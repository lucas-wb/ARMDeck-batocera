# CI status and engineering gates

There are four workflows:

- `validate.yml` runs inexpensive static checks and a synthetic integration fixture on GitHub-hosted runners.
- `build-batocera-sm8250.yml` is a manually triggered, resource-intensive build on a dedicated self-hosted runner. It requires the exact 40-character Batocera commit SHA as input and attempts the upstream `make sm8250-build` target.
- `build-armdeck-device-packages.yml` takes exact ARMDeck, pmaports, and Batocera commit SHAs. It patches the pinned postmarketOS initramfs package, stages Batocera's stock init into the OnePlus device package, builds the initramfs/kernel/device packages, then exports an **integrated boot-chain intermediate**. It still requires a correctly initialized pmbootstrap runner.
- `assemble-oneplus8-prototype.yml` downloads artifacts from the two successful build runs, requires an explicitly supplied and measured `super` capacity, builds and validates the nested image, and uploads an inspection bundle. It does not publish a release or flash a device.

The Batocera workflow is a **baseline build only**. The ARMDeck workflow produces the matching boot-chain intermediate, and the assembly workflow joins them into a prototype bundle. None of these workflows publishes a release or establishes that the OnePlus 8 boots.

## Why there is no release workflow yet

A release workflow must not package generic SM8250 artifacts as if they were compatible with the OnePlus 8. These inputs and build stages still need to be implemented and pinned:

1. Execute the integrated ARMDeck workflow against real pinned source revisions; its initramfs patch has only passed a synthetic fixture test so far.
2. The assembly workflow now automatically inspects the generated Android `boot.img` ramdisk and rejects missing `/init.batocera` or handoff markers. Inspect the report and confirm the full initramfs, `kpartx`, `blkid`, and expected device mappings are present.
3. Run both build workflows and confirm the baseline artifact contains exactly one `rootfs.squashfs` and the ARMDeck artifact contains the integrated `boot.img`.
4. Verify the IN2017 physical `super` partition capacity and confirm whether the selected fastboot path accepts the produced Android-sparse image.
5. Run the assembly workflow and inspect its nested image validation, source manifests, and handoff diff.
6. Inspect the actual generated boot image's initramfs to confirm the handoff and tools are present.
7. Add beta/stable publication only after build validation. Hardware boot testing remains a separate later gate.

## Runner requirements

The build workflow expects a self-hosted Linux x86_64 runner labelled `batocera-builder`, with Docker, Git, GNU Make 4.3+, and substantial free disk space. The workflow prints disk capacity before building. Determine actual disk use from a successful baseline run before attempting the full image build. Do not treat GitHub Actions cache as storage for the complete Buildroot output tree.

## Release status policy

Until all end-to-end build gates exist, artifacts must be called **baseline** or **prototype**, never “flashable”, “stable”, or “tested”. Hardware qualification is a separate step and must name the exact model variant and test result.
