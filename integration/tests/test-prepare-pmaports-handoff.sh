#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pmaports/main/postmarketos-initramfs" \
  "$TMP/pmaports/device/testing/device-oneplus-instantnoodle" \
  "$TMP/armdeck/integration/postmarketos-initramfs" \
  "$TMP/batocera/package/batocera/boot/batocera-initramfs"
cp "$ROOT/integration/postmarketos-initramfs/0001-armdeck-batocera-handoff.patch" \
  "$TMP/armdeck/integration/postmarketos-initramfs/"
cat > "$TMP/pmaports/main/postmarketos-initramfs/init_2nd.sh" <<'EOF'
#!/bin/sh
setup_dynamic_partitions
run_hooks /hooks
mount_subpartitions
mount_root
EOF
printf 'depends="\n busybox\n"\nsha512sums="\n%s  init_2nd.sh\n"\n' \
  "$(sha512sum "$TMP/pmaports/main/postmarketos-initramfs/init_2nd.sh" | cut -d' ' -f1)" \
  > "$TMP/pmaports/main/postmarketos-initramfs/APKBUILD"
cat > "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/APKBUILD" <<'EOF'
pkgname=device-oneplus-instantnoodle
source="
 deviceinfo
 kernel-cmdline.conf
 sm8250-oneplus-instantnoodle-empty.dts
"
package() {
 devicepkg_package $startdir $pkgname
	install -Dm644 "$srcdir/dtbo.img" "$pkgdir/boot/dtbo.img"
}
sha512sums="
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000  deviceinfo
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000  kernel-cmdline.conf
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000  sm8250-oneplus-instantnoodle-empty.dts
"
EOF
printf 'clk_ignore_unused\npd_ignore_unused\n' > "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/kernel-cmdline.conf"
for file in deviceinfo sm8250-oneplus-instantnoodle-empty.dts; do
  printf 'fixture\n' > "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/$file"
done
cat > "$TMP/batocera/package/batocera/boot/batocera-initramfs/init" <<'EOF'
#!/bin/ash
do_mount() { mount -o "$2" "$1" /boot_root; }
do_root() {
    mount -t devtmpfs none /dev
    MOUNTARG=none
    while [ $boot_root_mounted = n ]
    do
        for param in ${cmdline}
        do
            case ${param} in
                dev=*)      MOUNTARG=${param#dev=};;
            esac
        done
    done
}
EOF
bash "$ROOT/integration/prepare-pmaports-handoff.sh" \
  "$TMP/pmaports" "$TMP/armdeck" "$TMP/batocera"
sh -n "$TMP/pmaports/main/postmarketos-initramfs/init_2nd.sh"
sh -n "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/init.batocera"
grep -q 'kpartx -avs' "$TMP/pmaports/main/postmarketos-initramfs/init_2nd.sh"
grep -q 'BATOCERA_BOOT' "$TMP/pmaports/main/postmarketos-initramfs/init_2nd.sh"
grep -q 'BATOCERA_BOOT_DEV' "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/init.batocera"
grep -q 'init.batocera:/init.batocera' "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/00-armdeck-batocera.files"
grep -q 'armdeck.batocera=1' "$TMP/pmaports/device/testing/device-oneplus-instantnoodle/kernel-cmdline.conf"
python3 - "$TMP/pmaports" <<'PY'
from pathlib import Path
import hashlib, re, sys
root = Path(sys.argv[1])
checks = [
    (root / 'main/postmarketos-initramfs/APKBUILD', ['init_2nd.sh']),
    (root / 'device/testing/device-oneplus-instantnoodle/APKBUILD',
     ['kernel-cmdline.conf', 'init.batocera', '00-armdeck-batocera.files']),
]
for apk, names in checks:
    text = apk.read_text()
    for name in names:
        m = re.search(rf'(?m)^([0-9a-f]{{128}})  {re.escape(name)}$', text)
        assert m, f'missing checksum for {name}'
        actual = hashlib.sha512((apk.parent / name).read_bytes()).hexdigest()
        assert actual == m.group(1), f'checksum mismatch for {name}'
print('Handoff preparation fixture and generated APKBUILD checksums passed.')
PY
