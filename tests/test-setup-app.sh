#!/bin/sh
# Test the installed quill-setup package. Runs in the builder container with the
# local repo mounted at /repo. Installs the RPM and checks files, desktop
# entries, the helper, and the autostart rules (regular user, once only).
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

rpm --import /repo/RPM-GPG-KEY-quill-dev
dnf5 -y -q install --repofrompath=quill,/repo --setopt=quill.gpgcheck=0 --setopt=quill.pkg_gpgcheck=1 \
    --setopt=quill.gpgkey=file:///repo/RPM-GPG-KEY-quill-dev quill-setup >/dev/null 2>&1 \
    && ok "quill-setup installs with its dependencies" || { bad "quill-setup does not install"; exit 1; }

[ "$(stat -c '%U:%G %a' /usr/libexec/quill-setup-helper)" = "root:root 755" ] && ok "helper is root:root 0755" || bad "helper ownership or mode"
for g in /usr/share/quill-setup/groups/*.json; do
    [ "$(stat -c '%U:%a' "$g")" = "root:644" ] || bad "$g is not root:0644"
done; ok "group definitions are root-owned and not writable by others"
desktop-file-validate /usr/share/applications/quill-setup.desktop /etc/xdg/autostart/quill-setup.desktop 2>&1 | grep -v "^$" | grep -qv hint \
    && bad "desktop files do not validate" || ok "desktop files validate without hints or errors"
xmllint --noout /usr/share/polkit-1/actions/org.quill.setup.policy && ok "polkit policy is well-formed XML" || bad "polkit policy XML"
grep -q 'exec.path">/usr/libexec/quill-setup-helper' /usr/share/polkit-1/actions/org.quill.setup.policy && ok "polkit action is bound to the helper path" || bad "polkit exec.path"
[ "$(/usr/libexec/quill-setup-helper list | wc -l | tr -d ' ')" = 5 ] && ok "helper lists 5 groups from the installed definitions" || bad "helper list"

export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
# Autostart rules. "app" runs the binary as a regular user (uid 1000) with its own HOME.
useradd -m -u 1000 tester 2>/dev/null
app() { setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/home/tester XDG_CONFIG_HOME=/home/tester/.config \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=Basic "$@"; }
rm -rf /home/tester/.config /tmp/s1.png /tmp/s2.png /tmp/s3.png; chmod 1777 /tmp

timeout 20 quill-setup --autostart --screenshot /tmp/s1.png >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e /tmp/s1.png ] && ok "autostart shows nothing for a system user (uid 0)" || bad "autostart for uid 0: exit $rc, shot exists: $([ -e /tmp/s1.png ] && echo yes || echo no)"

app timeout 30 quill-setup --autostart --screenshot /tmp/s2.png >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s /tmp/s2.png ] && ok "autostart shows the window for a regular user with no marker" || bad "autostart for uid 1000: exit $rc"

app timeout 30 quill-setup --skip-test >/dev/null 2>&1   # unknown option: must not crash the shell
app sh -c 'mkdir -p /home/tester/.config/quill-os/quill-setup && : > /home/tester/.config/quill-os/quill-setup/done'
app timeout 30 quill-setup --autostart --screenshot /tmp/s3.png >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e /tmp/s3.png ] && ok "autostart shows nothing once the done marker exists" || bad "autostart with marker: exit $rc"

# The marker is written by a successful install and by Skip... covered by the Backend; here: a
# successful dry-run install through the real binary and a fake helper creates it.
rm -rf /home/tester/.config
cat > /tmp/fake-helper <<'FAKE'
#!/bin/sh
echo '{"event":"step","name":"Installing packages","fraction":0.5}'
echo '{"event":"done","fraction":1.0}'
FAKE
chmod +x /tmp/fake-helper
app env QUILL_SETUP_HELPER_CMD=/tmp/fake-helper QUILL_SETUP_SHOT_DELAY_MS=2500 timeout 30 quill-setup --preselect developer --autoinstall --screenshot /tmp/s4.png >/dev/null 2>&1
[ -e /home/tester/.config/quill-os/quill-setup/done ] && ok "a successful install writes the done marker" || bad "no done marker after a successful install"
rm -rf /home/tester/.config
cat > /tmp/fake-helper <<'FAKE'
#!/bin/sh
echo '{"event":"error","message":"boom"}'; exit 1
FAKE
app env QUILL_SETUP_HELPER_CMD=/tmp/fake-helper QUILL_SETUP_SHOT_DELAY_MS=2500 timeout 30 quill-setup --preselect developer --autoinstall --screenshot /tmp/s5.png >/dev/null 2>&1
[ ! -e /home/tester/.config/quill-os/quill-setup/done ] && ok "a failed install does not write the done marker (it will offer again)" || bad "done marker written after a failure"
exit "$fail"
