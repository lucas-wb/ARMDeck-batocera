# ARMDeck + Batocera for OnePlus 8 — prototype

This project is exploring Batocera's userspace and EmulationStation on the OnePlus 8 family, using ARMDeck's postmarketOS/kernel/device foundation. The goal is to minimize Batocera-side changes and keep phone-specific boot/storage work on the ARMDeck side.

## Important status

**This is not currently a flashable build. Do not flash any prototype artifact to a phone.** There is no fully automated build of Batocera + kernel/initramfs/Android boot image yet, and no successful IN2017 boot test. The prototype's shell syntax/staging checks are not evidence that the phone will boot.

ARMDeck lists the OnePlus 8 IN2013 as tested; T-Mobile IN2017 remains unverified. See <https://github.com/GabrielCRadu/ARMDeck>.

## Intended storage layout

- An image stored inside Android `super` contains two partitions: `BATOCERA_BOOT` and userdata.
- The boot partition contains `/boot/batocera` (Batocera SquashFS), optional `/boot/rufomaculata`, and `/batocera-boot.conf`.
- The userdata partition contains `/batocera/roms`, `bios`, `saves`, and `system`.
- `batocera-boot.conf` uses `sharedevice=DEV <userdata UUID>` and `autoresize=false`, preserving Batocera's normal userdata mount behavior as far as practical.

## Documentation

- [Flashing and installation status](docs/FLASHING.md)
- [Build from source](docs/BUILDING.md)
- [Betas and stable releases](docs/RELEASES.md)
- [CI status and remaining build gates](docs/CI-STATUS.md)
- [Initramfs integration notes](integration/README.md)

## Prototype scripts

- `build-super-image.sh` creates a two-partition image file; it never flashes a device.
- `validate-super-image.sh` performs read-only image validation.
- `integration/` contains the experimental PID-1 handoff patch and initramfs staging script.
- `prepare-initramfs.sh` and `init` are an earlier wrapper-based prototype retained for comparison; prefer the native integration approach when continuing the work.

## CI

`.github/workflows/validate.yml` runs syntax/lint checks and uploads a small validation artifact. It is intentionally not labelled as a build or release workflow. Release publication must remain disabled until the pinned Batocera and ARMDeck build steps are complete and the resulting images pass automated inspection.

## Safety

This design may replace Android system/vendor/product contents and make Android unrecoverable without restoring stock firmware. Back up important data, keep a tested recovery path, and do not assume another OnePlus 8 variant has the same partition layout. No prototype script contains a phone-flashing command.

## CI workflows

- **Validate prototype** runs static checks on pull requests and development pushes.
- **Build Batocera SM8250 baseline** is a manual, expensive build that runs on a dedicated self-hosted runner and requires a full Batocera commit SHA. Its output is only a generic SM8250 baseline; it is not flashable on the OnePlus 8.

See [CI status](docs/CI-STATUS.md) and [Building from source](docs/BUILDING.md) before running a build. No workflow flashes a device or publishes a release-ready OnePlus image at this stage.

## Batocera port status

This repository currently contains a prototype layout builder and experimental initramfs handoff integration. GitHub Actions does not yet produce a flashable OnePlus 8 Batocera release. See `docs/CI-STATUS.md` and `docs/ARMDECK-CI.md`.


The assembly workflow automatically unpacks the generated `boot.img` and checks that its ramdisk contains `/init`, `/init.batocera`, executable `kpartx` and `blkid`, and the Batocera handoff markers. This is a static build gate only; it does not claim that the IN2017 boots successfully.
