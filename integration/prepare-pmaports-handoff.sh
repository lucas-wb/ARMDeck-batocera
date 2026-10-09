#!/usr/bin/env bash
# Apply the Batocera initramfs handoff to a pinned pmaports checkout and add
# the stock Batocera init to the OnePlus device package so mkinitfs includes it.
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <pmaports-root> <armdeck-source-root> <batocera-source-root>" >&2
  exit 2
fi
PMAPORTS=$(readlink -f "$1")
ARMDECK=$(readlink -f "$2")
BATOCERA=$(readlink -f "$3")
SELF_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

INITFS_DIR="$PMAPORTS/main/postmarketos-initramfs"
DEVICE_DIR="$PMAPORTS/device/testing/device-oneplus-instantnoodle"
INITFS_APKBUILD="$INITFS_DIR/APKBUILD"
DEVICE_APKBUILD="$DEVICE_DIR/APKBUILD"
INITFS_SCRIPT="$INITFS_DIR/init_2nd.sh"
BATOCERA_INIT="$BATOCERA/package/batocera/boot/batocera-initramfs/init"

for f in "$INITFS_APKBUILD" "$INITFS_SCRIPT" "$DEVICE_APKBUILD" "$DEVICE_DIR/kernel-cmdline.conf" "$BATOCERA_INIT"; do
  [[ -f "$f" ]] || { echo "ERROR: expected source file not found: $f" >&2; exit 1; }
done
command -v patch >/dev/null
command -v sha512sum >/dev/null

if grep -q 'armdeck.batocera=1' "$INITFS_SCRIPT"; then
  echo 'ERROR: handoff already present; refusing to apply twice.' >&2
  exit 1
fi
patch --batch --forward -p1 -d "$INITFS_DIR" < "$SELF_DIR/postmarketos-initramfs/0001-armdeck-batocera-handoff.patch"

# Ensure kpartx is included in the initramfs package.
python3 - "$INITFS_APKBUILD" <<'PYDEP'
from pathlib import Path
import re, sys
p = Path(sys.argv[1]); s = p.read_text()
m = re.search(r'(?ms)^depends="\n(.*?)\n"', s)
if not m:
    raise SystemExit('Could not find multiline depends block in initramfs APKBUILD')
if 'multipath-tools' not in m.group(1).split():
    block = m.group(1) + '\n\tmultipath-tools'
    s = s[:m.start(1)] + block + s[m.end(1):]
    p.write_text(s)
PYDEP

# Update the checksum for the modified local init_2nd.sh source file.
python3 - "$INITFS_APKBUILD" "$INITFS_SCRIPT" <<'PYCHECK'
from pathlib import Path
import hashlib, re, sys
apk = Path(sys.argv[1]); src = Path(sys.argv[2])
s = apk.read_text(); digest = hashlib.sha512(src.read_bytes()).hexdigest()
pattern = re.compile(r'(?m)^\s*[0-9a-fA-F]{128}\s+init_2nd\.sh\s*$')
s, n = pattern.subn(f'{digest}  init_2nd.sh', s)
if n != 1:
    raise SystemExit(f'Expected exactly one init_2nd.sh checksum in {apk}; found {n}')
apk.write_text(s)
PYCHECK

# Stage and minimally patch Batocera's stock init. It must not remount devtmpfs
# over the already-populated /dev, and must accept the mapped boot device.
cp "$BATOCERA_INIT" "$DEVICE_DIR/init.batocera"
python3 - "$DEVICE_DIR/init.batocera" <<'PYINIT'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
old = 'mount -t devtmpfs none /dev'
new = """if ! grep -q \"^[^ ]* /dev devtmpfs\" /proc/mounts; then
    mount -t devtmpfs none /dev
fi"""
if s.count(old) != 1:
    raise SystemExit(f'Expected exactly one devtmpfs mount anchor in Batocera init, found {s.count(old)}')
s = s.replace(old, new, 1)
old = '    while [ $boot_root_mounted = n ]\n    do\n        for param in ${cmdline}'
new = """    while [ $boot_root_mounted = n ]
    do
        # ARMDeck passes a block device mapped from Android super. Prefer it
        # directly and never fall through to a different dev= argument.
        if [ -n \"${BATOCERA_BOOT_DEV:-}\" ]; then
            if [ ! -b \"$BATOCERA_BOOT_DEV\" ]; then
                echo \"ARMDeck: invalid BATOCERA_BOOT_DEV: $BATOCERA_BOOT_DEV\"
                return 1
            fi
            for i in $(seq $devretry)
            do
                if do_mount \"$BATOCERA_BOOT_DEV\" \"\"
                then
                    echo \"Mounted $BATOCERA_BOOT_DEV as /boot_root\"
                    boot_root_mounted=y
                    break
                fi
                echo \"Waiting for the Batocera boot device $BATOCERA_BOOT_DEV\"
                sleep 1
            done
            [ $boot_root_mounted = y ] && break
            continue
        fi
        for param in ${cmdline}"""
if s.count(old) != 1:
    raise SystemExit(f'Expected exactly one boot-root mount loop anchor, found {s.count(old)}')
s = s.replace(old, new, 1)
p.write_text(s)
PYINIT
chmod 0755 "$DEVICE_DIR/init.batocera"
sh -n "$DEVICE_DIR/init.batocera"
cat > "$DEVICE_DIR/00-armdeck-batocera.files" <<'FILES'
/usr/share/armdeck-batocera/init.batocera:/init.batocera
FILES

# Append local source files, package install commands, and checksums in a
# deterministic, guarded way. Fail if the expected APKBUILD structure changed.
python3 - "$DEVICE_APKBUILD" "$DEVICE_DIR" <<'PYDEVICE'
from pathlib import Path
import hashlib, re, sys
apk = Path(sys.argv[1]); root = Path(sys.argv[2]); s = apk.read_text()
for name in ('init.batocera', '00-armdeck-batocera.files'):
    if re.search(rf'(?m)^\s*{re.escape(name)}\s*$', s):
        raise SystemExit(f'{name} already listed in APKBUILD; refusing duplicate edit')
source = re.search(r'(?ms)^source="\n(.*?)\n"', s)
if not source:
    raise SystemExit('Could not find multiline source="..." in device APKBUILD')
s = s[:source.end()-1] + '\n\tinit.batocera\n\t00-armdeck-batocera.files\n' + s[source.end()-1:]
anchor = '\tinstall -Dm644 "$srcdir/dtbo.img" "$pkgdir/boot/dtbo.img"'
if s.count(anchor) != 1:
    raise SystemExit('Expected exactly one dtbo install anchor in device APKBUILD')
s = s.replace(anchor, anchor + '\n\tinstall -Dm755 "$srcdir/init.batocera" "$pkgdir/usr/share/armdeck-batocera/init.batocera"\n\tinstall -Dm644 "$srcdir/00-armdeck-batocera.files" "$pkgdir/etc/mkinitfs/files/00-armdeck-batocera.files"', 1)
checks = re.search(r'(?ms)^sha512sums="\n(.*?)\n"', s)
if not checks:
    raise SystemExit('Could not find multiline sha512sums="..." in device APKBUILD')
block = checks.group(1)
for name in ('init.batocera', '00-armdeck-batocera.files'):
    digest = hashlib.sha512((root / name).read_bytes()).hexdigest()
    block += f'\n{digest}  {name}'
s = s[:checks.start(1)] + block + s[checks.end(1):]
apk.write_text(s)
PYDEVICE

# Enable handoff without hardcoding an unverified Linux block-device path.
CMDLINE="$DEVICE_DIR/kernel-cmdline.conf"
grep -qxF 'armdeck.batocera=1' "$CMDLINE" || printf '\narmdeck.batocera=1\n' >> "$CMDLINE"
python3 - "$DEVICE_APKBUILD" "$CMDLINE" <<'PYCMDSUM'
from pathlib import Path
import hashlib, re, sys
apk = Path(sys.argv[1]); src = Path(sys.argv[2]); s = apk.read_text()
digest = hashlib.sha512(src.read_bytes()).hexdigest()
pattern = re.compile(r'(?m)^\s*[0-9a-fA-F]{128}\s+kernel-cmdline\.conf\s*$')
s, n = pattern.subn(f'{digest}  kernel-cmdline.conf', s)
if n != 1:
    raise SystemExit(f'Expected exactly one kernel-cmdline.conf checksum; found {n}')
apk.write_text(s)
PYCMDSUM

# Sanity checks before pmbootstrap gets to build anything.
grep -q 'armdeck.batocera=1' "$INITFS_SCRIPT"
grep -q 'kpartx -avs' "$INITFS_SCRIPT"
grep -q 'BATOCERA_BOOT' "$INITFS_SCRIPT"
grep -q 'init.batocera' "$DEVICE_APKBUILD"
grep -q '00-armdeck-batocera.files' "$DEVICE_APKBUILD"
sh -n "$INITFS_SCRIPT"
printf 'Prepared pinned pmaports checkout for Batocera handoff.\n'
printf '  pmaports: %s\n  Batocera init source: %s\n' "$PMAPORTS" "$BATOCERA_INIT"
printf '  WARNING: this creates an integrated boot artifact, not a tested or flashable release.\n'
