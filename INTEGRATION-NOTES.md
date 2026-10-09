# Integration status

The first prototype's `/init` wrapper was useful to prove the intended handoff, but the staging script alone did not rebuild the Android boot image. The native integration under `integration/` now defines the packaging path more concretely: patch `postmarketos-initramfs`'s PID-1 `init_2nd.sh`, stage Batocera's init as `/init.batocera`, and use mkinitfs's source-to-destination file list.

The PMOS stage-2 source currently runs `mount_subpartitions` before `/hooks-extra`, and that function is called by PID 1. The new handoff patch is placed immediately after that call so the partition mapper should exist before label lookup. `run_hooks` cannot perform the handoff itself because each hook runs in a child shell.

This is still not a ready-to-flash build: no full pmbootstrap package rebuild, generated initramfs inspection, IN2017 storage-path verification, or hardware boot has been performed. The old wrapper files remain for comparison but should not be used in parallel with this native patch.
