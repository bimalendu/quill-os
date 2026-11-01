# Build notes: running kiwi on an Apple Silicon Mac

`make image` builds inside a rootful Podman machine (`quill-build`). Getting
there needed five workarounds. Each one is in the repo; this explains why.

| Symptom | Cause | Fix |
|---|---|---|
| `rsync ... fremovexattr("security.selinux") Permission denied` | The kiwi description sat on the macOS bind mount, which has no SELinux labels. kiwi's `rsync -X` then tries to remove the label from the copy, which SELinux never allows. | `make sync-src` copies `kiwi/` into a VM-side volume first. |
| `setfiles: Could not set context ... Invalid argument` | The VM (Fedora CoreOS) policy lacks modules such as mysql, so the kernel rejects labels the image's own policy uses. | `selinux=0` kernel argument on `quill-build` only. Undo with `rpm-ostree kargs --delete=selinux=0`. |
| `Device /dev/loop0p1 does not exist` | A container's static `/dev` never gets partition nodes after `losetup -P`. | `-v /dev:/dev` in `KIWI_RUN`. |
| `Cannot download ibus-m17n ... All mirrors were tried` | Package was in Fedora `updates` metadata but missing from every mirror (2026-10-30). | `<ignore name="ibus-m17n"/>`; remove once Fedora fixes the repo. |
| `/boot` files unlabelled (`unlabeled_t`): logind denied reading the boot entry | Files created while the image is assembled (`grub.cfg`, the boot entry, `lost+found`) get no SELinux label when the builder has SELinux off, as here and on CI runners. | `quill-release-common` ships `/usr/lib/tmpfiles.d/quill-boot-labels.conf` (`Z /boot - - -`), which restores the labels at every boot. `make vm-test` checks the labels and that there are no denials. |
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

## Branding (Phase 3)

Quill's packages live in `packages/` and are built by `make rpms` into the
`quill-rpms` podman volume (an rpm-md repo, signed with a throwaway dev key held
in the `quill-keys` volume, never in git). `make image` mounts it at
`/quill-repo`; `kiwi/repositories/quill.xml` points at it. For releases, replace
that repository with the published one and its real signing key.

| Package | Replaces | How |
|---|---|---|
| `quill-release` (+ `-common`, `-kde-desktop`, `-identity-*`) | `fedora-asahi-remix-release*`, `fedora-release*` | Provides `fedora-release`, `fedora-release-common`, `fedora-release-kde`, `system-release`, keeps the `%fedora` / `.fc44` macros. `ID=quill`, `ID_LIKE=fedora`. |
| `quill-logos` | `fedora-logos` | Provides `system-logos`, the capability the Fedora KDE and Plymouth packages require. Ships `start-here` (launcher icon) and `system-logo-white.png` (Plymouth watermark, About this system). |
| `quill-backgrounds-kde` | `f44-backgrounds-*`, `desktop-backgrounds-*` | Provides `system-backgrounds-kde`. Wallpapers are generated at build time by `gen-wallpaper.sh`. |
| `quill-plasma-theme` | the Fedora look and feel *as default* | Colour schemes, two look-and-feel packages, `/etc/xdg/kdeglobals`, `/etc/xdg/kscreenlockerrc`, and `/usr/lib/plasmalogin/defaults.conf` (replaces `kde-settings-plasmalogin`). |

### How the theme overrides Fedora without forking kde-settings

Fedora's Plasma session sets
`XDG_CONFIG_DIRS=/etc/xdg:/usr/share/kde-settings/kde-profile/default/xdg`
(`/etc/xdg/plasma-workspace/env/env.sh`). `/etc/xdg` comes first, so Quill's
`/etc/xdg/kdeglobals` wins over kde-settings' `LookAndFeelPackage` and
`ColorScheme`.

### Fedora packages excluded, and why

`ignore` is `dnf --exclude=NAME` (package names and globs only):

- `fedora-logos`, `fedora-release*`, `fedora-asahi-remix-release*`,
  `f44-backgrounds*`, `desktop-backgrounds*`, `breeze-icon-theme-fedora`,
  `fedora-bookmarks`, `plasma-welcome-fedora`: Fedora branding.
- `abrt*`, `gnome-abrt`, `libreport-fedora`: ABRT's workflows file crash
  reports on Fedora's Bugzilla. `libreport-filesystem` stays (mdadm requires it).
- `NetworkManager-config-connectivity-fedora`: requested
  `fedoraproject.org` on every connection. Side effect: no automatic
  captive-portal sign-in pages.
- `mediawriter`: carries the Fedora logo.

### Fedora identity that remains, on purpose

- `plasma-lookandfeel-fedora`: `plasma-workspace` requires it at an exact
  version. It only adds "Fedora" entries to Settings > Appearance.
- `fedora-repos`, `fedora-gpg-keys`, `fedora-workstation-repositories`,
  `fedora-third-party`, `fedora-flathub-remote`: functional.
- `fedora-asahi-remix-scripts`, `fedora-asahi-remix-appstream-metadata`:
  functional Asahi tooling that carries the old name.
- The m1n1 boot logo is Asahi's, inside `boot.bin`.
- `/usr/share/wallpapers/Fedora`: a dangling symlink from `kde-settings-plasma`.

### Placeholders to replace before publishing

- All URLs are `https://quill-os.example/...`.
- The logo (`packages/quill-logos/quill-mark.svg`) is a drawn placeholder.
- Licenses: artwork CC-BY-SA-4.0, release package MIT, theme GPL-2.0-or-later.
  `Quill-Legal-README.txt` is a draft that needs legal review.
- Seen in the VM on 2026-10-31 (user report): the login screen and the Plasma
  session look as intended. On Apple Silicon hardware: not yet seen.

### Image checks

- `make check-image PROFILE=...` asserts the package list.
- `make check-branding PROFILE=...` mounts the built image and asserts
  `os-release`, leftover `fedora-logo*` files, the default look and feel, the
  login wallpaper and that nothing contacts Fedora by default.
- Final Phase 3 results: `Workstation-KDE` 2004 packages (baseline 2251, trimmed
  before branding 2049); `Minimal` 818 packages. Both pass `check-image` and
  `check-branding`.
- `satyr` and `python3-libreport` stay in the image: Minimal's `initial-setup`
  needs them (initial-setup -> anaconda-tui -> python3-meh -> python3-libreport
  -> satyr). The KDE image also gets them. ABRT itself is not installed.
- Minimal needs its own bootstrap `quill-release`, as KDE does, or dnf
  bootstraps Fedora Asahi Remix's release package and then conflicts.

## No-AI policy (Phase 4)

See `docs/no-ai-policy.md`. Image checks added: `make check-no-ai` (policy file
valid against the image's Firefox schema) and `make check-firefox` (the image's
Firefox started headless; asserts the policy is applied). `make check-image`
now also runs the denylist gate. `Workstation-KDE`: 2005 packages.

## Quill Setup (Phase 5)

See `docs/quill-setup.md`. `Workstation-KDE`: 2006 packages. `make rpms` now
builds `quill-setup` from a source tarball it creates from
`packages/quill-setup/src/`. The builder image gained Qt 6, Kirigami, flatpak,
polkit and desktop-file-utils.

## Disk space on the Mac

The build machine's disk file (`~/.local/share/containers/podman/machine/applehv/quill-build-arm64.raw`)
only grows: blocks freed inside the VM stay allocated on macOS. On 2026-10-30 it
reached 78 GB while the VM used 33 GB, and the Mac fell to 17 GB free (97% full).
`make reclaim-space` runs `fstrim` in the VM and returned 46 GB. Run it after a
batch of builds, and `make doctor` warns when the Mac has under 25 GB free.
The VM disk is capped at 80 GB, and the Apple Silicon and VM images are each
15 to 32 GB while building.

## VM image (Phase 6)

See `docs/vm.md`. `VM-KDE`: 1960 packages, a 3.7 GB qcow2 (32 GiB virtual).
Checked with `make check-image check-branding check-no-ai check-firefox check-vm`.
Booted in UTM on 2026-10-31 (user report): GRUB, Plasma Setup, the Quill login
screen, the desktop and Quill Setup all appeared and worked.

The Apple Silicon packages were split out of `Common` into an `AsahiPlatform`
profile, and the Asahi package repositories now apply only to it. After the
split the Apple Silicon images are unchanged: `Workstation-KDE` has the same
2006 package names as before, `Minimal` the same 818.

## Testing the VM image without a GUI (`make vm-test`)

`make vm-test` boots the qcow2 under QEMU in the build machine, with no KVM
(software emulation, about 2.5 minutes to SSH). The test key and `sshd` are
passed as systemd credentials, so the image is not modified. Two tests:
`smoke` (the system is healthy) and `maintenance` (snapshots, background
update downloads, rollback with a reboot; about 35 minutes under emulation).
QEMU gets 2 GiB: more gets it killed in the 4 GiB build machine. PackageKit
needs a longer start timeout under emulation; the test sets one.
`QUILL_INSTALL=1` installs the local `quill-*` packages into an older image
first. Run `make vm-test VM_TEST=explore` after writing commands to
`tests/vm/explore.cmds` to try something by hand in a booted guest.

## Rebuild after Phase 7a/7b (2026-11-01)

All three images were rebuilt with `quill-snapshots`, `quill-updates` (KDE
images only) and the `/boot` label fix, and checked:

| Image | Packages | check-image | check-branding | check-no-ai |
|---|---|---|---|---|
| VM-KDE | 1970 | pass | not re-run (see below) | not re-run (see below) |
| Workstation-KDE | 2016 | pass | pass | pass |
| Minimal | 829 | pass | pass | not applicable: Minimal has no Firefox, so `check-no-ai` (a Firefox policy check) fails by design |

For VM-KDE, only `check-image` was run on the rebuilt image: its raw disk was removed to free space, and `check-branding` and `check-no-ai` read the raw disk. The booted-VM smoke test covers the same ground at runtime (os-release says Quill OS, the Firefox policy is present). VM-KDE also passes `make vm-test` (smoke and maintenance). The Apple Silicon
images are checked statically only: no Apple Silicon hardware has booted them.
