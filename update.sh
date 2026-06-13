#!/usr/bin/env bash
#
# update.sh
# ---------
# Safely update to the latest LineageOS build/kernel and re-apply the Droidspaces
# namespace config (and KernelSU-Next).
#
# Run from the LineageOS source root. This script itself is fine to run from fish.
# After it finishes, the build step still needs bash:
#   bash; ulimit -v unlimited; source build/envsetup.sh; brunch diting
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
echo "[+] Update complete. Now build (needs bash, not fish):"
echo "    bash"
echo "    ulimit -v unlimited"
echo "    source build/envsetup.sh && brunch diting"
