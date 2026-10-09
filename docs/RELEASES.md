# Release readiness

No beta or stable release is published by this prototype. Builds are performed locally and artifacts are reviewed manually. GitHub Actions is not part of the build pipeline.

Before any release is called flashable, all of the following must be true:

- All sources are pinned to exact commit SHAs and recorded in manifests.
- Official Batocera SM8250 build completes successfully from `batocera-linux/batocera.linux`.
- ARMDeck/pmaports handoff and device package build complete successfully.
- Generated boot image passes static inspection and its kernel command line and ramdisk are reviewed.
- Embedded image passes read-only partition/filesystem validation and includes checksums and source manifests.
- Installation and recovery instructions are written and verified for the exact IN2017 variant.
- A controlled hardware boot test succeeds and results are documented, including display, controls, storage, audio, charging behavior, reboot, and recovery.

Until then, label output `prototype-not-for-flashing`. Never include a flashing script that guesses partition size or assumes a block-device path. Do not flash vbmeta, bootloader, radio, firmware, or unrelated partitions by default.
