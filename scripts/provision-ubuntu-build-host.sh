#!/usr/bin/env bash
# Install host prerequisites for local Batocera + ARMDeck builds on Ubuntu 24.04.
# This does not clone source, run builds, flash a phone, or configure pmbootstrap.
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]]; then echo 'Cannot identify OS.' >&2; exit 1; fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ ${ID:-} != ubuntu ]]; then
  echo "This provisioning script supports Ubuntu only (detected: ${PRETTY_NAME:-unknown})." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  bash build-essential ca-certificates cpio curl device-tree-compiler \
  dosfstools e2fsprogs fdisk file gawk git gnupg gzip kpartx lz4 make mkbootimg patch \
  python3 python3-pip python3-venv pipx rsync squashfs-tools sudo \
  tar unzip util-linux xz-utils zstd \
  android-sdk-libsparse-utils

# Install Docker Engine from Docker's official Ubuntu repository, as recommended
# by Batocera's build guide rather than relying on Ubuntu's older docker.io package.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' "$ARCH" "$CODENAME" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Install the current pmbootstrap CLI in an isolated pipx environment.
# Its own docs recommend a native Linux host; WSL is not officially supported.
TARGET_USER=${SUDO_USER:-root}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ ! -x "$TARGET_HOME/.local/bin/pmbootstrap" ]]; then
  runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    pipx install 'git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git'
fi
if [[ ! -e /usr/local/bin/pmbootstrap ]]; then
  ln -s "$TARGET_HOME/.local/bin/pmbootstrap" /usr/local/bin/pmbootstrap
fi

if [[ -n ${SUDO_USER:-} ]]; then
  usermod -aG docker "$SUDO_USER"
  echo "Added $SUDO_USER to the docker group. Log out and back in before using Docker without sudo."
fi

cat <<'MSG'
Host prerequisites installed.

Next:
  1. Log out/in if your user was added to the docker group.
  2. Run: docker info
  3. Check available disk space; allow at least 200-250 GB for Batocera source/build
     data, plus additional room for ARMDeck/pmaports caches and image assembly.
  4. Read docs/BUILDING.md. Batocera defaults to the latest stable upstream release;
     ARMDeck and pmaports still use explicit commit SHAs.
  5. Run `pmbootstrap init` once interactively for your chosen build configuration.

The `mkbootimg` package provides Android's boot-image inspection utilities on supported
Ubuntu releases. If `unpack_bootimg.py` is not on PATH, install the AOSP mkbootimg script
from https://android.googlesource.com/platform/system/tools/mkbootimg and put it on PATH.
MSG
