#!/bin/sh
# Build the Quill Setup app and take offscreen screenshots of its states.
# Runs in the builder container: expects /w/src (the app sources) and writes
# PNGs to /shots. Offscreen, software-rendered; the look is close to Plasma's
# but not identical (no KWin, default fonts).
set -e
# The app's icon comes from quill-logos; install it from the local repo when it is mounted.
if [ -f /repo/repodata/repomd.xml ]; then
    rpm --import /repo/RPM-GPG-KEY-quill-dev
    dnf5 -y -q install --repofrompath=quill,/repo --setopt=quill.gpgcheck=0 --setopt=quill.pkg_gpgcheck=1 \
        --setopt=quill.gpgkey=file:///repo/RPM-GPG-KEY-quill-dev quill-logos >/dev/null 2>&1 \
        && echo "installed quill-logos for the icon" >&2
fi
cd /w/src
cmake -S . -B /tmp/b -DCMAKE_BUILD_TYPE=Release >/tmp/cmake.log 2>&1 || { tail -20 /tmp/cmake.log; exit 1; }
cmake --build /tmp/b -j4 2>&1 | grep -E "error|warning" && exit 1
mkdir -p /shots

export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=${STYLE:-org.kde.desktop}
export QUILL_SETUP_GROUPS=/w/src/groups HOME=/tmp/home XDG_CONFIG_HOME=/tmp/home/.config
rm -rf /tmp/home; mkdir -p /tmp/home

# A fake helper that speaks the same JSON-lines protocol.
cat > /tmp/fake-helper <<'FAKE'
#!/bin/sh
mode="$FAKE_MODE"
echo '{"event":"start","groups":["x"],"rpms":3,"flatpaks":1}'
echo '{"event":"step","name":"Installing packages","fraction":0.4}'
echo '{"event":"log","line":"$ dnf5 install -y -- git gcc clang"}'
echo '{"event":"log","line":"Installing git-2.50.0 ..."}'
case "$mode" in
  busy) sleep 30 ;;
  fail) echo '{"event":"error","message":"dnf failed to install the selected packages"}'; exit 1 ;;
  *)    echo '{"event":"done","fraction":1.0}'; exit 0 ;;
esac
FAKE
chmod +x /tmp/fake-helper
export QUILL_SETUP_HELPER_CMD=/tmp/fake-helper

shot() { # <name> <extra args...>
    name=$1; shift
    /tmp/b/quill-setup --screenshot /shots/$name.png "$@" 2>/tmp/$name.err; rc=$?
    echo "$name: exit=$rc  qml-warnings=$(grep -ciE 'qml|warning|error|unable' /tmp/$name.err)"
    grep -iE "qml|warning|error|unable" /tmp/$name.err | head -5
}
shot 1-nothing-selected
shot 2-some-selected --preselect developer,media
FAKE_MODE=busy QUILL_SETUP_SHOT_DELAY_MS=2000 shot 3-installing --preselect developer --autoinstall
FAKE_MODE=ok   QUILL_SETUP_SHOT_DELAY_MS=2000 shot 4-done --preselect developer --autoinstall
rm -rf /tmp/home/.config; FAKE_MODE=fail QUILL_SETUP_SHOT_DELAY_MS=2000 shot 5-failed --preselect developer --autoinstall
echo "done marker after success: $(ls /tmp/home/.config/quill-os/quill-setup/ 2>/dev/null | tr '\n' ' ')"
