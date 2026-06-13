# Droidspaces on LineageOS — Xiaomi 12T Pro (diting)

A small, repeatable toolkit that makes a **self-built LineageOS** kernel for the
Xiaomi 12T Pro / Redmi K50 Ultra (codename **diting**, SoC SM8475 "cape" / SM8450
"waipio", **android12-5.10 GKI**) able to run [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
— i.e. full Linux containers (Debian, Alpine, …) on the phone.

LineageOS ships a great kernel and updates it often, but it builds the GKI kernel
with `CONFIG_PID_NS` (and a few cgroup/IPC options) **disabled**, so container
runtimes fail with *"namespaces are not allowed in this kernel."* These options are
compile-time only — no root trick enables them at runtime. This toolkit re-enables
them cleanly and **re-applies in one command after every LineageOS update**.

> Generic prebuilt "Droidspaces kernels" are built against the **stock** vendor ABI
> and will bootloop on LineageOS (different module vermagic, no matching
> `vendor_dlkm`). Building from the LineageOS source — which rebuilds the kernel
> **and** all vendor modules together — is the only reliable path, and it's what
> this repo automates.

## What it does

* Appends the required namespace/cgroup/IPC kernel options to the device GKI config
  fragment (`droidspaces.config`).
* Optionally bakes in **KernelSU-Next** (GKI mode) for root, which Droidspaces needs.
* Is **idempotent and update-safe**: it resets the fragment to upstream first, so the
  result is identical every time, and re-running never duplicates anything.

## Requirements

* A Linux build host (instructions assume **Arch**), ~250 GB free disk, and enough
  RAM **+ swap** — `soong` peaks around 13 GB. With 16 GB RAM add a big swapfile.
* `repo`, `git`, `git-lfs`, `ccache`, `base-devel` (or your distro's AOSP build deps).
* The AOSP build tools run in **bash/zsh**, **not fish**.

## One-time setup

```bash
# 0) build deps (Arch example) + git-lfs MUST be installed and initialised
sudo pacman -S --needed git git-lfs base-devel ccache repo
git lfs install                      # CRITICAL — without it LFS blobs download as
                                     # text pointers -> SHA1 mismatch / corrupt APKs

# 1) get the source (keep --git-lfs)
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
repo sync -j"$(nproc)"

# 2) device + kernel + vendor trees
source build/envsetup.sh
breakfast diting

# 3) proprietary vendor blobs (breakfast does NOT pull these)
mkdir -p .repo/local_manifests
cp /path/to/this/repo/local_manifests/diting.xml .repo/local_manifests/
repo sync -j"$(nproc)"               # now pulls vendor/xiaomi/{diting,sm8450-common}

# 4) drop the scripts in the source root
cp /path/to/this/repo/apply-droidspaces.sh /path/to/this/repo/update.sh .
chmod +x apply-droidspaces.sh update.sh
```

## Build

```bash
./apply-droidspaces.sh               # config + KernelSU-Next  (WITH_KSU=0 to skip root)
ulimit -v unlimited                  # per-shell; prevents soong OOM-abort
source build/envsetup.sh
brunch diting
```

Flash the three images that the kernel config affects (keep backups first):

```bash
cd out/target/product/diting
fastboot flash boot boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot reboot fastboot             # fastbootd, needed for the logical vendor_dlkm
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot reboot
```

Then install the matching **KernelSU-Next manager** (`v3.2.0`) and the Droidspaces
app. Verify: `adb shell su -c 'droidspaces check'` → all namespaces green.

## Updating to a new LineageOS build / kernel

This is the whole point — one command, clean every time:

```bash
cd ~/android/lineage
./update.sh                          # resets our edits, repo sync, re-applies cleanly
ulimit -v unlimited
source build/envsetup.sh && brunch diting
```

## How it works (short)

* The kernel config comes from `gki_defconfig` + vendor fragments; the device fragment
  `arch/arm64/configs/vendor/diting_GKI.config` is merged **last**, so appending our
  options there overrides the GKI defaults (e.g. turns `PID_NS` back on).
* diting builds **every** kernel module from source (0 prebuilt `.ko`), so the kernel,
  `vendor_boot` and `vendor_dlkm` share one consistent ABI → no bootloop.
* `CONFIG_SYSVIPC` is deliberately **off**: the Android 16 VINTF matrix requires it
  disabled (`check_vintf` fails otherwise). IPC namespaces only need
  `(SYSVIPC || POSIX_MQUEUE)`, so `POSIX_MQUEUE` keeps `IPC_NS` working.

## Coexistence note (SUSFS users)

If you add SUSFS for root hiding, do **not** enable its *"hide sus mounts for all
processes"* option — it breaks Droidspaces container startup. Targeted hiding is fine.

## Troubleshooting (the gotchas, so you never hit them twice)

| Symptom | Cause / fix |
|---|---|
| `swapon: Invalid argument` | Btrfs swapfile — use `btrfs filesystem mkswapfile --size 32g /swapfile`, not `fallocate`. |
| `build/envsetup.sh ... Missing end ... if` | You're in **fish**. Run `bash` first. |
| soong exits code 1 silently, ~13 GB RSS | Memory/`ulimit`. Set `ulimit -v unlimited` and add swap. |
| `vendor/xiaomi/diting/...-vendor.mk does not exist` | Vendor blobs missing — add `local_manifests/diting.xml`, `repo sync`. |
| `SHA1 mismatch` (e.g. `abl.img`) / `failed opening zip` (webview.apk) | Git LFS not active → blobs are pointers. `git lfs install`, then `repo forall -c 'git lfs pull'`. |
| `check_vintf ... CONFIG_SYSVIPC ... required n` | Don't enable `SYSVIPC`; this toolkit already omits it. |

## Other devices

Adapt: the codename (`diting`), kernel path (`kernel/xiaomi/sm8450`), the GKI fragment
name (`*_GKI.config`), and the TheMuppets vendor repos in `local_manifests/`. The
`droidspaces.config` options themselves are device-agnostic for android12-5.10 GKI.

## Credits

LineageOS · [Droidspaces (ravindu644 / MGHazz)](https://github.com/ravindu644/Droidspaces-OSS) ·
[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) · TheMuppets (vendor blobs).
