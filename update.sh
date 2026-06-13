#!/usr/bin/env bash
#
# update.sh
# ---------
# Safely update to the latest LineageOS build/kernel and re-apply the Droidspaces
# namespace config (and KernelSU-Next). Run from the LineageOS source root, in bash.
#
# It discards our local kernel edits FIRST so `repo sync` is conflict-free, pulls the
# latest, then re-applies everything cleanly via apply-droidspaces.sh.
#
set -euo pipefail
[ -d .repo ] || { echo "[!] Run from the LineageOS source root (.repo not found)."; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "[*] Discarding our local kernel edits so sync is clean..."
( cd kernel/xiaomi/sm8450 && git checkout -- . 2>/dev/null || true )

echo "[*] Syncing latest LineageOS sources..."
repo sync               # LineageOS defaults (-j4 -c) are deliberate; don't override

echo "[*] Re-applying Droidspaces (+ KernelSU-Next)..."
"$HERE/apply-droidspaces.sh"

echo
echo "[+] Update complete. Build with:"
echo "    bash; ulimit -v unlimited; source build/envsetup.sh; brunch diting"
