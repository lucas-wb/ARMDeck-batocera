#!/usr/bin/env bash
set -Eeuo pipefail
MIN_FREE_GIB=${MIN_FREE_GIB:-200}
MIN_RAM_GIB=${MIN_RAM_GIB:-8}

[[ $(uname -s) == Linux ]] || { echo 'Build host must be native Linux; WSL is not supported by pmbootstrap.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'Use an x86_64 Linux host for the documented build path.' >&2; exit 1; }
for cmd in git make docker python3 pmbootstrap patch sha512sum sfdisk losetup mkfs.ext4 mount blkid img2simg; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done
docker info >/dev/null
mem_kib=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
mem_gib=$((mem_kib / 1024 / 1024))
(( mem_gib >= MIN_RAM_GIB )) || { echo "Need at least ${MIN_RAM_GIB} GiB RAM; detected ${mem_gib} GiB." >&2; exit 1; }
free_kib=$(df -Pk . | awk 'NR==2 {print $4}')
free_gib=$((free_kib / 1024 / 1024))
(( free_gib >= MIN_FREE_GIB )) || { echo "Need at least ${MIN_FREE_GIB} GiB free on this filesystem; detected ${free_gib} GiB." >&2; exit 1; }
printf 'Host checks passed. RAM: %s GiB; free disk in %s: %s GiB.\n' "$mem_gib" "$PWD" "$free_gib"
printf 'Note: unpack_bootimg or unpack_bootimg.py is additionally required for boot-image inspection.\n'
