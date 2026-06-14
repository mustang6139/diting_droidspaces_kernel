#!/usr/bin/env bash
#
# apply-droidspaces.sh
# --------------------
# Make a (freshly synced) LineageOS source tree for the Xiaomi 12T Pro (diting)
# Droidspaces-capable, by enabling the required kernel namespace/cgroup options.
#
# Idempotent & update-safe: run it after EVERY `repo sync`. It first resets the
# device kernel config fragment to upstream, then re-appends our block, so the
# result is identical whether the tree is fresh or already patched. Re-running
# never duplicates anything.
#
# Usage (from the LineageOS source root):
#   This script itself runs fine from fish. Call it directly.
#   The *build* step after this (source build/envsetup.sh && brunch) needs bash though.
#
#   ./apply-droidspaces.sh                 # config + KernelSU-Next (root for containers)
#   WITH_KSU=0 ./apply-droidspaces.sh      # only the namespace config, no root baked in
#   KSU_TAG=v3.2.0 ./apply-droidspaces.sh  # pin a specific KernelSU-Next release
#
set -euo pipefail

KSOURCE="kernel/xiaomi/sm8450"
FRAG_REL="arch/arm64/configs/vendor/diting_GKI.config"
FRAG="$KSOURCE/$FRAG_REL"
WITH_KSU="${WITH_KSU:-1}"
KSU_TAG="${KSU_TAG:-v3.2.0}"

[ -d .repo ]   || { echo "[!] Run this from the LineageOS source root (.repo not found)."; exit 1; }
[ -f "$FRAG" ] || { echo "[!] Missing $FRAG — run 'repo sync' + 'breakfast diting' first."; exit 1; }

# --- 1. Droidspaces kernel config (deterministic: reset fragment, then append) ---
git -C "$KSOURCE" checkout -- "$FRAG_REL" 2>/dev/null || true   # drop any previous block

cat >> "$FRAG" <<'EOF'

# >>> droidspaces >>>  (added by apply-droidspaces.sh)
# Namespaces + cgroups + IPC for container runtimes (Droidspaces).
# CONFIG_SYSVIPC is intentionally NOT set: the Android 16 VINTF matrix requires it
# disabled. IPC namespaces stay available via CONFIG_POSIX_MQUEUE instead.
CONFIG_POSIX_MQUEUE=y
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG=y
CONFIG_CGROUP_SCHED=y
CONFIG_FAIR_GROUP_SCHED=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_DEVTMPFS=y
CONFIG_OVERLAY_FS=y
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_NF_TABLES=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NF_CONNTRACK_NETLINK=y
CONFIG_NF_NAT_REDIRECT=y
# <<< droidspaces <<<

# >>> docker >>>
# iptables/netfilter support so Docker doesn't complain about missing chains
CONFIG_BRIDGE_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_NAT=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_NAT=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_NETFILTER_XT_MATCH_CONNTRACK=y
CONFIG_NETFILTER_XT_MARK=y
# resource limits (optional but useful)
CONFIG_CPUSETS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CFS_BANDWIDTH=y
# <<< docker <<<
EOF
echo "[+] Droidspaces + Docker config applied -> $FRAG"

# --- 2. Root via KernelSU-Next (optional; Droidspaces needs root) ----------------
# Update-safe: after a re-sync the driver wiring is gone even if the clone dir
# lingers, so we detect the actual wiring and (re)integrate cleanly if needed.
if [ "$WITH_KSU" = "1" ]; then
  if grep -q "kernelsu" "$KSOURCE/drivers/Makefile" 2>/dev/null; then
    echo "[=] KernelSU-Next already wired into the kernel tree."
  else
    echo "[*] Integrating KernelSU-Next $KSU_TAG ..."
    rm -rf "$KSOURCE/KernelSU-Next" "$KSOURCE/drivers/kernelsu"
    ( cd "$KSOURCE" && \
      curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" \
      | bash -s "$KSU_TAG" )
    echo "[+] KernelSU-Next $KSU_TAG integrated."
  fi
  grep -q "^CONFIG_KSU=y" "$FRAG" || printf '\nCONFIG_KSU=y\n' >> "$FRAG"
  echo "    (install the matching KernelSU-Next manager $KSU_TAG on the phone)"
fi

cat <<'EOF'

────────────────────────────────────────────────────────────────────
Ready. Build and flash:

  bash                                   # AOSP build needs bash - if you use fish
  ulimit -v unlimited                    # per-shell; prevents soong OOM-abort
  source build/envsetup.sh
  brunch diting

  out/target/product/diting/{boot.img,vendor_boot.img,vendor_dlkm.img}
  fastboot flash boot boot.img
  fastboot flash vendor_boot vendor_boot.img
  fastboot reboot fastboot
  fastboot flash vendor_dlkm vendor_dlkm.img
  fastboot reboot

Verify:  adb shell su -c 'droidspaces check'   (all namespaces green)
────────────────────────────────────────────────────────────────────
EOF
