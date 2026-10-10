# Local build guide

This project is built locally on a dedicated native x86_64 Linux host. There are no GitHub Actions build workflows and no hosted/self-hosted runner requirement. The build scripts pin upstream sources to exact commit SHAs, keep artifacts on disk, and never flash a phone.

## Host requirements

- Ubuntu 24.04 x86_64 is the scripted baseline. Other Linux distributions may work, but the provisioning script intentionally refuses to run on them.
- At least 8 GiB RAM; 16 GiB or more is recommended.
- Plan for **250 GiB free disk or more** for Batocera downloads/build output, plus additional space for pmaports, kernel/package caches, exported images, and final artifacts. Batocera's official build guide estimates roughly 80–250 GB per target. See <https://wiki.batocera.org/compile_batocera.linux>.
- Docker, Git, GNU Make, Python, pmbootstrap, loop-device/filesystem tools, Android sparse image tools, and Android `unpack_bootimg` utility.
- Native Linux is recommended; pmbootstrap does not officially support WSL. Do not build in a small temporary filesystem.

## 1. Provision the host

From the project root:

```bash
sudo bash scripts/provision-ubuntu-build-host.sh
```

Log out and back in if the script adds your account to the `docker` group. Verify Docker works:

```bash
docker info
```

Initialize pmbootstrap interactively once for the host:

```bash
pmbootstrap init
```

Select the OnePlus 8 / `oneplus-instantnoodle` device and an appropriate postmarketOS channel. This initializes the local pmbootstrap configuration; the build script then points the build at the pinned pmaports checkout. Review the selections carefully. The script does not flash anything.

Check prerequisites and available resources:

```bash
bash scripts/check-build-host.sh
```

If the host has less than 200 GiB free in the current filesystem, the check fails by default. You can override the threshold intentionally, for example `MIN_FREE_GIB=150 bash scripts/check-build-host.sh`, but doing so does not make a low-space build safe.

## 2. Build official Batocera SM8250 userspace

By default, the script detects the latest **stable release version** from the official Batocera changelog, selects that release's upstream branch/tag, resolves it to a commit, and records the exact SHA in the build manifest. It does not use `master` as a fallback. Do not use a community fork or a third-party image.

```bash
bash scripts/build-batocera-local.sh
```

Optionally provide a workspace directory while retaining the latest-release default:

```bash
bash scripts/build-batocera-local.sh latest "$PWD/build-local"
```

To reproduce a prior build, you can still pass an exact SHA or an official branch/tag:

```bash
bash scripts/build-batocera-local.sh <BATOCERA_SHA_OR_REF> "$PWD/build-local"
```

The resolver is `scripts/resolve-batocera-release.sh`. It reads the latest dated stable-version heading from the official upstream changelog, prefers the corresponding `batocera-<major>` branch, and then checks exact release/major tags. If it cannot resolve a matching official ref, it stops instead of silently building development `master`. The build initializes submodules, builds the official Docker development image, and runs `make sm8250-build`. Logs go to `build-local/batocera-build.log`; the source manifest and checksums go to `build-local/output-artifacts/batocera/`.

This is the generic upstream SM8250 target, **not a OnePlus 8 image**. The manifest records release version, selected ref, exact commit SHA, and official repository URL. The script fails if the expected output directory or image artifacts are missing. If the official target name or output layout changes, inspect the build tree instead of guessing a replacement path.

## 3. Build ARMDeck's OnePlus boot chain with the handoff

ARMDeck and pmaports remain pinned to exact 40-character commit SHAs. Batocera no longer requires a SHA by default: the script uses the exact commit in `build-local/output-artifacts/batocera/source-manifest.env` when that manifest exists, so the boot chain matches the already-built userspace. If no Batocera build manifest exists, it resolves the latest official stable release automatically.

```bash
bash scripts/build-armdeck-local.sh \
  <ARMDECK_COMMIT_SHA> \
  <PMAPORTS_COMMIT_SHA>
```

To explicitly request the latest stable Batocera release (or use a custom workspace), pass `latest` as the third argument:

```bash
bash scripts/build-armdeck-local.sh \
  <ARMDECK_COMMIT_SHA> \
  <PMAPORTS_COMMIT_SHA> \
  latest \
  "$PWD/build-local"
```

You may also pass an official Batocera branch, tag, or exact SHA as the third argument. `BATOCERA_REF` can be set in the environment to override automatic selection. The script clones/resolves Batocera only from the official repository, overlays the ARMDeck OnePlus device packages into the pmaports checkout, applies the project's Batocera handoff, stages Batocera's stock init, and builds the initramfs, kernel, firmware, audio package, and device package with pmbootstrap. It then exports the intermediate boot artifacts.

The script refuses to overwrite source directories. If a build is interrupted after the handoff was applied, use a fresh workspace for the next attempt; do not apply the patch twice to a modified pmaports checkout. The ARMDeck and pmaports package definitions are changing projects, so the first real build may reveal incompatibilities that synthetic tests cannot catch. Their exact commit SHAs are recorded in the manifest.

Outputs are under `build-local/output-artifacts/armdeck/`. Confirm the exported `boot.img` and source manifest exist. If the installed pmbootstrap version exports to a different location, inspect `pmbootstrap export` output and update the script deliberately; do not use a stale `/tmp/postmarketOS-export` directory.

## 4. Assemble and inspect the prototype image

First measure the exact logical capacity of the IN2017's `super` partition using a verified device/recovery procedure. Do not guess this value. Then run:

```bash
bash scripts/assemble-local.sh \
  build-local/output-artifacts/batocera/images/rootfs.squashfs \
  build-local/output-artifacts/armdeck/boot.img \
  <EXACT_SUPER_PARTITION_BYTES> \
  - \
  6144 \
  build-local/output-artifacts/final
```

Adjust the SquashFS path to the actual file produced by the pinned Batocera build. The script inspects the Android boot image, builds the nested two-partition image, validates its partition table and filesystems, and creates checksums. It requires `sudo` for loop devices and mounts. `EXACT_SUPER_PARTITION_BYTES` must be the verified capacity in bytes; the image builder aligns the result down to a 4096-byte boundary.

The resulting bundle is marked `prototype-not-for-flashing`. It is an inspection artifact, not a release. Do not flash it to the phone.

## 5. Local static checks

Run before and after source changes:

```bash
bash scripts/run-local-checks.sh
```

These checks include shell syntax validation and synthetic integration fixtures. They do not build the full projects, and they do not prove the phone boots.

## Known limitations / acceptance gates

- The official generic SM8250 Batocera target is not proof of OnePlus-specific GPU, display, input, audio, storage, or power support.
- The ARMDeck mainline kernel and OnePlus 8 IN2017 variant compatibility have not been verified on hardware.
- The boot-image inspection is static and cannot prove bootloader acceptance.
- The nested-MBR-inside-Android-`super` concept must be reviewed against the exact device partition layout and recovery path before any write.
- Do not enable the risky PM8150B charger/fuel-gauge driver from community patches.
- No script in this repository flashes the phone. A verified stock recovery image and recovery procedure are required before any device experiment.
