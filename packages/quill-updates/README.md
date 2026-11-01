# quill-updates

Quill OS downloads updates in the background and lets you decide when to
install them.

- `quill-update-download.timer` runs daily (and 15 minutes after boot):
  `pkcon refresh`, `pkcon --only-download update` and
  `flatpak update --system --no-deploy`. Nothing is installed.
- It skips the run on battery power and on metered connections.
- Discover shows the update notification; "Update All" then installs on the
  next reboot (offline updates, Discover's Fedora default), using the
  downloaded packages.

To turn background downloads off:

    sudo systemctl disable --now quill-update-download.timer
