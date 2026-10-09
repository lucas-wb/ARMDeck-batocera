#!/usr/bin/env bash
# Read-only validation of a generated raw nested-partition image. Never flashes.
set -Eeuo pipefail

usage() { echo "Usage: sudo $0 IMAGE.img EXPECTED_SUPER_BYTES" >&2; }
[[ $# -eq 2 ]] || { usage; exit 2; }
IMAGE=$(readlink -f "$1")
EXPECTED_BYTES=$2
[[ $EUID -eq 0 ]] || { echo 'ERROR: run as root for loop/mount checks.' >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "ERROR: image not found: $IMAGE" >&2; exit 1; }
[[ $EXPECTED_BYTES =~ ^[0-9]+$ ]] || { echo 'ERROR: expected byte count must be an integer.' >&2; exit 2; }
for cmd in readlink stat sfdisk losetup blkid mount umount mountpoint file grep seq; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing tool: $cmd" >&2; exit 1; }
done
ACTUAL_BYTES=$(stat -c '%s' "$IMAGE")
(( ACTUAL_BYTES == EXPECTED_BYTES )) || { echo "ERROR: image size $ACTUAL_BYTES != expected $EXPECTED_BYTES" >&2; exit 1; }

WORK=$(mktemp -d)
LOOP=
cleanup() {
  set +e
  mountpoint -q "$WORK/boot" && umount "$WORK/boot"
  mountpoint -q "$WORK/data" && umount "$WORK/data"
  [[ -n "$LOOP" ]] && losetup -d "$LOOP"
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/boot" "$WORK/data"
LOOP=$(losetup --find --show --read-only --partscan "$IMAGE")
for _ in $(seq 1 20); do [[ -b "${LOOP}p1" && -b "${LOOP}p2" ]] && break; sleep 0.25; done
[[ -b "${LOOP}p1" && -b "${LOOP}p2" ]] || { echo 'ERROR: two partition nodes not created' >&2; exit 1; }

sfdisk --verify "$IMAGE"
BOOT_TYPE=$(blkid -s TYPE -o value "${LOOP}p1")
DATA_TYPE=$(blkid -s TYPE -o value "${LOOP}p2")
BOOT_UUID=$(blkid -s UUID -o value "${LOOP}p1")
DATA_UUID=$(blkid -s UUID -o value "${LOOP}p2")
[[ "$BOOT_TYPE" == ext4 && "$DATA_TYPE" == ext4 ]] || { echo "ERROR: expected ext4/ext4; got $BOOT_TYPE/$DATA_TYPE" >&2; exit 1; }
[[ -n "$BOOT_UUID" && -n "$DATA_UUID" && "$BOOT_UUID" != "$DATA_UUID" ]] || { echo 'ERROR: filesystem UUIDs missing or duplicated' >&2; exit 1; }
mount -o ro "${LOOP}p1" "$WORK/boot"
mount -o ro "${LOOP}p2" "$WORK/data"
[[ -s "$WORK/boot/boot/batocera" ]] || { echo 'ERROR: missing /boot/batocera SquashFS' >&2; exit 1; }
file "$WORK/boot/boot/batocera" | grep -qi 'squashfs' || { echo 'ERROR: /boot/batocera is not recognized as SquashFS' >&2; exit 1; }
[[ -d "$WORK/data/batocera/roms" && -d "$WORK/data/batocera/bios" && -d "$WORK/data/batocera/saves" && -d "$WORK/data/batocera/system" ]] || { echo 'ERROR: userdata directory layout is incomplete' >&2; exit 1; }
grep -Fx "sharedevice=DEV $DATA_UUID" "$WORK/boot/batocera-boot.conf" >/dev/null || { echo 'ERROR: sharedevice does not match userdata UUID' >&2; exit 1; }
grep -Fx 'autoresize=false' "$WORK/boot/batocera-boot.conf" >/dev/null || { echo 'ERROR: autoresize=false missing' >&2; exit 1; }
echo "PASS: image size $ACTUAL_BYTES bytes; MBR valid; ext4 boot/data UUIDs distinct; SquashFS and userdata layout present."
echo "BATOCERA_BOOT_UUID=$BOOT_UUID"
echo "BATOCERA_DATA_UUID=$DATA_UUID"
echo 'No physical device was accessed.'
