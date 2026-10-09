#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <batocera-source-init> <pmbootstrap-rootfs>" >&2
    exit 2
fi
src=$(readlink -f "$1")
root=$(readlink -f "$2")
[ -f "$src" ] || { echo "ERROR: Batocera init not found: $src" >&2; exit 1; }
[ -d "$root" ] || { echo "ERROR: rootfs directory not found: $root" >&2; exit 1; }

# Validate that this is the Batocera init expected by the patch. Refuse to
# patch an unrelated/newly reorganized init rather than silently producing a
# boot image with the wrong mount logic.
grep -Fq 'while [ $boot_root_mounted = n ]' "$src" || { echo "ERROR: unexpected Batocera init: boot-root loop anchor missing" >&2; exit 1; }
grep -Fq 'mount -t devtmpfs none /dev' "$src" || { echo "ERROR: unexpected Batocera init: devtmpfs anchor missing" >&2; exit 1; }

out="$root/usr/share/armdeck-batocera/init.batocera"
mkdir -p "$(dirname "$out")"
cp "$src" "$out"

# Add direct-device override while preserving stock cmdline behavior for every
# normal Batocera boot. The selected block node is already mapped by PMOS.
python3 - "$out" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'mount -t devtmpfs none /dev'
new = '''if ! grep -q "^[^ ]* /dev devtmpfs" /proc/mounts; then
    mount -t devtmpfs none /dev
fi'''
if s.count(old) != 1:
    raise SystemExit(f"ERROR: expected exactly one devtmpfs mount, found {s.count(old)}")
s = s.replace(old, new, 1)
old = '    while [ $boot_root_mounted = n ]\n    do\n        for param in ${cmdline}'
new = """    while [ $boot_root_mounted = n ]
    do
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
    raise SystemExit(f"ERROR: expected exactly one boot-root loop anchor, found {s.count(old)}")
s = s.replace(old, new, 1)
p.write_text(s)
PY
chmod 0755 "$out"
sh -n "$out"
printf 'Staged patched Batocera init: %s\n' "$out"
printf 'Next: install integration/device-package/00-armdeck-batocera.files into %s/etc/mkinitfs/files/ and apply integration/postmarketos-initramfs/0001-armdeck-batocera-handoff.patch to the postmarketos-initramfs source package before rebuilding.\n' "$root"
