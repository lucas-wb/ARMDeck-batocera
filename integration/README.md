# Native postmarketOS initramfs integration (experimental)

This integration replaces the earlier `/init` wrapper approach with a handoff from `init_2nd.sh`, which is PID 1 when it reaches the handoff. This matters because postmarketOS `run_hooks` executes each hook as a child shell; a hook cannot safely call `switch_root` as PID 1.

## Files

- `postmarketos-initramfs/0001-armdeck-batocera-handoff.patch`: after the normal PMOS subpartition setup, checks for `armdeck.batocera=1`, finds the physical `super` block device by `PARTLABEL=super` (or optional `superdev=` override), maps its embedded MBR partitions with `kpartx`, finds the `BATOCERA_BOOT` filesystem, and `exec`s the staged Batocera init as PID 1.
- `prepare-pmaports-handoff.sh`: local build helper that patches the pinned pmaports source package, updates the affected local-source checksums, stages the Batocera init in the OnePlus device package, and enables the selector kernel argument. It fails if expected source anchors have changed.
- `stage-batocera-init.sh`: older manual staging helper. The local build script uses `prepare-pmaports-handoff.sh` so the init is packaged into the initramfs through the device package.
- `device-package/00-armdeck-batocera.files`: mkinitfs file-list entry to include `/init.batocera` in the initramfs.
- `device-package/kernel-cmdline.conf.example`: selector flag. Preserve existing command-line entries; do not blindly replace the current file.

## Integration order

1. `scripts/build-armdeck-local.sh` checks out exact ARMDeck, pmaports, and Batocera commit SHAs.
2. `prepare-pmaports-handoff.sh` applies the initramfs patch, updates the checksum for the modified local `init_2nd.sh`, ensures `multipath-tools` is a package dependency, patches Batocera init's devtmpfs and direct-device mount behavior, and adds it to the device package's mkinitfs file list.
3. Build `postmarketos-initramfs`, the OnePlus kernel, firmware, audio, and device package before `pmbootstrap install` regenerates the boot image.
4. Inspect the generated initramfs archive and confirm `/init_2nd.sh`, `/init.batocera`, `blkid`, `kpartx`, and required filesystem tools are present before attempting to boot.

## Important limitations

- The patch maps the `super` partition itself via `kpartx`; it locates `super` by `PARTLABEL=super`, with an optional `superdev=/dev/...` override. Confirm the block-device discovery and mapper names in the generated initramfs before boot testing.
- The Batocera boot filesystem label must be exactly `BATOCERA_BOOT`.
- Do not enable Batocera mode until the stock PMOS boot is confirmed to work and the generated initramfs is inspected.
- No flash commands are included. No IN2017 super path or capacity is assumed verified.
- The preparation helper has passed a synthetic fixture test only. It is not yet validated against a full pmbootstrap build or a real phone boot.
