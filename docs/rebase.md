# Rebasing on upstream

Quill OS is a thin fork. Two things move upstream and need a deliberate rebase:
the Fedora Asahi Remix kiwi descriptions (`kiwi/`), and Asahi's installer
(`installer/installer.lock`). A new Fedora release is a third, rarer move.

Everything here runs locally. Nothing in it publishes anything.

## 1. The kiwi descriptions

`kiwi/UPSTREAM` records where the copy came from: repo, branch and commit.
Commit `9cdc28c` ("Import upstream kiwi-descriptions f44 snapshot unmodified")
is the pristine import, so `git diff 9cdc28c..HEAD -- kiwi` is exactly what
Quill changed.

Files Quill has changed: `components/base.xml`, `components/boot.xml`,
`components/desktop-environments.xml`, `config.sh`, `config.xml`,
`platforms/minimal.xml`, `platforms/vm.xml` (new), `platforms/workstation.xml`,
`post_bootstrap.sh`, `repositories/asahi.xml`, `repositories/quill.xml` (new).
`platforms/server.xml` was removed. `make-asahi-installer-package.sh` is kept
for reference only; `installer/make-package.sh` is what Quill runs.

To move to a newer upstream commit:

1. Clone upstream at the branch in `kiwi/UPSTREAM` (`git clone --branch f44 <repo> <empty dir>`) and note the new commit hash.
2. Make the old pristine tree: `git archive 9cdc28c kiwi | tar -x -C <old dir>`. Take the diff between the old tree and the new upstream tree. That is what upstream changed.
3. Apply it to `kiwi/` by hand or with `git apply --3way`, and resolve conflicts in the files listed above. Read the diff; do not skip it.
4. Update `kiwi/UPSTREAM` (commit and `imported:` date).
5. Check, in order: `make test`, `make check-no-ai`, `make image PROFILE=Minimal`, `make check-image PROFILE=Minimal`, then the same for `Workstation-KDE` and `VM-KDE`, `make check-branding`, and `make vm-test`.
6. A new upstream package that is on `policy/ai-denylist.txt` fails `check-image`. Handle it the way `docs/no-ai-policy.md` describes.

## 2. Asahi's installer

`installer/installer.lock` pins the version and sha256 of the bundled installer.
`make installer-lock` fetches upstream's newest and writes a new lock; it moves the pin
and does not install anything. Before committing it:

1. Read what changed upstream in the installer's release notes and repository history.
2. Check `installer/install.sh` still provides everything the installer reads: `VERSION_FLAG`, `INSTALLER_BASE`, `INSTALLER_DATA`, `REPO_BASE`, `DISTRO`, `DISTRO_DOCS`. `tests/test-bootstrap.sh` runs the real installer's `load_package()`, so a changed contract usually fails there.
3. Rebuild and re-run `make installer-pkg`, `make check-installer`, `make test-bootstrap`.
4. A run of `install.sh` on a Mac is still the only test of the partitioning steps. Do not claim a new pin works on hardware until it has been installed on hardware.

## 3. A new Fedora release

`FEDORA_RELEASE` in the `Makefile` selects the builder image and the kiwi branch.

1. Import the new upstream branch as in step 1, as its own "unmodified" commit, then re-apply Quill's changes.
2. Package names change between releases. `make check-image` and `make check-group-packages` fail loudly on a name that no longer exists. Do not paper over a failure by deleting the check.
3. The package versions in `packages/*/*.spec` carry the release (`44`). Bump them together.
4. Rebuild all three profiles (`Minimal`, `Workstation-KDE`, `VM-KDE`), run every check, and run `make vm-test` on the VM image.

## 4. Fedora identity that stays

Some Fedora names are kept on purpose, because other packages require them; the list is in `docs/build-notes.md` under "Fedora identity that remains, on purpose". After a rebase, `make check-branding` is what shows whether new Fedora branding has crept in.

## CI

`.github/workflows/ci.yml` runs `make test` and builds the RPMs. It does not build images, and it does not publish. COPR, signing with a real key and releases are not set up; they need decisions that have not been made.
