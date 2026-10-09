# ARMDeck device build in GitHub Actions

## Purpose and status

`.github/workflows/build-armdeck-device-packages.yml` is an intermediate build gate. It builds the OnePlus 8 kernel and device packages from exact ARMDeck and pmaports commits, then exports the ordinary postmarketOS boot artifacts. It does **not** build a Batocera-enabled `boot.img`, assemble the embedded `super.img`, or publish a release. Do not flash its artifacts as Batocera.

The workflow uses a dedicated self-hosted runner because pmbootstrap builds use chroots, mounts, loop devices, and significant disk space. It requires an isolated runner, not a general-purpose machine with unrelated workloads.

## Runner contract

The runner needs Linux x86-64, `git`, `python3`, `pmbootstrap`, working `sudo` for pmbootstrap's loop/mount operations, and enough disk for kernel sources, Alpine chroots, packages, and image exports. It must be labelled `self-hosted`, `linux`, `x64`, and `armdeck-builder`.

**Important runner constraint:** the workflow expects `pmbootstrap status` to report that its active aports checkout is the job's `pmaports-src` directory. A normal persistent self-hosted runner cannot reliably point a pre-initialized pmbootstrap installation at a new GitHub Actions workspace on each run without additional configuration. The current workflow intentionally fails rather than building against an unknown or floating pmaports checkout. The runner bootstrap still needs to implement a clean per-job pmbootstrap configuration before this workflow can run successfully.

## Trigger

1. Open **Actions → Build ARMDeck OnePlus 8 device packages (intermediate) → Run workflow**.
2. Enter the full 40-character commit SHA for `lucas-wb/ARMDeck-batocera` and the full 40-character commit SHA for postmarketOS `pmaports`.
3. Review the build logs and source manifest in the uploaded artifact.

The source commits are explicit inputs so that builds can be reproduced. Do not use branch names or floating `master`/`edge` revisions for release builds. The current job also depends on a first-time pmbootstrap initialization on the self-hosted runner; that initialization is not yet fully automated by the workflow.

## What this proves

A successful run proves that the selected kernel and device package recipes built in that runner environment and that pmbootstrap exported non-empty boot artifacts. It does not prove the initramfs handoff patch applies, that the Batocera root filesystem is embedded correctly, that IN2017 partition sizes and block-device paths are correct, or that the device boots.

## Next gates

1. Make pmbootstrap initialization isolated and deterministic per run.
2. Apply and test the PID 1 handoff patch against the exact postmarketOS initramfs source revision.
3. Stage the Batocera init in the generated initramfs and verify all runtime tools are present.
4. Build Batocera userspace at an exact commit and assemble the two-partition image using measured target capacity.
5. Inspect boot image, initramfs, filesystem labels, partition table, sparse image, and checksums.
6. Only then enable a separate packaging workflow. Release publishing remains disabled until the install bundle is complete.


## Batocera handoff mode (prototype)

The device-package workflow now requires three full commit SHAs: ARMDeck, pmaports, and Batocera. It applies `integration/prepare-pmaports-handoff.sh` before building. That helper modifies only the per-run pmaports checkout; it does not commit or push changes upstream. It patches `init_2nd.sh` in the local `postmarketos-initramfs` package, includes the stock Batocera init as `/init.batocera` in the initramfs, and adds `armdeck.batocera=1` to the OnePlus device kernel command line.

The handoff maps the Android GPT `super` partition by `PARTLABEL=super` or the optional `superdev=` kernel argument, then uses `kpartx` to expose the MBR partitions inside the image written to `super`. The image's boot filesystem must carry the exact `BATOCERA_BOOT` label. If the source package changes the init script anchors, the helper stops rather than silently creating a different boot image.

The workflow artifact is still an intermediate boot-chain artifact. It does not yet contain the Batocera SquashFS inside `super.img`, and no install ZIP is published. The helper's automated test uses a synthetic pmaports fixture; a successful real pmbootstrap run and archive inspection are still required before calling this integrated stage operational.
