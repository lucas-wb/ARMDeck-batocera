#!/usr/bin/env bash
# Build official Batocera SM8250 target from the latest stable release by default.
# This produces generic SM8250 userspace, not a OnePlus-specific phone image.
set -Eeuo pipefail

usage() { echo "Usage: $0 [latest|<Batocera-branch-tag-or-40-char-SHA>] [workspace-dir]" >&2; exit 2; }
[[ $# -le 2 ]] || usage
REQUESTED_REF=${1:-latest}
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE=$(readlink -m "${2:-$ROOT/build-local}")
SRC="$WORKSPACE/batocera-src"
OUT="$WORKSPACE/output-artifacts/batocera"
REPO=https://github.com/batocera-linux/batocera.linux.git
mkdir -p "$WORKSPACE" "$WORKSPACE/output-artifacts"
for cmd in git make docker curl; do command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }; done

if [[ $REQUESTED_REF == latest ]]; then
  IFS='|' read -r RELEASE_VERSION FETCH_REF EXPECTED_SHA < <(bash "$ROOT/scripts/resolve-batocera-release.sh")
else
  IFS='|' read -r RELEASE_VERSION FETCH_REF EXPECTED_SHA < <(bash "$ROOT/scripts/resolve-batocera-release.sh" --ref "$REQUESTED_REF")
fi

echo "Batocera release selection: version=$RELEASE_VERSION ref=$FETCH_REF expected-commit=$EXPECTED_SHA"
if [[ -d "$SRC/.git" ]]; then
  [[ -z $(git -C "$SRC" status --porcelain) ]] || { echo "Existing Batocera checkout has local changes: $SRC. Preserve them and use a clean workspace." >&2; exit 1; }
  git -C "$SRC" remote get-url origin >/dev/null 2>&1 || { echo "Existing checkout has no origin remote: $SRC" >&2; exit 1; }
  [[ $(git -C "$SRC" remote get-url origin) == "$REPO" ]] || { echo "Existing checkout is not from the official Batocera repository: $SRC" >&2; exit 1; }
  git -C "$SRC" fetch --depth=1 origin "$FETCH_REF"
  git -C "$SRC" checkout --detach FETCH_HEAD
else
  [[ ! -e "$SRC" ]] || { echo "Refusing to overwrite non-checkout path: $SRC" >&2; exit 1; }
  git init "$SRC"
  git -C "$SRC" remote add origin "$REPO"
  git -C "$SRC" fetch --depth=1 origin "$FETCH_REF"
  git -C "$SRC" checkout --detach FETCH_HEAD
fi
ACTUAL=$(git -C "$SRC" rev-parse HEAD)
if [[ ${ACTUAL,,} != ${EXPECTED_SHA,,} ]]; then
  echo "Resolved ref changed between lookup and fetch (expected $EXPECTED_SHA, fetched $ACTUAL). Rerun to resolve a consistent revision." >&2
  exit 1
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
{
  printf 'BATOCERA_RELEASE=%s\n' "$RELEASE_VERSION"
  printf 'BATOCERA_REF=%s\n' "$FETCH_REF"
  printf 'BATOCERA_COMMIT=%s\n' "$ACTUAL"
  printf 'BATOCERA_REPOSITORY=%s\n' "$REPO"
} > "$OUT/source-manifest.env"
find "$OUT/images" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/SHA256SUMS"
cat <<MSG
Official Batocera SM8250 build completed.
Release selection: $RELEASE_VERSION ($FETCH_REF)
Resolved commit: $ACTUAL
Source: $SRC
Artifacts: $OUT
Manifest: $OUT/source-manifest.env

This is the generic upstream SM8250 target, NOT a OnePlus 8 flashable image.
Inspect the outputs and build log before continuing.
MSG
