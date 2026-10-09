#!/usr/bin/env bash
# Build official Batocera SM8250 target from a pinned commit. Not a phone image.
set -Eeuo pipefail

usage() { echo "Usage: $0 <batocera-40-char-commit-sha> [workspace-dir]" >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
REF=$1
[[ $REF =~ ^[0-9a-fA-F]{40}$ ]] || { echo 'Provide an exact 40-character Batocera commit SHA.' >&2; exit 2; }
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE=$(readlink -m "${2:-$ROOT/build-local}")
SRC="$WORKSPACE/batocera-src"
OUT="$WORKSPACE/output-artifacts/batocera"
mkdir -p "$WORKSPACE" "$WORKSPACE/output-artifacts"
command -v git >/dev/null; command -v make >/dev/null; command -v docker >/dev/null

if [[ -d "$SRC/.git" ]]; then
  ACTUAL=$(git -C "$SRC" rev-parse HEAD)
  [[ ${ACTUAL,,} == ${REF,,} ]] || { echo "Existing Batocera checkout is $ACTUAL, not requested $REF. Use a new workspace." >&2; exit 1; }
else
  [[ ! -e "$SRC" ]] || { echo "Refusing to overwrite non-checkout path: $SRC" >&2; exit 1; }
  git clone https://github.com/batocera-linux/batocera.linux.git "$SRC"
  git -C "$SRC" fetch --depth=1 origin "$REF"
  git -C "$SRC" checkout --detach FETCH_HEAD
  ACTUAL=$(git -C "$SRC" rev-parse HEAD)
  [[ ${ACTUAL,,} == ${REF,,} ]] || { echo 'Checked-out Batocera commit does not match requested SHA.' >&2; exit 1; }
fi
git -C "$SRC" submodule update --init --recursive

# Build Batocera using its official Docker development container.
cd "$SRC"
make build-docker-image
set -o pipefail
make sm8250-build 2>&1 | tee "$WORKSPACE/batocera-build.log"

IMAGES="$SRC/output/sm8250/images"
[[ -d "$IMAGES" ]] || { echo "Expected output directory missing: $IMAGES" >&2; exit 1; }
find "$IMAGES" -type f -size +0c -print -quit | grep -q . || { echo 'Batocera image output directory is empty.' >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT/images"
cp -a "$IMAGES"/. "$OUT/images/"
printf 'BATOCERA_COMMIT=%s\n' "$ACTUAL" > "$OUT/source-manifest.env"
printf 'BATOCERA_REPOSITORY=https://github.com/batocera-linux/batocera.linux.git\n' >> "$OUT/source-manifest.env"
find "$OUT/images" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/SHA256SUMS"
cat <<MSG
Official Batocera SM8250 build completed.
Source: $SRC
Artifacts: $OUT
Manifest: $OUT/source-manifest.env

This is the generic upstream SM8250 baseline, NOT a OnePlus 8 flashable image.
Inspect the outputs and build log before continuing.
MSG
