#!/usr/bin/env bash
# Assemble and statically validate the nested super image. Never flashes a device.
set -Eeuo pipefail
usage() { echo "Usage: $0 <rootfs.squashfs> <boot.img> <exact-super-bytes> [rufomaculata.squashfs|-] [boot-mib] [output-dir]" >&2; exit 2; }
[[ $# -ge 3 && $# -le 6 ]] || usage
ROOTFS=$(readlink -f "$1"); BOOTIMG=$(readlink -f "$2"); SUPER_BYTES=$3
RUF=${4:--}; BOOT_MIB=${5:-6144}
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
OUTDIR=$(readlink -m "${6:-$ROOT/build-local/output-artifacts/final}")
[[ -s "$ROOTFS" && -s "$BOOTIMG" ]] || { echo 'Rootfs SquashFS and boot.img must both exist and be nonempty.' >&2; exit 1; }
[[ $SUPER_BYTES =~ ^[0-9]+$ ]] || { echo 'super size must be the exact integer capacity in bytes.' >&2; exit 2; }
mkdir -p "$OUTDIR"
[[ ! -e "$OUTDIR/super.img" ]] || { echo "Refusing to overwrite $OUTDIR/super.img; use a new output directory." >&2; exit 1; }
"$ROOT/scripts/inspect-android-boot-image.sh" "$BOOTIMG" "$OUTDIR/boot-inspection.txt"
sudo -v
sudo bash "$ROOT/build-super-image.sh" "$ROOTFS" "$OUTDIR/super.img" "$SUPER_BYTES" "$RUF" "$BOOT_MIB"
sudo bash "$ROOT/validate-super-image.sh" "$OUTDIR/super.img" "$((SUPER_BYTES / 4096 * 4096))" | tee "$OUTDIR/super-validation.txt"
install -m 0644 "$BOOTIMG" "$OUTDIR/boot.img"
install -m 0644 "$ROOTFS" "$OUTDIR/rootfs.squashfs"
if [[ $RUF != - ]]; then install -m 0644 "$(readlink -f "$RUF")" "$OUTDIR/rufomaculata.squashfs"; fi
cp "$OUTDIR/super.img.env" "$OUTDIR/super-image.env"
printf 'STATUS=prototype-not-for-flashing\n' > "$OUTDIR/STATUS.txt"
printf 'SCOPE=static validation only; no IN2017 hardware boot test has been performed\n' >> "$OUTDIR/STATUS.txt"
(
  cd "$OUTDIR"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
printf 'Assembled and validated inspection bundle: %s\n' "$OUTDIR"
echo 'WARNING: This is not a flashable release. Do not write it to the phone until the IN2017 boot path and recovery plan have been verified.'
