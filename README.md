# ARMDeck Batocera prototype for OnePlus 8

This repository contains an experimental integration of the official Batocera Linux userspace with the ARMDeck OnePlus 8 / postmarketOS boot chain. The target handset is a T-Mobile OnePlus 8 IN2017 (`instantnoodle`), but **IN2017 compatibility is not yet verified**.

## Build locally

There are no GitHub Actions build workflows. Use a dedicated native x86_64 Ubuntu host with substantial disk space:

1. Provision prerequisites: `sudo bash scripts/provision-ubuntu-build-host.sh`
2. Initialize pmbootstrap once: `pmbootstrap init`
3. Review [`docs/BUILDING.md`](docs/BUILDING.md) for local build commands and artifact locations. Batocera defaults to the latest official stable release; its exact resolved commit is recorded in the manifest.
4. Run synthetic/static checks: `bash scripts/run-local-checks.sh`

Batocera source must come from the official [`batocera-linux/batocera.linux`](https://github.com/batocera-linux/batocera.linux) repository. The Batocera build script resolves the latest stable release by default and records the exact commit SHA for reproducibility. ARMDeck and pmaports remain explicitly pinned. Do not substitute third-party images or forks.

## Current status

This is a development prototype, not a flashable release. The generic upstream SM8250 userspace, OnePlus kernel/boot chain, handoff patch, and nested `super` image need successful local builds and review. Static tests do not establish that the phone boots. No script flashes a device.

- [Local build instructions](docs/BUILDING.md)
- [Flashing and recovery safety notes](docs/FLASHING.md)
- [Release readiness](docs/RELEASES.md)
