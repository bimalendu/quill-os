# Quill OS

A lightweight, polished, AI-free Linux distribution for Apple Silicon Macs.
Quill OS is a thin fork of [Fedora Asahi Remix](https://fedora-asahi-remix.org/)
with KDE Plasma. It adds no drivers of its own: kernel, GPU, audio and firmware
support come unchanged from the Asahi Linux project and Fedora.

Status: **Phase 2 of 8** (unmodified baseline image builds; trimming next). Nothing is installable yet.

## Targets

- Native install on M1 and M2 Macs (M3 support follows Asahi's progress).
- An aarch64 VM image for every M-series Mac, including M4 and M5.

## Building

Requires macOS on Apple Silicon with [Podman](https://podman.io/) installed.

    make doctor        # check the host
    make machine       # create the rootful 'quill-build' podman machine
    make builder       # build the Fedora builder container
    make kiwi-version  # prove the kiwi-ng toolchain runs
    make test          # repository checks

`make help` lists every target. Targets for later phases fail with a message
naming the phase that implements them.

## License

GPL-3.0-or-later, matching the upstream Fedora Asahi kiwi descriptions this
repo forks. See `LICENSE`. Upstream provenance is recorded in `kiwi/UPSTREAM`.
