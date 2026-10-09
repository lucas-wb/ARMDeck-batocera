#!/usr/bin/env bash
# Build a two-partition disk image intended to live INSIDE Android super.
# This does not flash anything. Run as root on Linux/WSL with loop-device support.
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sudo ./build-super-image.sh ROOTFS_SQUASHFS OUTPUT.img SUPER_BYTES [RUFOMACULATA_SQUASHFS] [BOOT_MIB]

ROOTFS_SQUASHFS       Batocera's built rootfs.squashfs
OUTPUT.img            Output raw image containing MBR + boot/data ext4 partitions
SUPER_BYTES           Exact physical super partition capacity from fastboot getvar
RUFOMACULATA_SQUASHFS Optional Batocera extra SquashFS layer; use '-' to omit
BOOT_MIB              Boot filesystem size, default 6144 MiB

Outputs alongside OUTPUT.img:
  OUTPUT.img.sparse   Android sparse image, if img2simg is installed
  OUTPUT.img.env      Generated boot UUID, userdata UUID, and kernel args

The script deliberately refuses to run unless root and all required tools exist.
It never flashes or writes to a physical device.
USAGE
}

[[ $# -ge 3 && $# -le 5 ]] || { usage >&2; exit 2; }
ROOTFS=$(readlink -f "$1")
OUT=$(readlink -m "$2")
SUPER_BYTES=$3
RUFOMACULATA=${4:--}
BOOT_MIB=${5:-6144}

[[ $EUID -eq 0 ]] || { echo 'ERROR: run with sudo; loop mounts are required.' >&2; exit 1; }
[[ -f "$ROOTFS" ]] || { echo "ERROR: squashfs not found: $ROOTFS" >&2; exit 1; }
if [[ "$RUFOMACULATA" != "-" ]]; then
  RUFOMACULATA=$(readlink -f "$RUFOMACULATA")
  [[ -f "$RUFOMACULATA" ]] || { echo "ERROR: rufomaculata squashfs not found: $RUFOMACULATA" >&2; exit 1; }
fi
[[ $SUPER_BYTES =~ ^[0-9]+$ ]] || { echo 'ERROR: SUPER_BYTES must be an integer.' >&2; exit 2; }
[[ $BOOT_MIB =~ ^[0-9]+$ ]] || { echo 'ERROR: BOOT_MIB must be an integer.' >&2; exit 2; }
for cmd in readlink truncate sfdisk losetup mkfs.ext4 mount umount blkid blockdev install sync du df awk tail tr seq stat; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing required tool: $cmd" >&2; exit 1; }
done

# Leave room for alignment and the partition table; do not guess the phone's size.
IMAGE_BYTES=$((SUPER_BYTES / 4096 * 4096))
BOOT_BYTES=$((BOOT_MIB * 1024 * 1024))
ALIGN=$((4 * 1024 * 1024))
BOOT_START=$ALIGN
BOOT_SECTORS=$((BOOT_BYTES / 512))
DATA_START=$(( (BOOT_START / 512 + BOOT_SECTORS + 8191) / 8192 * 8192 ))
TOTAL_SECTORS=$((IMAGE_BYTES / 512))
DATA_SECTORS=$((TOTAL_SECTORS - DATA_START - 8192))
(( DATA_SECTORS > 0 )) || { echo 'ERROR: image too small for requested boot partition.' >&2; exit 1; }
(( BOOT_START + BOOT_BYTES < IMAGE_BYTES )) || { echo 'ERROR: boot partition exceeds image size.' >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
[[ ! -e "$OUT" ]] || { echo "ERROR: refusing to overwrite existing file: $OUT" >&2; exit 1; }
WORK=$(mktemp -d)
LOOP=''
cleanup() {
  set +e
  if [[ -n "$LOOP" ]]; then
    umount "$WORK/boot" "$WORK/data" 2>/dev/null
    losetup -d "$LOOP" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/boot" "$WORK/data"

# Sparse raw image, partition table lives inside the image flashed to super.
truncate -s "$IMAGE_BYTES" "$OUT"
sfdisk "$OUT" <<PARTITIONS
label: dos
unit: sectors
start=$((BOOT_START / 512)), size=$BOOT_SECTORS, type=83, bootable
start=$DATA_START, size=$DATA_SECTORS, type=83
PARTITIONS

LOOP=$(losetup --find --show --partscan "$OUT")
udevadm settle 2>/dev/null || true
BOOT_DEV="${LOOP}p1"
DATA_DEV="${LOOP}p2"
for _ in $(seq 1 20); do [[ -b "$BOOT_DEV" && -b "$DATA_DEV" ]] && break; sleep 0.25; done
[[ -b "$BOOT_DEV" && -b "$DATA_DEV" ]] || { echo "ERROR: loop partition devices not created for $LOOP" >&2; exit 1; }

mkfs.ext4 -F -L BATOCERA_BOOT "$BOOT_DEV" >/dev/null
mkfs.ext4 -F -L BATOCERA_DATA "$DATA_DEV" >/dev/null
mount "$BOOT_DEV" "$WORK/boot"
mount "$DATA_DEV" "$WORK/data"
mkdir -p "$WORK/boot/boot" "$WORK/data/batocera" \
  "$WORK/data/batocera/roms" "$WORK/data/batocera/bios" \
  "$WORK/data/batocera/saves" "$WORK/data/batocera/system"
install -m 0644 "$ROOTFS" "$WORK/boot/boot/batocera"
if [[ "$RUFOMACULATA" != "-" ]]; then
  install -m 0644 "$RUFOMACULATA" "$WORK/boot/boot/rufomaculata"
fi
# Fail before success if the selected SquashFS layers do not fit.
BOOT_USED=$(du -sb "$WORK/boot" | awk '{print $1}')
BOOT_AVAIL=$(df -B1 --output=avail "$WORK/boot" | tail -n 1 | tr -d ' ')
if (( BOOT_USED > BOOT_BYTES - 64*1024*1024 || BOOT_AVAIL < 64*1024*1024 )); then
  echo "ERROR: boot files use ${BOOT_USED} bytes; increase BOOT_MIB (current ${BOOT_MIB} MiB)." >&2
  exit 1
fi
cat > "$WORK/boot/batocera-boot.conf" <<CONF
# ARMDeck phone integration; Batocera stock share service.
sharedevice=DEV $(blkid -s UUID -o value "$DATA_DEV")
autoresize=false
CONF
sync
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_DEV")
DATA_UUID=$(blkid -s UUID -o value "$DATA_DEV")
umount "$WORK/boot" "$WORK/data"
losetup -d "$LOOP"
LOOP=''

cat > "${OUT}.env" <<ENV
# The boot filesystem has the fixed label BATOCERA_BOOT; no generated boot UUID
# needs to be baked into the Android boot image.
BATOCERA_BOOT_UUID=${BOOT_UUID}
BATOCERA_DATA_UUID=${DATA_UUID}
# Add superdev=<verified Linux block path> to Android boot-image kernel args.
# Do not assume /dev/sda14 until confirmed on the actual IN2017 booted kernel.
ENV

if command -v img2simg >/dev/null 2>&1; then
  img2simg "$OUT" "${OUT}.sparse"
  echo "Created sparse image: ${OUT}.sparse"
else
  echo 'NOTE: img2simg unavailable; only raw image created. Install Android sparse tools before flashing.' >&2
fi

echo "Created image: $OUT"
echo "Capacity: $IMAGE_BYTES bytes; boot UUID: $BOOT_UUID; userdata UUID: $DATA_UUID"
echo 'No phone partitions were accessed or modified.'
