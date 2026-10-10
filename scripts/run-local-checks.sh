#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
for script in \
  "$ROOT/build-super-image.sh" \
  "$ROOT/validate-super-image.sh" \
  "$ROOT/prepare-initramfs.sh" \
  "$ROOT/scripts/inspect-android-boot-image.sh" \
  "$ROOT/scripts/provision-ubuntu-build-host.sh" \
  "$ROOT/scripts/check-build-host.sh" \
  "$ROOT/scripts/build-batocera-local.sh" \
  "$ROOT/scripts/resolve-batocera-release.sh" \
  "$ROOT/scripts/build-armdeck-local.sh" \
  "$ROOT/scripts/assemble-local.sh" \
  "$ROOT/integration/tests/test-resolve-batocera-release.sh"; do
  bash -n "$script"
done
sh -n "$ROOT/init"
bash "$ROOT/integration/tests/test-inspect-android-boot-image.sh"
bash "$ROOT/integration/tests/test-prepare-pmaports-handoff.sh"
bash "$ROOT/integration/tests/test-resolve-batocera-release.sh"
echo 'PASS: local shell syntax and synthetic integration tests.'
