# Build notes: running kiwi on an Apple Silicon Mac

`make image` builds inside a rootful Podman machine (`quill-build`). Getting
there needed five workarounds. Each one is in the repo; this explains why.

| Symptom | Cause | Fix |
|---|---|---|
| `rsync ... fremovexattr("security.selinux") Permission denied` | The kiwi description sat on the macOS bind mount, which has no SELinux labels. kiwi's `rsync -X` then tries to remove the label from the copy, which SELinux never allows. | `make sync-src` copies `kiwi/` into a VM-side volume first. |
| `setfiles: Could not set context ... Invalid argument` | The VM (Fedora CoreOS) policy lacks modules such as mysql, so the kernel rejects labels the image's own policy uses. | `selinux=0` kernel argument on `quill-build` only. Undo with `rpm-ostree kargs --delete=selinux=0`. |
| `Device /dev/loop0p1 does not exist` | A container's static `/dev` never gets partition nodes after `losetup -P`. | `-v /dev:/dev` in `KIWI_RUN`. |
| `Cannot download ibus-m17n ... All mirrors were tried` | Package was in Fedora `updates` metadata but missing from every mirror (2026-10-30). | `<ignore name="ibus-m17n"/>`; remove once Fedora fixes the repo. |
| `kiwi-ng --version` exits 1 | kiwi 11 exits 1 for `--version` and `--help`. | `make kiwi-version` checks the output, not the exit code. |

Also: `kiwi-ng image info --resolve-package-list` cannot expand `$releasever`
in upstream's repo URLs, so there is no dry-run validation. The only check is
a real build.

## Baseline numbers (unmodified upstream Workstation-KDE, f44)

- Build time on an M1 (4 CPUs, 4 GiB VM): about 18 minutes, 59 GB free of 80 GB afterwards.
- 2251 packages, 9.4 GB root subvolume, 15 GB sparse raw disk.
- Partitions: 500 MB EFI (with `m1n1/boot.bin`), 1 GB ext4 `/boot`, btrfs root with `root` and `home` subvolumes.
- Kernel `7.2.12-402.asahi.fc44.aarch64+16k`.

## Trimmed image (Workstation-KDE after Phase 2 trimming)

- 2049 packages (baseline 2251), 8.1 GB root (baseline 9.4 GB). Same kernel,
  same `m1n1/boot.bin`. `make check-image` passes.
- Removed: KDE PIM stack, LibreOffice, Elisa, KDE Connect, the extra
  kde-apps (games, Krusader, KTorrent, NeoChat, KRDC, ...), GNOME and Server
  profiles.
- Still large and untouched: the rest of `kde-media` (digiKam, K3b, Kamoso,
  Dragon, KolourPaint), Firefox, fonts, input methods, firmware.
- `keditbookmarks` stays because `konsole` requires it.
- kiwi's `<ignore>` is `dnf --exclude=NAME`: it matches package names and
  globs, not `@groups`. Upstream's `@dial-up`-style ignores are therefore
  probably no-ops. The `kde-desktop-environment` environment installs the
  kde-pim, kde-apps and libreoffice groups by default, so each must be
  excluded by package name.

## Differences from the original plan

- Fedora 44 KDE uses `plasma-setup` for first boot, not Calamares. Phase 5
  needs a different mechanism for the package picker.
- The login manager is Plasma Login Manager, not SDDM. Phase 3 themes that.
- The default editor is KWrite; Kate is not installed. Add it to the
  Developer group.
- Profile names stay as upstream's (`Workstation-KDE`, `Minimal`) to keep
  rebases small.
- `kiwi-ng image info --resolve-package-list` cannot validate the package
  set offline, so validation is a real build (about 18 minutes).
