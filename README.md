# Droidspaces on LineageOS — Xiaomi 12T Pro (diting)

> *Or: how I turned a perfectly good paperweight into a perfectly good homelab.*

## The backstory (skip if you just want the commands)

So I had this Xiaomi 12T Pro sitting in a drawer. Couldn't sell it anymore —
market value had dropped to "yeah, good luck with that". Couldn't throw it away
— felt wrong, it's a great piece of hardware. Couldn't *not* use it — that felt
even worse.

Then I had The Idea™: **what if I run Linux on it and make a tiny homelab?**

Naturally I Googled my way through the usual options:

- **Termux** — great, but it's essentially a sandbox with a terminal stapled on.
  No real namespaces, no containers, forget it.
- **proot** — fakes a filesystem root. Cute, but half your syscalls are emulated
  and the other half just lie to you.
- **Emulators** — bless their hearts.

Then I found [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS). Full
Linux containers. Real namespaces. Actual hardware access. *chef's kiss*

There was just one small problem.

The kernel didn't support it.

**Of course it didn't.**

LineageOS builds the GKI kernel with `CONFIG_PID_NS` (and a bunch of
namespace/cgroup options) turned off. These are compile-time switches — no root
trick, no Magisk module, no amount of praying will enable them at runtime. You
have to rebuild the kernel.

So I did. I downloaded the entire LineageOS source tree (~400 GB, yes, really),
found the device kernel config fragment, added the missing options, rebuilt
everything from scratch, flashed it, and — **it worked**. Full containers on the
phone. My own tiny homelab running Debian on a 2022 flagship that was otherwise
heading for the drawer of forgotten gadgets.

This repo is the toolkit I put together so I never have to remember what I did,
and so that if you're in the same situation, you don't have to figure it out
from scratch either.

It's a small set of scripts and configs. Nothing fancy. Home-assembled, slightly
over-engineered, shared in the hope it saves someone a weekend.

---

## What this actually does

* Appends the required namespace/cgroup/IPC kernel options to the device GKI
  config fragment (`diting_GKI.config`).
* Optionally bakes in **KernelSU-Next** (GKI mode) for root, which Droidspaces
  needs to do its thing.
* Is **idempotent and update-safe**: resets the fragment to upstream first, so
  the result is always identical, and re-running after a LineageOS update never
  duplicates anything. Just run it, build, flash, done.

> **Why not use a prebuilt Droidspaces kernel?**
> Generic "Droidspaces kernels" floating around the internet are built against the
> **stock** Xiaomi vendor ABI. On LineageOS they bootloop — different module
> vermagic, no matching `vendor_dlkm`. Building from the LineageOS source
> rebuilds the kernel *and* all vendor modules together with a consistent ABI.
> It's the only path that actually works, and yes, it takes a while.

---

## Requirements

* A Linux build host (these instructions assume **Arch**; adapt as needed).
* **~400 GB free disk space.** Yes, really. LineageOS 21+ needs that much, plus
  extra if you enable ccache (worth it). SSDs make a huge difference here.
* **RAM:** LineageOS officially recommends 64 GB for lineage-21+. In practice,
  16 GB + a big swapfile works, but `soong` peaks around 13 GB and will
  OOM-abort without the swap. Don't ask how I know.
* `repo`, `git`, `git-lfs`, `ccache`, `base-devel` (or your distro's AOSP build deps).
* The AOSP build tools want **bash** or **zsh**. Not fish. Fish will betray you.

---

## One-time setup

```bash
# 0) build deps (Arch) — git-lfs MUST be installed AND initialised
sudo pacman -S --needed git git-lfs base-devel ccache repo
git lfs install      # CRITICAL — skip this and blobs download as text pointers
                     # -> SHA1 mismatch -> corrupt APKs -> fun debugging session

# 1) get the source (grab a coffee, maybe lunch too)
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs --no-clone-bundle
repo sync                  # don't add -j here; LineageOS defaults (-j4 -c) are deliberate

# 2) device + kernel + vendor trees
source build/envsetup.sh
breakfast diting

# 3) proprietary vendor blobs (breakfast does NOT pull these automatically)
mkdir -p .repo/local_manifests
cp /path/to/this/repo/diting.xml .repo/local_manifests/
repo sync                  # now pulls vendor/xiaomi/{diting,sm8450-common}

# 4) drop the scripts in the source root
cp /path/to/this/repo/apply-droidspaces.sh /path/to/this/repo/update.sh .
chmod +x apply-droidspaces.sh update.sh
```

---

## Build

```bash
./apply-droidspaces.sh          # apply config + integrate KernelSU-Next
                                # (use WITH_KSU=0 if you don't want root baked in)
ulimit -v unlimited             # per-shell; prevents soong from OOM-aborting
source build/envsetup.sh
brunch diting
```

Then flash the three images the kernel config affects. **Back up your current ones first** — or live dangerously, I'm not your mom.

```bash
cd out/target/product/diting
fastboot flash boot boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot reboot fastboot                    # fastbootd, needed for the logical partition
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot reboot
```

Install the matching **KernelSU-Next manager** (`v3.2.0`) and the Droidspaces app.

Verify everything is happy:

```bash
adb shell su -c 'droidspaces check'
# → all namespaces green
# → tiny internal celebration
```

---

## Updating after a LineageOS build / kernel update

This is the whole point of the toolkit — one command, clean every time:

```bash
cd ~/android/lineage
./update.sh               # resets our edits, repo sync, re-applies everything
ulimit -v unlimited
source build/envsetup.sh && brunch diting
```

Go make coffee. Or dinner. Or sleep. Come back, flash, done.

---

## How it works (the nerdy part)

The GKI kernel config is assembled from `gki_defconfig` plus vendor fragments,
merged in order. The device fragment
`arch/arm64/configs/vendor/diting_GKI.config` is merged **last**, which means
anything we append there wins over the GKI defaults — including turning
`CONFIG_PID_NS` back on.

The diting device builds **every** kernel module from source (zero prebuilt
`.ko` files), so the kernel, `vendor_boot`, and `vendor_dlkm` all share one
consistent ABI. No bootloop. This is also why you have to flash all three images.

**Why no `CONFIG_SYSVIPC`?** The Android 16 VINTF compatibility matrix requires
it disabled — enabling it makes `check_vintf` fail at build time. Fortunately,
IPC namespaces only need `(SYSVIPC || POSIX_MQUEUE)`, so `CONFIG_POSIX_MQUEUE=y`
keeps `CONFIG_IPC_NS` working without upsetting the VINTF police.

---

## Coexistence note (SUSFS users)

If you layer SUSFS on top for root hiding: **do not** enable the
*"hide sus mounts for all processes"* option. It breaks Droidspaces container
startup. Targeted process hiding is fine.

---

## Troubleshooting

The gotchas I already hit, so you don't have to:

| Symptom | Cause / fix |
|---|---|
| `swapon: Invalid argument` | Btrfs swapfile — use `btrfs filesystem mkswapfile --size 32g /swapfile`, not `fallocate`. Classic. |
| `build/envsetup.sh ... Missing end ... if` | You're in **fish**. Run `bash` first. Every time. |
| soong exits silently with code 1, ~13 GB RSS | Memory / `ulimit`. Set `ulimit -v unlimited` and add swap. A lot of swap. |
| `vendor/xiaomi/diting/...-vendor.mk does not exist` | Vendor blobs missing — add `diting.xml` to `.repo/local_manifests/`, then `repo sync`. |
| `SHA1 mismatch` (e.g. `abl.img`) / `failed opening zip` (webview.apk) | Git LFS not active — blobs downloaded as text pointers. Run `git lfs install`, then `repo forall -c 'git lfs pull'`. |
| `check_vintf ... CONFIG_SYSVIPC ... required n` | Don't enable `SYSVIPC`. This toolkit already leaves it off on purpose. |

---

## Adapting to other devices

The namespace/cgroup options in `droidspaces.config` are device-agnostic for
android12-5.10 GKI. To adapt: swap the codename (`diting`), kernel path
(`kernel/xiaomi/sm8450`), GKI fragment name (`*_GKI.config`), and the
TheMuppets vendor repos in the local manifest.

---

## Credits

LineageOS · [Droidspaces (ravindu644 / MGHazz)](https://github.com/ravindu644/Droidspaces-OSS) ·
[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) · TheMuppets (vendor blobs) ·
and whoever invented coffee, without which none of this would have been possible.
