# Installing a release on OnePlus 8

> **Status: not yet flashable.** This document defines the intended release install procedure, not permission to flash the current prototype. No release image has been built or boot-tested on the T-Mobile IN2017. Do not flash `super.img`, `boot.img`, or `dtbo.img` from prototype artifacts.

## Before installing a future release

1. Confirm the release explicitly lists your exact model (`IN2017`) as tested. IN2013-only or “OnePlus 8” generic wording is not enough.
2. Read that release's notes and known-issues list. Check the required bootloader state, firmware baseline, Android build, and whether the release wipes Android.
3. Back up anything you need. The expected design replaces Android's system/vendor/product contents and may make Android unrecoverable without restoring stock firmware. Do not rely on a backup stored only on the phone.
4. Download the release ZIP and `SHA256SUMS` from the same GitHub Releases page. Verify the ZIP hash on your computer before extracting it. A matching hash detects corruption; it does not by itself prove the release is trustworthy.
5. Install current Android platform-tools and verify `adb` and `fastboot` are available. Keep a known-good MSM recovery package for the exact IN2017 variant and understand its use before proceeding.
6. Charge the phone and use a reliable USB cable and direct USB port. Disconnect other Android devices to avoid targeting the wrong device.

## Install procedure for a release

The final release must include a versioned `INSTALL.md` with the exact commands for that build. Follow that file verbatim. The installer is expected to:

- verify that the connected device reports the expected product/variant before writing anything;
- print every target partition and require an explicit confirmation;
- flash only the images listed in that release's manifest;
- stop on any failed command and never continue after a device/product mismatch;
- never flash `vbmeta`, firmware, bootloader, or radio partitions unless a future release explicitly documents and justifies the change.

Do **not** guess a `super` capacity or Linux block-device path from another OnePlus 8 variant. Do not substitute `fastbootd` for bootloader fastboot (or vice versa) unless the release instructions explicitly require it. These details are not verified for IN2017 yet.

## First boot and recovery

The release notes must state the expected first-boot behavior and a tested recovery route. Until those are available, there is no supported first-boot or rollback procedure. If a future install fails, do not repeatedly flash different partitions experimentally; capture the exact console output and follow that release's recovery instructions.

## Prototype status

The prototype assembly workflow may produce generated `boot.img` and `super.img` files for inspection, but neither is verified or boot-tested on IN2017. The bundle deliberately includes no installer. It is **not safe to flash**.
