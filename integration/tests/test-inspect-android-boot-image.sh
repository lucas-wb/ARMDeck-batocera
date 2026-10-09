#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/root"
cat > "$tmp/bin/unpack_bootimg.py" <<'UNPACKER'
#!/usr/bin/env bash
set -euo pipefail
out=''
while (($#)); do
  case "$1" in
    --boot_img) shift 1 ;;
    --out) out=$2; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$out"
printf 'synthetic-kernel\n' > "$out/kernel"
cp "$TEST_RAMDISK" "$out/ramdisk"
printf 'synthetic boot header details\n'
UNPACKER
chmod +x "$tmp/bin/unpack_bootimg.py"
make_ramdisk() {
  local with_markers=$1
  rm -rf "$tmp/root"
  mkdir -p "$tmp/root/sbin"
  printf '#!/bin/sh\n' > "$tmp/root/sbin/kpartx"
  printf '#!/bin/sh\n' > "$tmp/root/sbin/blkid"
  chmod +x "$tmp/root/sbin/kpartx" "$tmp/root/sbin/blkid"
  if [[ $with_markers == yes ]]; then
    cat > "$tmp/root/init" <<'INIT'
# armdeck.batocera=1
kpartx
BATOCERA_BOOT_DEV
/dev/mapper/
blkid
exec /init.batocera
INIT
  else
    printf '# no handoff configured\n' > "$tmp/root/init"
  fi
  printf '#!/bin/sh\n' > "$tmp/root/init.batocera"
  (cd "$tmp/root" && find . -type f -print0 | cpio --null -o -H newc --quiet) | gzip -c > "$tmp/ramdisk.gz"
  export TEST_RAMDISK="$tmp/ramdisk.gz"
}
printf 'synthetic boot image\n' > "$tmp/boot.img"
export PATH="$tmp/bin:$PATH"
make_ramdisk yes
bash "$repo_root/scripts/inspect-android-boot-image.sh" "$tmp/boot.img" "$tmp/pass-report.txt" >/dev/null
grep -Fx 'RESULT=PASS' "$tmp/pass-report.txt" >/dev/null
make_ramdisk no
if bash "$repo_root/scripts/inspect-android-boot-image.sh" "$tmp/boot.img" "$tmp/fail-report.txt" >/dev/null 2>&1; then
  echo 'Inspector unexpectedly accepted a ramdisk without the handoff markers.' >&2
  exit 1
fi
echo 'Synthetic boot-image inspection test passed (valid handoff accepted; missing handoff rejected).'
