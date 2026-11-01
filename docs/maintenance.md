# Updates, snapshots and rollback

Decided 2026-10-31: updates are downloaded automatically and installed only
when you choose; snapshots are taken around every package change; rollback is
one command, keeping Fedora's disk layout.

## Updates (`quill-updates`)

| What | When | Installs anything? |
|---|---|---|
| `quill-update-download.timer` downloads system updates (PackageKit, the same cache Discover uses) and Flatpak updates (`--no-deploy`) | daily, and 15 minutes after boot; skipped on battery and metered connections | no |
| Discover's notifier shows that updates are ready | daily (`/etc/xdg/PlasmaDiscoverUpdates`) | no |
| You click *Update All* in Discover | when you choose | yes, on the next reboot (offline update) |

From a terminal, `sudo dnf upgrade` works as on any Fedora system.

Turn background downloads off: `sudo systemctl disable --now quill-update-download.timer`.
Change the reminder: System Settings > Software Update.

The Minimal image has no Discover and no background downloads; update it with
`sudo dnf upgrade`.

## Snapshots (`quill-snapshots`)

- At first boot, snapper is set up for `/`. A "First boot" snapshot is taken.
- Every package transaction gets a *pre* and a *post* snapshot, whichever tool
  runs it: `dnf`, Discover (PackageKit), Quill Setup. If snapper fails, the
  transaction still runs.
- No timeline (hourly) snapshots. At most 10 are kept, 4 of them marked
  important; `snapper-cleanup.timer` removes older ones.

See them:

    quill-rollback list          # or: snapper -c root list

### What a snapshot covers

The root subvolume: the operating system, `/etc`, and `/var` (including logs,
caches and system-wide Flatpaks). **Not** covered:

- `/home`: your files are never rolled back.
- `/boot`: the kernels and boot menu (a separate partition). See below.

Snapshots share unchanged data with the running system, but files changed
since a snapshot (updated packages, Flatpak runtimes) take extra space until
the snapshot is removed.

## Rolling back

    sudo quill-rollback list
    sudo quill-rollback to 12     # asks for confirmation
    sudo reboot

After the reboot, the system is as it was in snapshot 12, and the system you
left is kept as `root.old-<date>`. When you are happy, free the space:

    sudo quill-rollback cleanup

How it works: Quill OS keeps Fedora's layout (`/` is mounted with
`subvol=root`), where `snapper rollback` does not apply. `quill-rollback`
makes a writable copy of the snapshot, moves nested subvolumes (`.snapshots`,
`/var/lib/machines`) into it, then swaps it with `root` in one atomic rename.
At every step there is a bootable `root`.

**Kernels.** `/boot` is not rolled back. If the default kernel is newer than
the snapshot (its modules are not in the snapshot), `quill-rollback` makes the
newest kernel that the snapshot has modules for the default boot entry. The
newer kernel stays installed in `/boot` and the next `dnf upgrade` replaces it.

**If the system does not boot at all**, pick an older kernel in the GRUB menu
(hold Shift, or press Esc, during boot). From a rescue shell the same swap can
be done by hand:

    mount -o subvolid=5 /dev/<root partition> /mnt
    btrfs subvolume snapshot /mnt/root/.snapshots/N/snapshot /mnt/root.new
    rmdir /mnt/root.new/.snapshots && mv /mnt/root/.snapshots /mnt/root.new/
    mv -T --exchange /mnt/root.new /mnt/root
    mv /mnt/root.new /mnt/root.old-manual

## Not covered

- Rolling back `/home`, or individual files (use `snapper undochange` or copy
  from `/.snapshots/N/snapshot/` instead).
- Detecting a Discover update in progress: do not roll back while Discover is
  installing.
- Firmware: Apple firmware updates come with macOS, not Quill OS.
