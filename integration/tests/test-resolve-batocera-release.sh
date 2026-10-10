#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir "$TMP/repo"
git -C "$TMP/repo" init -q -b main
git -C "$TMP/repo" config user.email test@example.invalid
git -C "$TMP/repo" config user.name 'Fixture Test'
printf 'fixture\n' > "$TMP/repo/fixture.txt"
git -C "$TMP/repo" add fixture.txt
git -C "$TMP/repo" commit -qm 'fixture commit'
git -C "$TMP/repo" branch batocera-43
git clone -q --bare "$TMP/repo" "$TMP/remote.git"
cat > "$TMP/changelog.md" <<'CHANGELOG'
# 2026/xx/xx - batocera.linux 44 - Development
# 2026/05/30 - batocera.linux 43.1
CHANGELOG
EXPECTED=$(git -C "$TMP/repo" rev-parse refs/heads/batocera-43)
ACTUAL=$(BATOCERA_REPO_URL="$TMP/remote.git" BATOCERA_CHANGELOG_URL="file://$TMP/changelog.md" bash "$ROOT/scripts/resolve-batocera-release.sh")
[[ $ACTUAL == "43.1|batocera-43|$EXPECTED" ]] || { echo "Unexpected latest-release branch fallback: $ACTUAL" >&2; exit 1; }
# If an exact version tag exists, it should win over a moving release branch.
git -C "$TMP/repo" tag v43.1
(cd "$TMP/repo" && git push -q "$TMP/remote.git" refs/tags/v43.1)
ACTUAL=$(BATOCERA_REPO_URL="$TMP/remote.git" BATOCERA_CHANGELOG_URL="file://$TMP/changelog.md" bash "$ROOT/scripts/resolve-batocera-release.sh")
[[ $ACTUAL == "43.1|refs/tags/v43.1|$EXPECTED" ]] || { echo "Exact release tag was not preferred: $ACTUAL" >&2; exit 1; }
ACTUAL_EXPLICIT=$(BATOCERA_REPO_URL="$TMP/remote.git" bash "$ROOT/scripts/resolve-batocera-release.sh" --ref "$EXPECTED")
[[ $ACTUAL_EXPLICIT == "explicit|$EXPECTED|$EXPECTED" ]] || { echo "Unexpected explicit-SHA resolution: $ACTUAL_EXPLICIT" >&2; exit 1; }
echo 'PASS: latest stable release branch and explicit SHA resolve correctly.'
