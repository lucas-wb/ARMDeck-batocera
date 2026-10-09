#!/usr/bin/env bash
# Static inspection gate for the generated Android boot image. This does not
# prove device bootability; it verifies the built handoff is actually present.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <boot.img> <report.txt>" >&2
  exit 2
fi
boot_img=$(readlink -f "$1")
report=$(readlink -m "$2")
[[ -s "$boot_img" ]] || { echo "Missing or empty boot image: $boot_img" >&2; exit 1; }

if command -v unpack_bootimg.py >/dev/null 2>&1; then
  unpacker=$(command -v unpack_bootimg.py)
elif command -v unpack_bootimg >/dev/null 2>&1; then
  unpacker=$(command -v unpack_bootimg)
else
  echo 'Required Android tool not found: unpack_bootimg.py or unpack_bootimg' >&2
  exit 1
fi
for tool in file cpio gzip grep find sort; do
  command -v "$tool" >/dev/null || { echo "Required inspection tool not found: $tool" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$(dirname "$report")" "$work/unpacked"
if ! "$unpacker" --boot_img "$boot_img" --out "$work/unpacked" >"$work/unpack.log" 2>&1; then
  cat "$work/unpack.log" >&2
  echo 'Android boot image could not be unpacked.' >&2
  exit 1
fi
ramdisk="$work/unpacked/ramdisk"
kernel="$work/unpacked/kernel"
[[ -s "$kernel" ]] || { echo 'Unpacked boot image has no kernel.' >&2; exit 1; }
[[ -s "$ramdisk" ]] || { echo 'Unpacked boot image has no ramdisk.' >&2; exit 1; }

ramdisk_type=$(file -b "$ramdisk")
case "$ramdisk_type" in
  *gzip*) gzip -dc "$ramdisk" > "$work/ramdisk.cpio" ;;
  *LZ4*)
    command -v lz4 >/dev/null || { echo 'Ramdisk is LZ4-compressed but lz4 is unavailable.' >&2; exit 1; }
    lz4 -dc "$ramdisk" > "$work/ramdisk.cpio"
    ;;
  *XZ*)
    command -v xz >/dev/null || { echo 'Ramdisk is XZ-compressed but xz is unavailable.' >&2; exit 1; }
    xz -dc "$ramdisk" > "$work/ramdisk.cpio"
    ;;
  *Zstandard*)
    command -v zstd >/dev/null || { echo 'Ramdisk is Zstandard-compressed but zstd is unavailable.' >&2; exit 1; }
    zstd -dc "$ramdisk" > "$work/ramdisk.cpio"
    ;;
  *ASCII\ cpio\ archive*|*cpio\ archive*) cp "$ramdisk" "$work/ramdisk.cpio" ;;
  *)
    echo "Unsupported ramdisk compression/format: $ramdisk_type" >&2
    exit 1
    ;;
esac

# Reject suspicious archive paths before extraction. This is a build artifact,
# but the guard avoids writing outside the temporary inspection directory.
(cd "$work" && cpio -it --quiet < ramdisk.cpio) > "$work/ramdisk-files.txt"
if grep -E '(^/|(^|/)\.\.(/|$))' "$work/ramdisk-files.txt"; then
  echo 'Ramdisk archive contains an absolute or parent-traversal path; refusing extraction.' >&2
  exit 1
fi
mkdir "$work/root"
(cd "$work/root" && cpio -idm --quiet --no-absolute-filenames < ../ramdisk.cpio)

required_files=(init init.batocera)
for path in "${required_files[@]}"; do
  [[ -s "$work/root/$path" ]] || { echo "Required ramdisk file missing: /$path" >&2; exit 1; }
done

for marker in 'armdeck.batocera=1' 'BATOCERA_BOOT_DEV' 'kpartx' 'blkid' '/dev/mapper/' 'exec /init.batocera'; do
  if ! grep -R -F -q -- "$marker" "$work/root"; then
    echo "Required Batocera handoff marker missing from ramdisk: $marker" >&2
    exit 1
  fi
done

: > "$work/executable-paths.txt"
for executable in kpartx blkid; do
  executable_path=$(find "$work/root" -name "$executable" -perm /111 -print -quit)
  if [[ -z "$executable_path" ]]; then
    echo "Required executable missing from initramfs: $executable" >&2
    exit 1
  fi
  printf '%s=%s\n' "$executable" "${executable_path#"$work/root"}" >> "$work/executable-paths.txt"
done

{
  echo 'RESULT=PASS'
  echo 'SCOPE=static boot-image and ramdisk inspection; not a hardware boot test'
  echo "BOOT_IMAGE=$boot_img"
  echo "BOOT_IMAGE_SHA256=$(sha256sum "$boot_img" | awk '{print $1}')"
  echo "BOOT_IMAGE_BYTES=$(stat -c '%s' "$boot_img")"
  echo "KERNEL_BYTES=$(stat -c '%s' "$kernel")"
  echo "RAMDISK_BYTES=$(stat -c '%s' "$ramdisk")"
  echo "RAMDISK_FORMAT=$ramdisk_type"
  echo
  echo '--- unpack_bootimg output ---'
  cat "$work/unpack.log"
  echo
  echo '--- required handoff files ---'
  printf '/%s\n' "${required_files[@]}"
  echo
  echo '--- required executable paths ---'
  cat "$work/executable-paths.txt"
  echo
  echo '--- relevant ramdisk paths ---'
  grep -E '(^|/)(init|init\.batocera|.*init_2nd.*|.*kernel-cmdline.*)$' "$work/ramdisk-files.txt" || true
  echo
  echo '--- handoff markers ---'
  printf '%s\n' 'armdeck.batocera=1' 'BATOCERA_BOOT_DEV' 'kpartx' 'blkid' '/dev/mapper/' 'exec /init.batocera'
} > "$report"
cat "$report"
