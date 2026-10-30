#!/bin/sh
# Test quill-setup-helper as root, with real dnf. Runs in the builder container:
#   expects /c/quill-setup-helper and /c/groups/ (the real groups).
cd /c || exit 1
H=/c/quill-setup-helper
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
# expect <label> <want exit code> <command...>: runs it and compares the exit code.
expect() { label="$1"; want="$2"; shift 2; out=$("$@" 2>&1); rc=$?; [ "$rc" = "$want" ] && ok "$label (exit $rc)" || { bad "$label: exit $rc, want $want"; echo "$out" | tail -3; }; }

# 1. list reads the real groups
n=$($H --groups-dir /c/groups list | wc -l | tr -d ' ')
[ "$n" = 5 ] && ok "list shows 5 groups" || bad "list shows $n groups, want 5"

# 2. dry run builds the right commands and installs nothing
out=$($H --groups-dir /c/groups --dry-run install developer 2>&1); rc=$?
echo "$out" | grep -q '"line": "\$ dnf5 install -y -- git git-lfs' && ok "dry run: dnf5 install with -- before the names" || bad "dry run: dnf command wrong"
echo "$out" | grep -q 'flatpak install --system --noninteractive -y flathub com.vscodium.codium' && ok "dry run: flatpak install command" || bad "dry run: flatpak command wrong"
[ "$rc" = 0 ] && ok "dry run exits 0" || bad "dry run exit $rc"
rpm -q git-lfs >/dev/null 2>&1 && bad "dry run installed something" || ok "dry run installed nothing"

# 3. refusals: nothing may run, exit 2
expect "unknown group is refused"            2 $H --groups-dir /c/groups --dry-run install nope
expect "path-like group id is refused"       2 $H --groups-dir /c/groups --dry-run install ../etc/passwd
expect "option-like group id is refused"     2 $H --groups-dir /c/groups --dry-run install --installroot=/x
expect "group id with shell syntax refused"  2 $H --groups-dir /c/groups --dry-run install 'developer;id'
expect "no groups is refused"                2 $H --groups-dir /c/groups install
expect "unknown option is refused"           2 $H --groups-dir /c/groups --evil install developer

# 4. a tampered group definition is refused before anything runs
mkdir -p /tmp/evil
printf '%s' '{"id":"evil","name":"E","description":"d","order":1,"rpm":["--installroot=/tmp/x"],"flatpak":[]}' > /tmp/evil/evil.json
expect "option-like package in a definition refused" 2 $H --groups-dir /tmp/evil --dry-run install evil
printf '%s' '{"id":"evil","name":"E","description":"d","order":1,"rpm":["git"],"flatpak":["x; reboot"]}' > /tmp/evil/evil.json
expect "shell syntax in a flatpak id refused"        2 $H --groups-dir /tmp/evil --dry-run install evil

# 5. a failing transaction exits 1 with an error event
mkdir -p /tmp/broken
printf '%s' '{"id":"broken","name":"B","description":"d","order":1,"rpm":["no-such-package-quill-xyz"],"flatpak":[]}' > /tmp/broken/broken.json
out=$($H --groups-dir /tmp/broken install broken 2>&1); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '"event": "error"' && ok "failed dnf transaction exits 1 with an error event" || { bad "failed dnf: exit $rc"; echo "$out" | tail -3; }

# 6. the flatpak step calls flatpak correctly (mock flatpak, since real installs are hundreds of MB)
mv /usr/bin/flatpak /usr/bin/flatpak.real
printf '#!/bin/sh\necho "$@" >> /tmp/flatpak-calls\nexit 0\n' > /usr/bin/flatpak; chmod +x /usr/bin/flatpak
mkdir -p /tmp/fp; rm -f /tmp/flatpak-calls
printf '%s' '{"id":"fp","name":"F","description":"d","order":1,"rpm":[],"flatpak":["com.vscodium.codium"]}' > /tmp/fp/fp.json
$H --groups-dir /tmp/fp install fp >/dev/null 2>&1; rc=$?
mv /usr/bin/flatpak.real /usr/bin/flatpak
[ "$rc" = 0 ] && grep -q 'remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' /tmp/flatpak-calls \
    && grep -q 'install --system --noninteractive -y flathub com.vscodium.codium' /tmp/flatpak-calls \
    && ok "flatpak step adds Flathub then installs the app" || { bad "flatpak step: exit $rc"; cat /tmp/flatpak-calls; }

# 7. a REAL install of a small group
mkdir -p /tmp/real
printf '%s' '{"id":"real","name":"R","description":"d","order":1,"rpm":["tree","figlet"],"flatpak":[]}' > /tmp/real/real.json
rpm -q tree figlet >/dev/null 2>&1 && dnf5 -y -q remove tree figlet >/dev/null 2>&1
out=$($H --groups-dir /tmp/real install real 2>&1); rc=$?
if [ "$rc" = 0 ] && rpm -q tree figlet >/dev/null 2>&1 && echo "$out" | tail -1 | grep -q '"event": "done"'; then
    ok "real install: tree and figlet installed, last event is done"
else
    bad "real install failed (exit $rc)"; echo "$out" | tail -5
fi
exit "$fail"
