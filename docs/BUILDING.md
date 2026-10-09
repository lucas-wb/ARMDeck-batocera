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

Use the exact 40-character SHA for the official `batocera-linux/batocera.linux` repository. Do not use a community fork or a third-party image.

```bash
bash scripts/build-batocera-local.sh <BATOCERA_COMMIT_SHA> "$PWD/build-local"
```

The script clones the official repository at that exact commit, initializes submodules, builds the official Docker development image, and runs `make sm8250-build`. It writes logs to `build-local/batocera-build.log`, a source manifest and checksums to `build-local/output-artifacts/batocera/`, and copies image outputs from `output/sm8250/images`.

This is the generic upstream SM8250 target, **not a OnePlus 8 image**. The script fails if the expected output directory or image artifacts are missing. If the official target name or output layout changes at the pinned commit, stop and inspect the build tree instead of guessing a replacement path.

## 3. Build ARMDeck's OnePlus boot chain with the handoff

Use exact 40-character commit SHAs for the ARMDeck fork, pmaports, and the official Batocera repository:

```bash
bash scripts/build-armdeck-local.sh \
  <ARMDECK_COMMIT_SHA> \
  <PMAPORTS_COMMIT_SHA> \
  <BATOCERA_COMMIT_SHA> \
  "$PWD/build-local"
```

This clones pinned sources, overlays the ARMDeck OnePlus device packages into the pinned pmaports checkout, applies the project's Batocera handoff, stages Batocera's stock init, and builds the initramfs, kernel, firmware, audio package, and device package with pmbootstrap. It then exports the intermediate boot artifacts.

The script refuses to overwrite source directories. If a build is interrupted after the handoff was applied, use a fresh workspace for the next attempt; do not apply the patch twice to a modified pmaports checkout. The ARMDeck and pmaports package definitions are changing projects, so the first real build may reveal incompatibilities that synthetic tests cannot catch.

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
