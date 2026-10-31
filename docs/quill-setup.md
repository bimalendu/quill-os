# Quill Setup: choosing software after install

The Asahi installer writes a prebuilt image, so packages cannot be chosen
during the macOS-side install. Quill Setup is the choice screen: it opens on
first login, and can be run again from the application menu.

Fedora 44 KDE's first-boot wizard (`plasma-setup`) creates the user, language
and keyboard, and has no software-selection step, so this is a separate app
that starts after it.

## Behaviour

- Opens once per user at first login. Nothing is pre-ticked.
- **Install selected** asks for the administrator password (polkit), then
  installs the chosen groups.
- **Skip for now** or a successful install records "done"
  (`~/.config/quill-os/quill-setup/done`); it will not open at login again. A
  failed install records nothing and offers **Try again**.
- Re-run it any time from the menu entry *Quill Setup*.
- At login it only opens for regular users (uid >= 1000). `plasma-setup` runs
  as a system user, so it never appears in Plasma's own setup session.

## Groups

Defined in `packages/quill-setup/src/groups/*.json`:
`developer`, `office`, `media`, `graphics`, `gaming`.

To add or change a group, edit its JSON file (keys: `id`, `name`,
`description`, `order`, `rpm`, `flatpak`; `id` must equal the file name), then:

    make test                  # structure, shell-syntax rejection, AI denylist
    make check-group-packages  # every name exists for aarch64 (needs network)

Steam is not offered. It is not in Fedora's repositories, and Flathub's Steam
is x86-only. FEX and muvm (x86 compatibility) are in the default image.

## How it is built

| Part | Where | Notes |
|---|---|---|
| Window | `src/qml/Main.qml` | Kirigami. The progress bar is drawn by hand so it renders on every Qt Quick style. |
| Backend | `src/backend.{h,cpp}`, `src/main.cpp` | Qt 6 C++. Runs `pkexec /usr/libexec/quill-setup-helper install <group ids>`. |
| Installer | `src/quill-setup-helper` | Python, runs as root. Takes **group IDs only**; package names come from the root-owned definitions and are re-validated. Calls `dnf5 install -y -- <names>` (the `--` stops anything being read as an option). |
| Policy | `src/data/org.quill.setup.policy` | polkit action bound to the helper path; admin authentication. |
| Autostart | `/etc/xdg/autostart/quill-setup.desktop` | `quill-setup --autostart`. |

The group installer is why the UI is not trusted: a compromised or buggy
interface can only choose among the five groups.

## Tests

| Command | What it proves |
|---|---|
| `make test` | Group definitions are well formed, bad input is rejected, no group contains a denylisted package. |
| `make check-setup-helper` | The helper as root with real dnf: refusals, dry run, failing transaction, Flatpak calls (mocked), a real install. |
| `make check-setup-app` | The installed RPM: file ownership, desktop and polkit files, autostart rules, the done marker. |
| `tests/shoot-setup-app.sh` | Builds the app and takes offscreen screenshots of every state. |
| `make check-branding` | The built image contains the helper, polkit policy, autostart entry and five groups. |

## Booting

In the VM (2026-10-31, user report) Quill Setup opened after the first login
and worked. The items below were not checked separately:


- The look in a real Plasma session. The screenshots are headless and
  software-rendered, with default fonts and no KWin.
- The polkit password prompt. There is no polkit daemon in the test container;
  only the policy file's validity is checked.
- A real Flatpak install (VSCodium is 216 MB plus its runtime). The helper's
  Flatpak commands are tested against a mock.
- Whether Flathub is reachable and enabled on a fresh install. The helper adds
  the `flathub` system remote if it is missing.
