#!/usr/bin/env bash
# Resolve the latest stable release branch from the official Batocera changelog.
# Output is pipe-delimited: version|fetch-ref|commit-sha
set -Eeuo pipefail

REPO=${BATOCERA_REPO_URL:-https://github.com/batocera-linux/batocera.linux.git}
CHANGELOG_URL=${BATOCERA_CHANGELOG_URL:-https://raw.githubusercontent.com/batocera-linux/batocera.linux/master/batocera-Changelog.md}

resolve_ref() {
  local requested=$1 result sha ref
  if [[ $requested =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf 'explicit|%s|%s\n' "$requested" "${requested,,}"
    return 0
  fi
  result=$(git ls-remote "$REPO" \
    "refs/heads/$requested" "refs/tags/$requested" "refs/tags/$requested^{}")
  sha=$(awk -v head="refs/heads/$requested" -v tag="refs/tags/$requested" -v peeled="refs/tags/$requested^{}" '
    $2 == head { print $1; found=1; exit }
    $2 == peeled { peeled_sha=$1 }
    $2 == tag { tag_sha=$1 }
    END { if (!found) { if (peeled_sha != "") print peeled_sha; else if (tag_sha != "") print tag_sha } }
  ' <<< "$result")
  [[ $sha =~ ^[0-9a-fA-F]{40}$ ]] || { echo "Cannot resolve Batocera ref '$requested' in $REPO" >&2; return 1; }
  printf 'explicit|%s|%s\n' "$requested" "$sha"
}

if [[ ${1:-} == --ref ]]; then
  [[ $# -eq 2 && -n $2 ]] || { echo "Usage: $0 [--ref <branch-tag-or-40-character-sha>]" >&2; exit 2; }
  resolve_ref "$2"
  exit
fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--ref <branch-tag-or-40-character-sha>]" >&2; exit 2; }
command -v curl >/dev/null || { echo 'curl is required to resolve the latest Batocera release.' >&2; exit 1; }
command -v git >/dev/null || { echo 'git is required to resolve the latest Batocera release.' >&2; exit 1; }

CHANGELOG=$(curl -fsSL "$CHANGELOG_URL")
# Ignore development headings such as "2026/xx/xx - batocera.linux 44".
VERSION=$(sed -nE 's/^# [0-9]{4}\/[0-9]{2}\/[0-9]{2} - batocera\.linux ([0-9]+(\.[0-9]+)*)$/\1/p' <<< "$CHANGELOG" | head -n 1)
[[ $VERSION =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Could not determine the latest stable Batocera version from $CHANGELOG_URL" >&2; exit 1; }
MAJOR=${VERSION%%.*}

# Batocera maintains stable release branches by major version. If that branch
# is absent, try exact version/major tags rather than silently using master.
CANDIDATES=("refs/tags/v$VERSION" "refs/tags/$VERSION" "refs/heads/batocera-$VERSION" "refs/heads/batocera-$MAJOR" "refs/tags/v$MAJOR" "refs/tags/$MAJOR")
QUERY=("${CANDIDATES[@]}")
for candidate in "${CANDIDATES[@]}"; do
  [[ $candidate == refs/tags/* ]] && QUERY+=("$candidate^{}")
done
REMOTE=$(git ls-remote "$REPO" "${QUERY[@]}")
for candidate in "${CANDIDATES[@]}"; do
  # For annotated tags, prefer the peeled commit rather than the tag object.
  sha=$(awk -v ref="$candidate" -v peeled="$candidate^{}" '$2 == peeled { print $1; found=1; exit } $2 == ref { value=$1 } END { if (!found && value != "") print value }' <<< "$REMOTE")
  if [[ $sha =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s|%s|%s\n' "$VERSION" "${candidate#refs/heads/}" "$sha"
    exit 0
  fi
done

echo "Detected Batocera stable version $VERSION, but could not find its release branch/tag in $REPO." >&2
echo 'No fallback to master is performed. Inspect upstream refs and pass an explicit ref with --ref if needed.' >&2
exit 1
