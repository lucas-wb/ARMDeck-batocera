# Building from source

> **Status: source-build integration is in progress.** The repository currently contains a prototype image-layout builder and initramfs handoff patch, not a complete reproducible build that emits a bootable phone image. The steps below describe the current development path and clearly identify what is still missing.

## Build environment

Use a supported 64-bit Linux environment with substantial free disk space, working loop devices, and root privileges for the image-layout step. A native Linux host or dedicated Linux build runner is preferable to a constrained container/WSL setup for the full Buildroot and Android boot-image toolchains.

The current prototype scripts expect Bash, `sfdisk`, `losetup`, `mkfs.ext4`, `mount`, `blkid`, `blockdev`, `cpio`, `file`, `gzip`, Android `unpack_bootimg.py` (or `unpack_bootimg`), and optionally Android `img2simg`. The assembly workflow automatically unpacks the generated `boot.img`, inspects its ramdisk, and fails if `/init`, `/init.batocera`, or the expected Batocera handoff markers are missing. This is static validation, not proof of a successful device boot. The image builder intentionally refuses to overwrite an existing output and never flashes a device.

## Current prototype checks

From the repository root:

```bash
bash -n build-super-image.sh
bash -n validate-super-image.sh
bash -n prepare-initramfs.sh
bash -n scripts/inspect-android-boot-image.sh
bash integration/tests/test-inspect-android-boot-image.sh
sh -n init
```

These are syntax checks only. They do not prove that the image can be built or booted.

## Build the Batocera userspace baseline in GitHub Actions

The repository now includes `.github/workflows/build-batocera-sm8250.yml`. It manually builds the generic upstream SM8250 target from an exact commit SHA. It is a baseline build, not a OnePlus 8 image.

1. Configure a dedicated Linux x86_64 self-hosted GitHub Actions runner with labels `self-hosted`, `linux`, `x64`, and `batocera-builder`. It must have Docker, Git, GNU Make 4.3+, and ample free disk space. The workflow deliberately does not use a standard hosted runner because a full Buildroot build can exceed its available storage.
2. In the repository, open **Actions → Build Batocera SM8250 baseline → Run workflow**.
3. Supply the exact 40-character Batocera commit SHA. The workflow rejects branch names and short hashes, checks out that commit, updates submodules, and runs `make sm8250-build`.
4. Download the workflow artifact and inspect its source manifest, image files, checksums, and build log. A failed build is not a release artifact.

The official Batocera build instructions require cloning the source and initializing its Buildroot submodule. The project Makefile defines the `*-build` target family; `sm8250-build` configures and builds the generic target. See <https://wiki.batocera.org/compile_batocera.linux>, <https://github.com/batocera-linux/batocera.linux/blob/master/Makefile>, and <https://github.com/batocera-linux/batocera.linux/blob/master/README.md>.

**This baseline workflow does not create a OnePlus 8 kernel/DTB, Android `boot.img`, or flashable `super.img`.** Do not flash its outputs to the phone.

## Build the ARMDeck/OnePlus boot path

1. Pin the ARMDeck device package, postmarketOS initramfs package, and kernel source to exact commits.
2. Apply `integration/postmarketos-initramfs/0001-armdeck-batocera-handoff.patch` to the matching initramfs source version. A patch that does not apply cleanly must stop the build.
3. Stage Batocera's init into the initramfs using `integration/stage-batocera-init.sh` and include `/init.batocera` in the generated initramfs.
4. Build the device package, kernel, initramfs, and Android boot image using the pinned pmbootstrap/pmaports environment.
5. Inspect the final boot image/initramfs contents and kernel command line. Keep a non-Batocera recovery boot path available until the Batocera path is verified.

ARMDeck reference: <https://github.com/GabrielCRadu/ARMDeck>. The upstream project's documented OnePlus 8 hardware testing does not establish IN2017 compatibility.

## Build the ARMDeck device-package baseline in GitHub Actions

The repository includes `.github/workflows/build-armdeck-device-packages.yml`. It is an intermediate step that builds the kernel, firmware, audio configuration, and device packages, then exports ordinary postmarketOS boot files. It does **not** enable the Batocera handoff or produce a Batocera flash package. See [ARMDeck CI](ARMDECK-CI.md) for runner requirements and known setup limitations.

The workflow takes exact 40-character ARMDeck and pmaports commit SHAs. It refuses to continue unless pmbootstrap reports the pinned per-job pmaports checkout. Runner bootstrapping is not yet fully automated, so this workflow is not yet a turnkey hosted build.

## Build the embedded Batocera storage image

After the Batocera SquashFS exists, the current prototype builder can construct the proposed two-partition image embedded in Android `super`:

```bash
sudo ./build-super-image.sh \
  /path/to/batocera-squashfs \
  /path/to/super.img \
  VERIFIED_SUPER_PARTITION_BYTES \
  - \
  6144
```

Replace `VERIFIED_SUPER_PARTITION_BYTES` with the exact capacity measured for the target device; it is a placeholder, not a literal. The optional fourth argument can be a Batocera extra SquashFS layer if the selected build actually produces one. The default boot filesystem is 6144 MiB and must be adjusted if the actual artifacts do not fit. The script emits a raw image, an environment file, and a sparse image if `img2simg` is installed. The `super.img` naming here is an output filename, not proof that it is ready for Android fastboot.

Run the read-only validator against the resulting image and inspect the partitions and filesystem labels before packaging. The builder must not be run against a phone block device.

## Release build acceptance criteria

A release build is not complete until CI:

- uses pinned source commits and records them in build metadata;
- successfully builds Batocera userspace and the OnePlus boot chain;
- creates and validates the embedded two-partition image;
- inspects the generated initramfs and kernel command line;
- packages the complete install bundle and `SHA256SUMS`;
- runs without any connected phone or flashing command;
- is followed by a separately recorded hardware boot test for the exact device variant.

Until those steps exist, GitHub Actions validation is not a claim that a flashable image was produced.


## Assembling the current prototype in GitHub Actions

The manual workflow `.github/workflows/assemble-oneplus8-prototype.yml` combines a successful Batocera baseline run with a successful ARMDeck handoff run. Supply both run IDs, the exact commit SHAs used by those runs, and the **measured** IN2017 `super` partition size in bytes. The workflow requires a self-hosted Linux runner with working loop devices, mount privileges, `img2simg`, and the other image tools. It rejects ambiguous or missing `rootfs.squashfs`, `boot.img`, or source manifests.

It first unpacks and inspects `boot.img` and fails closed if the ramdisk lacks `/init`, `/init.batocera`, or the expected handoff markers. It then creates and validates the nested two-partition image, and uploads an inspection bundle containing the boot image, boot-inspection report, sparse super image, optional DTBO, source manifests, handoff diff, checksums, and docs. The bundle is explicitly marked `prototype-not-for-flashing`; the workflow does not create a flashing script or GitHub Release. Do not guess `super_bytes` or use this artifact on the phone before the separate IN2017 verification and boot-test milestone.
