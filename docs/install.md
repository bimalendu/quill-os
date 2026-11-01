# Installing Quill OS on an Apple Silicon Mac

> **Not yet tested on Apple Silicon hardware.** The installer folder is built and
> checked in a Linux container, and `install.sh --verify` has been run on macOS.
> No Mac has installed Quill OS from it yet. Install on a Mac you can afford to
> restore, and back up first.

## What you get

`make installer-pkg` builds one self-contained folder, `quill-os-<release>-<date>/`:

| File | Purpose |
|---|---|
| `install.sh` | The starting point. Checks the folder, then runs the bundled installer. |
| `installer_data.json` | The systems offered: Quill OS with KDE Plasma, and Quill OS Minimal. |
| `os/*.zip` | The two OS images, packaged the way Asahi's installer expects. |
| `installer-<version>.tar.gz` | Fedora Asahi Remix's installer, unmodified and pinned by hash in `installer/installer.lock`. |
| `SHA256SUMS` | A checksum of every other file. |
| `README.txt` | The short version of this page. |

Nothing is downloaded from a Quill server. The only network use is Apple's
firmware, which the Asahi installer fetches from Apple during installation.
The installer sends no statistics: `REPORT` is left unset.

## Get the folder

    make fetch-installer     # copies the newest folder to ./out/installer/ (about 5 GB)

Copy the whole folder to the target Mac (USB disk or AirDrop) and keep its files together.

## Install

1. Back up your data. The installer shrinks macOS to make room, which changes the
   partition table. An interrupted install can usually be recovered, but that is not guaranteed.
2. In Terminal: `cd "<the folder>"`, then `./install.sh --verify`. It checks every
   file against `SHA256SUMS` and installs nothing. macOS may ask whether Terminal
   may read the disk the folder is on.
3. Run `./install.sh`. It asks you to confirm, then starts Asahi's installer, which asks how
   much space to give Quill OS and which system to install, and reboots once into
   Apple's recovery screen. Follow the instructions it prints there.
4. First boot starts Quill Setup, where you choose your software.

## Recovery and uninstall

Asahi Linux documents both: <https://asahilinux.org/docs/> (Uninstall, and Platform notes).

## How it is tested

| Check | Where | What it shows |
|---|---|---|
| `make check-installer` | build container, volume read-only | Both zips and `installer_data.json` are well formed; `boot.img` and `root.img` are byte-identical to the raw images' partitions; hashes match the lock; a lock with the wrong hash stops the build. |
| `make test-bootstrap` | build container, fake macOS | `--verify` accepts the folder and rejects nine kinds of damage; the full bootstrap hands the pinned installer the right environment and the real `osinstall.load_package()` opens both packages. |
| `install.sh --verify` | this project's Mac, read-only | The script works with macOS's own `curl`, `shasum` and `plutil`, and writes nothing. |

The container tests run a copy of `install.sh` with two lines rewritten (the `/System`
marker and the `/dev/tty` prompt); the test asserts that nothing else differs. They use
only a scratch directory: no `/System`, no `/tmp/asahi-install`, no `sudo`.

**Not covered:** partitioning, m1n1, the Apple recovery step and booting the result.
Those need a real Mac.
