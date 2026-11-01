# quill-snapshots

Snapshots of the system before and after every package transaction, and a
command to return to one.

- At first boot, `quill-snapshots-setup.service` creates the snapper
  configuration `root` for `/` from the `quill` template: no timeline
  snapshots, at most 10 kept (4 marked important), and members of `wheel` can
  list them. It also takes a "First boot" snapshot.
- `/etc/dnf/libdnf5-plugins/actions.d/quill-snapper.actions` takes a pre and a
  post snapshot around every dnf5 transaction: `dnf`, Discover (PackageKit's
  dnf5 backend) and Quill Setup. A failing snapshot never stops a transaction.
- `quill-rollback list | to N | cleanup` restores a snapshot (see
  `quill-rollback --help` and `docs/maintenance.md` in the Quill OS sources).

What is not covered: `/home` (a separate subvolume) and `/boot` (a separate
ext4 partition, which holds the kernels). Logs, caches and system Flatpaks
under `/var` are part of the system and roll back with it.
