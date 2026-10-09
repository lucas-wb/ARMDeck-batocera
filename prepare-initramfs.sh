#!/usr/bin/env bash
# Stage the Batocera init script into an ARMDeck/postmarketOS initramfs tree.
# This does not rebuild the ramdisk or flash a phone.
set -Eeuo pipefail

usage() { echo "Usage: sudo $0 ARMDECK_INITRAMFS_ROOT BATOCERA_INIT_SOURCE" >&2; }
[[ $# -eq 2 ]] || { usage; exit 2; }
ROOT=$(readlink -f "$1")
BATOCERA_INIT=$(readlink -f "$2")
[[ $EUID -eq 0 ]] || { echo 'ERROR: run as root to preserve init ownership and mode.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'ERROR: python3 is required on the build host.' >&2; exit 1; }
[[ -d "$ROOT" && -f "$BATOCERA_INIT" ]] || { echo 'ERROR: initramfs root or Batocera init source is missing.' >&2; exit 1; }
[[ -x "$ROOT/bin/ash" ]] || { echo "ERROR: $ROOT/bin/ash is missing; expected ARMDeck initramfs tree." >&2; exit 1; }
[[ ! -e "$ROOT/init.batocera" ]] || { echo 'ERROR: init.batocera already exists; refusing to overwrite.' >&2; exit 1; }

find_exec() {
  local name=$1 path
  for path in "$ROOT/sbin/$name" "$ROOT/bin/$name" "$ROOT/usr/sbin/$name" "$ROOT/usr/bin/$name"; do
    [[ -x "$path" ]] && { printf '%s\n' "$path"; return 0; }
  done
  return 1
}
for tool in kpartx blkid mount switch_root; do
  find_exec "$tool" >/dev/null || { echo "ERROR: required executable '$tool' missing from ARMDeck initramfs." >&2; exit 1; }
done

# Patch only the copied stock init. ARMDeck's wrapper mounts devtmpfs before kpartx
# and exports BATOCERA_BOOT_DEV so no generated UUID must be baked into boot.img.
COUNT=$(grep -Fxc '    mount -t devtmpfs none /dev' "$BATOCERA_INIT" || true)
[[ "$COUNT" == 1 ]] || { echo "ERROR: expected exactly one stock devtmpfs mount line; found $COUNT." >&2; exit 1; }
COUNT=$(grep -Fxc '    MOUNTOPTIONS=none' "$BATOCERA_INIT" || true)
[[ "$COUNT" == 1 ]] || { echo "ERROR: expected exactly one MOUNTOPTIONS initialization; found $COUNT." >&2; exit 1; }
TEMP=$(mktemp "$ROOT/.init.batocera.XXXXXX")
cleanup() { rm -f "$TEMP"; }
trap cleanup EXIT
python3 - "$BATOCERA_INIT" "$TEMP" <<'PYTHON'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
old_dev = '    mount -t devtmpfs none /dev'
new_dev = "    # ARMDeck mounted devtmpfs before kpartx. Avoid hiding /dev/mapper nodes.\n    grep -q ' /dev devtmpfs ' /proc/mounts || mount -t devtmpfs none /dev"
old_mount = '    MOUNTOPTIONS=none\n    while [ $boot_root_mounted = n ]'
new_mount = '''    MOUNTOPTIONS=none
    # ARMDeck resolves the nested boot filesystem and exports it. Keep the stock
    # dev/label/uuid lookup as fallback for ordinary Batocera boots.
    if [ -n "${BATOCERA_BOOT_DEV:-}" ]
    then
        MOUNTARG=${BATOCERA_BOOT_DEV}
        if do_mount "${MOUNTARG}"; then boot_root_mounted=y; else return 1; fi
        echo "Mounted ${MOUNTARG} as /boot_root"
    fi
    while [ $boot_root_mounted = n ]'''
if src.count(old_dev) != 1 or src.count(old_mount) != 1:
    raise SystemExit('ERROR: stock Batocera init does not match expected patch context')
src = src.replace(old_dev, new_dev).replace(old_mount, new_mount)
pathlib.Path(sys.argv[2]).write_text(src)
PYTHON
chmod --reference="$BATOCERA_INIT" "$TEMP"
chown 0:0 "$TEMP"
grep -Fq 'BATOCERA_BOOT_DEV:-' "$TEMP" || { echo 'ERROR: boot-device patch failed.' >&2; exit 1; }
mv "$TEMP" "$ROOT/init.batocera"
install -o 0 -g 0 -m 0755 "$(dirname "$(readlink -f "$0")")/init" "$ROOT/init"
trap - EXIT
printf '%s\n' 'ARMDeck Batocera init staged.' \
  'Review the initramfs tool/applet list, then rebuild the Android boot image.' \
  'No phone partitions were accessed or modified.'
