#!/usr/bin/env bash
# Prepare and build the pinned ARMDeck/postmarketOS handoff locally.
# Batocera defaults to the latest official stable release unless an existing
# Batocera build manifest in this workspace provides the exact matching commit.
set -Eeuo pipefail

usage() { echo "Usage: $0 <armdeck-40-char-sha> <pmaports-40-char-sha> [batocera-ref|latest] [workspace-dir]" >&2; exit 2; }
[[ $# -ge 2 && $# -le 4 ]] || usage
ARM_REF=$1; PM_REF=$2; BATO_REQUEST=${3:-auto}; WORKSPACE_ARG=${4:-}
for pair in "ARMDeck:$ARM_REF" "pmaports:$PM_REF"; do
  value=${pair#*:}
  [[ $value =~ ^[0-9a-fA-F]{40}$ ]] || { echo "${pair%%:*} revision must be an exact 40-character commit SHA." >&2; exit 2; }
done
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [[ -z $WORKSPACE_ARG && $BATO_REQUEST != auto && $BATO_REQUEST != latest && ! $BATO_REQUEST =~ ^[0-9a-fA-F]{40}$ ]]; then
  # A third argument is always the Batocera ref; use "latest <workspace>" to
  # specify a workspace without pinning Batocera.
  :
fi
WORKSPACE=$(readlink -m "${WORKSPACE_ARG:-$ROOT/build-local}")
ARM="$WORKSPACE/armdeck-src"; PM="$WORKSPACE/pmaports"; BATO="$WORKSPACE/batocera-src"
PMWORK="$WORKSPACE/pmbootstrap-work"; EXPORT=/tmp/postmarketOS-export
mkdir -p "$WORKSPACE"
for cmd in git pmbootstrap patch python3 sha512sum; do command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }; done

clone_pinned() {
  local url=$1 dest=$2 ref=$3
  if [[ -d "$dest/.git" ]]; then
    local existing
    existing=$(git -C "$dest" rev-parse HEAD)
    if [[ ${existing,,} != ${ref,,} ]]; then
      echo "Existing checkout at $dest is $existing, not requested $ref. Move it aside or use a new workspace." >&2
      exit 1
    fi
  else
    [[ ! -e "$dest" ]] || { echo "Refusing to overwrite non-checkout path: $dest" >&2; exit 1; }
    git clone "$url" "$dest"
    git -C "$dest" fetch --depth=1 origin "$ref"
    git -C "$dest" checkout --detach FETCH_HEAD
  fi
  local actual
  actual=$(git -C "$dest" rev-parse HEAD)
  [[ ${actual,,} == ${ref,,} ]] || { echo "Revision mismatch for $dest" >&2; exit 1; }
}

# If a Batocera userspace was already built in this workspace, pair the kernel
# integration with that exact commit so assembly provenance checks can match.
# BATOCERA_REF overrides this behavior; latest is the default for a fresh build.
if [[ -n ${BATOCERA_REF:-} ]]; then
  BATO_REQUEST=$BATOCERA_REF
elif [[ $BATO_REQUEST == auto ]]; then
  MANIFEST="$WORKSPACE/output-artifacts/batocera/source-manifest.env"
  if [[ -s $MANIFEST ]]; then
    BATO_REQUEST=$(sed -n 's/^BATOCERA_COMMIT=//p' "$MANIFEST" | head -n1)
  else
    BATO_REQUEST=latest
  fi
fi
if [[ $BATO_REQUEST == latest ]]; then
  IFS='|' read -r BATO_RELEASE BATO_FETCH_REF BATO_EXPECTED < <(bash "$ROOT/scripts/resolve-batocera-release.sh")
else
  IFS='|' read -r BATO_RELEASE BATO_FETCH_REF BATO_EXPECTED < <(bash "$ROOT/scripts/resolve-batocera-release.sh" --ref "$BATO_REQUEST")
fi

echo "Batocera source selection: version=$BATO_RELEASE ref=$BATO_FETCH_REF expected-commit=$BATO_EXPECTED"
clone_pinned https://github.com/lucas-wb/ARMDeck-batocera.git "$ARM" "$ARM_REF"
clone_pinned https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PM" "$PM_REF"
# Resolve Batocera from the official upstream only. Initialize a minimal checkout
# at the resolved release ref and verify its commit matches the resolver result.
if [[ -d "$BATO/.git" ]]; then
  [[ -z $(git -C "$BATO" status --porcelain) ]] || { echo "Existing Batocera checkout has local changes: $BATO. Use a clean workspace." >&2; exit 1; }
  [[ $(git -C "$BATO" remote get-url origin) == https://github.com/batocera-linux/batocera.linux.git ]] || { echo "Batocera checkout is not the official repository: $BATO" >&2; exit 1; }
  git -C "$BATO" fetch --depth=1 origin "$BATO_FETCH_REF"
  git -C "$BATO" checkout --detach FETCH_HEAD
else
  [[ ! -e "$BATO" ]] || { echo "Refusing to overwrite non-checkout path: $BATO" >&2; exit 1; }
  git init "$BATO"
  git -C "$BATO" remote add origin https://github.com/batocera-linux/batocera.linux.git
  git -C "$BATO" fetch --depth=1 origin "$BATO_FETCH_REF"
  git -C "$BATO" checkout --detach FETCH_HEAD
fi
BATO_ACTUAL=$(git -C "$BATO" rev-parse HEAD)
[[ ${BATO_ACTUAL,,} == ${BATO_EXPECTED,,} ]] || { echo "Batocera ref changed during resolution (expected $BATO_EXPECTED, fetched $BATO_ACTUAL). Rerun." >&2; exit 1; }
git -C "$BATO" submodule update --init --recursive

for package in linux-oneplus-instantnoodle device-oneplus-instantnoodle firmware-oneplus-instantnoodle alsa-ucm-conf-oneplus-instantnoodle; do
  [[ -d "$ARM/pmaports/$package" ]] || { echo "ARMDeck checkout missing pmaports/$package" >&2; exit 1; }
  [[ ! -e "$PM/device/testing/$package" ]] || { echo "Refusing to overwrite upstream package $package" >&2; exit 1; }
  cp -a "$ARM/pmaports/$package" "$PM/device/testing/"
done
bash "$ROOT/integration/prepare-pmaports-handoff.sh" "$PM" "$ARM" "$BATO"
for package in linux-oneplus-instantnoodle device-oneplus-instantnoodle firmware-oneplus-instantnoodle alsa-ucm-conf-oneplus-instantnoodle; do
  [[ -s "$PM/device/testing/$package/APKBUILD" ]] || { echo "Missing APKBUILD for $package" >&2; exit 1; }
done

# pmbootstrap's first-run configuration is interactive. Require it explicitly so
# this script never silently creates or overwrites a user's global configuration.
PMCONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/pmbootstrap.cfg"
if [[ ! -s "$PMCONFIG" ]]; then
  echo "pmbootstrap is not initialized. Run 'pmbootstrap init' interactively, then rerun this script." >&2
  exit 1
fi
mkdir -p "$PMWORK"
PMB=(pmbootstrap -p "$PM" -w "$PMWORK")
"${PMB[@]}" config aports "$PM"
"${PMB[@]}" config device oneplus-instantnoodle
"${PMB[@]}" config ui none
"${PMB[@]}" status
"${PMB[@]}" -y build postmarketos-initramfs 2>&1 | tee "$WORKSPACE/build-initramfs.log"
"${PMB[@]}" -y build linux-oneplus-instantnoodle 2>&1 | tee "$WORKSPACE/build-kernel.log"
"${PMB[@]}" -y build firmware-oneplus-instantnoodle 2>&1 | tee "$WORKSPACE/build-firmware.log"
"${PMB[@]}" -y build alsa-ucm-conf-oneplus-instantnoodle 2>&1 | tee "$WORKSPACE/build-audio.log"
"${PMB[@]}" -y build device-oneplus-instantnoodle 2>&1 | tee "$WORKSPACE/build-device.log"
"${PMB[@]}" -y install 2>&1 | tee "$WORKSPACE/install.log"
rm -rf "$EXPORT"
"${PMB[@]}" export 2>&1 | tee "$WORKSPACE/export.log"

[[ -d "$EXPORT" ]] || { echo "Expected pmbootstrap export directory missing: $EXPORT" >&2; exit 1; }
ART="$WORKSPACE/output-artifacts/armdeck"
mkdir -p "$ART"
find "$EXPORT" -maxdepth 2 -type f -size +0c -print -exec cp -t "$ART" {} \;
[[ -s "$ART/boot.img" ]] || { echo 'No boot.img exported. Inspect pmbootstrap export output and adjust the export path for this pmbootstrap version.' >&2; exit 1; }
{
  echo "ARMDECK_COMMIT=$(git -C "$ARM" rev-parse HEAD)"
  echo "PMAPORTS_COMMIT=$(git -C "$PM" rev-parse HEAD)"
  echo "BATOCERA_RELEASE=$BATO_RELEASE"
  echo "BATOCERA_REF=$BATO_FETCH_REF"
  echo "BATOCERA_COMMIT=$(git -C "$BATO" rev-parse HEAD)"
  echo "BATOCERA_REPOSITORY=https://github.com/batocera-linux/batocera.linux.git"
} > "$ART/source-manifest.env"
rm -f "$ART/SHA256SUMS"
(cd "$ART" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
cat <<MSG
ARMDeck integrated handoff build completed.
Artifacts: $ART

This is an intermediate boot artifact, not a tested or flashable release.
The IN2017 has not been boot-tested. Do not flash it yet.
MSG
