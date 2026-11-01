#!/bin/sh
# Run installer/install.sh in the Linux builder against the real installer folder
# in /out (mounted read-only) and the real pinned Asahi installer, with a fake
# macOS around it. Run via `make test-bootstrap`.
#
# Nothing here touches a system path. Every scratch file lives in one mktemp
# directory, which is removed on exit. The shipped install.sh is not changed:
# the tests run a copy with exactly three lines rewritten (see "the copy under test").
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
check() { # DESCRIPTION CONDITION-COMMAND...
    d=$1; shift
    if "$@"; then ok "$d"; else bad "$d"; fi
}

src=$(ls -d /out/installer/quill-os-* 2>/dev/null | sort | tail -n 1)
[ -n "$src" ] || { bad "no installer folder in /out/installer (run make installer-pkg)"; exit 1; }
echo "folder: $src"

w=$(mktemp -d) || exit 1
trap 'rm -rf "$w"' EXIT
mkdir "$w/bin" "$w/root" "$w/root/System" "$w/empty-root"

# --- the copy under test -----------------------------------------------------
# 1. the macOS marker /System becomes a path inside $w
# 2. the confirmation prompt reads a file instead of /dev/tty
# 3. the fake macOS tools (sysctl, df, ...) come first on PATH, ahead of the builder's own
sed -e 's:\[ ! -e /System \]:[ ! -e "$QUILL_TEST_ROOT/System" ]:' \
    -e 's|^export PATH="/usr/bin|export PATH="$QUILL_TEST_BIN:/usr/bin|' \
    -e 's:</dev/tty:<"$QUILL_TEST_ANSWER":' installer/install.sh > "$w/install-under-test.sh"
changed=$(diff installer/install.sh "$w/install-under-test.sh" | grep -c '^<')
check "the copy under test differs from install.sh in exactly 3 lines" [ "$changed" = 3 ]
check "install.sh in the folder is the committed one" cmp -s "$src/install.sh" installer/install.sh

# --- a fake macOS toolbox, on PATH for the tests only -------------------------
cat > "$w/bin/caffeinate" <<'SH'
#!/bin/sh
while [ "${1#-}" != "$1" ]; do shift; done
exec "$@"
SH
cat > "$w/bin/shasum" <<'SH'
#!/bin/sh
[ "$1" = -a ] && shift 2
exec sha256sum "$@"
SH
cat > "$w/bin/plutil" <<'SH'
#!/bin/sh
# only the form install.sh uses: plutil -convert xml1 -o /dev/null FILE
[ "$1 $2 $3 $4" = "-convert xml1 -o /dev/null" ] || { echo "plutil shim: unexpected arguments: $*" >&2; exit 2; }
shift 4
python3 -m json.tool "$1" >/dev/null
SH
# Fake macOS tools for --preflight. Each answers from FAKE_* variables.
cat > "$w/bin/sysctl" <<'SH'
#!/bin/sh
[ "$1 $2" = "-n machdep.cpu.brand_string" ] || { echo "sysctl shim: unexpected arguments: $*" >&2; exit 2; }
echo "${FAKE_CHIP:-Apple M1}"
SH
cat > "$w/bin/sw_vers" <<'SH'
#!/bin/sh
[ "$1" = -productVersion ] || exit 2
echo "${FAKE_MACOS-14.5}"
SH
cat > "$w/bin/df" <<'SH'
#!/bin/sh
[ "$1" = -k ] || { echo "df shim: unexpected arguments: $*" >&2; exit 2; }
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "fake 0 0 ${FAKE_FREE_KB:-200000000} 0% /"
SH
cat > "$w/bin/fdesetup" <<'SH'
#!/bin/sh
echo "${FAKE_FV:-FileVault is Off.}"
SH
cat > "$w/bin/pmset" <<'SH'
#!/bin/sh
echo "Now drawing from '${FAKE_POWER:-AC Power}'"
SH
cat > "$w/bin/defaults" <<'SH'
#!/bin/sh
[ "$FAKE_TM" = none ] && exit 1
cat <<'EOT'
{
    Destinations =     (
                {
            SnapshotDates =             (
                "2026-10-15 17:00:00 +0000",
                "2026-10-15 19:04:35 +0000"
            );
        }
    );
}
EOT
SH
chmod +x "$w/bin/"*

ver=$(tr -d '\r\n' < "$src/latest")
yes=$w/yes; echo y > "$yes"
no=$w/no;   echo n > "$no"

# mk NAME: a fresh folder $w/NAME; the big zips are symlinks into the read-only /out
mk() {
    f=$w/$1; mkdir -p "$f/os"
    cp "$w/install-under-test.sh" "$f/install.sh"; chmod +x "$f/install.sh"
    cp "$src/README.txt" "$src/latest" "$src/installer_data.json" "$src/installer-$ver.tar.gz" "$f/"
    for z in "$src"/os/*; do ln -s "$z" "$f/os/$(basename "$z")"; done
}
sums() { # FOLDER (a name under $w, or a full path)
    case $1 in /*) d=$1 ;; *) d=$w/$1 ;; esac
    ( cd "$d" && find -L . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS ); }

# runin FOLDER [ARGS]: run FOLDER/install.sh in the fake macOS; output in $out, status in $rc
asahi_tmp=$w/asahi-install
runin() {
    f=$1; shift
    out=$(env PATH="$w/bin:$PATH" QUILL_TEST_BIN="$w/bin" USER=root QUILL_TEST_ROOT="${ROOT:-$w/root}" \
        QUILL_INSTALL_TMP="$asahi_tmp" QUILL_TEST_ANSWER="${ANSWER:-$yes}" \
        QUILL_STUB_OUT="$w/stub.out" sh "$f/install.sh" "$@" 2>&1); rc=$?
    out=$(printf '%s\n' "$out" | grep -v 'setlocale')   # the builder has no en_US locale
}
says() { printf '%s' "$out" | grep -q -- "$1"; }
rejects() { # DESCRIPTION FOLDER PATTERN: --verify must fail and say PATTERN
    runin "$2" --verify
    if [ "$rc" != 0 ] && says "$3"; then ok "--verify rejects $1"
    else bad "--verify did not reject $1 (rc=$rc): $out"; fi
}

# --- 1. --verify on a good folder, whose name has a space ----------------------
mk "good folder"; sums "$w/good folder"
runin "$w/good folder" --verify
check "--verify passes on a good folder (rc=$rc)" [ "$rc" = 0 ]
check "--verify says nothing was installed" says "Nothing was installed"
check "--verify created no working directory" [ ! -e "$asahi_tmp" ]
runin "$w/good folder" --help
check "--help works and starts nothing" [ "$rc" = 0 ] && [ ! -e "$asahi_tmp" ]
check "--help prints the usage" says "--verify"

# --- 2. --verify rejects damage --------------------------------------------------
mk flipped; sums flipped
zip=$(ls "$src"/os/*minimal*.zip)
rm "$w/flipped/os/$(basename "$zip")"; cp "$zip" "$w/flipped/os/"
printf '\377' | dd of="$w/flipped/os/$(basename "$zip")" bs=1 seek=1000000 conv=notrunc status=none
rejects "a zip with one flipped byte" "$w/flipped" "do not match SHA256SUMS"
rm -f "$w/flipped/os/"*.zip

mk edited-json; sums edited-json
sed -i 's/Quill OS/Quill OZ/' "$w/edited-json/installer_data.json"
rejects "an installer_data.json edited after the checksums were made" "$w/edited-json" "do not match SHA256SUMS"

mk missing-zip; sums missing-zip; rm "$w/missing-zip/os/"*minimal*.zip
rejects "a missing zip (checksums still list it)" "$w/missing-zip" "do not match SHA256SUMS"

mk missing-zip2; rm "$w/missing-zip2/os/"*minimal*.zip; sums missing-zip2
rejects "a missing zip with fresh checksums (JSON still names it)" "$w/missing-zip2" "Missing os/"

mk bad-json; echo '{ not json' > "$w/bad-json/installer_data.json"; sums bad-json
rejects "an installer_data.json that is not valid" "$w/bad-json" "not valid"

mk no-sums
rejects "a folder without SHA256SUMS" "$w/no-sums" "SHA256SUMS is missing"

mk no-tarball; sums no-tarball; rm "$w/no-tarball/installer-$ver.tar.gz"; sums no-tarball
rejects "a folder without the installer tarball" "$w/no-tarball" "Missing installer-$ver.tar.gz"

mk truncated; head -n 60 "$w/install-under-test.sh" > "$w/truncated/install.sh"
runin "$w/truncated" --verify
if [ "$rc" != 0 ] && ! says "Checking the files"; then ok "a truncated install.sh fails to parse and runs nothing"
else bad "a truncated install.sh ran (rc=$rc): $out"; fi

ROOT=$w/empty-root runin "$w/good folder" --verify
if [ "$rc" != 0 ] && says "runs on a Mac"; then ok "--verify refuses to run where there is no /System"
else bad "ran without a macOS marker (rc=$rc): $out"; fi

# --- 2b. --preflight: reads this Mac, writes nothing -------------------------------
rc_says() { [ "$rc" = "$1" ] && says "$2"; }   # exit status is N and the output says PATTERN
lacks() { ! says "$1"; }
runin_env() { # VAR=value...: like runin, with FAKE_* settings for the shims
    out=$(env "$@" PATH="$w/bin:$PATH" QUILL_TEST_BIN="$w/bin" USER=root QUILL_TEST_ROOT="$w/root" \
        QUILL_INSTALL_TMP="$asahi_tmp" QUILL_TEST_ANSWER="$yes" QUILL_STUB_OUT="$w/stub.out" \
        sh "$w/good folder/install.sh" --preflight 2>&1); rc=$?
    out=$(printf '%s\n' "$out" | grep -v 'setlocale')
}
touch "$w/marker"; sleep 1
runin_env FAKE_CHIP="Apple M1"
check "preflight on an M1 with room passes (rc=$rc)" [ "$rc" = 0 ]
check "  ... says READY" says "^READY\. "
check "  ... reports the chip" says "chip: Apple M1"
check "  ... gives the space each system needs" says "Quill OS 44 with KDE Plasma needs 17\.1 GB"
check "  ... gives the space the Minimal system needs" says "Quill OS 44 Minimal needs 8\.7 GB"
check "  ... says nothing was installed or changed" says "Nothing was installed or changed"
check "  ... shows the last backup date" says "last Time Machine backup: 2026-10-15 19:04:35"
check "  ... created no working directory" [ ! -e "$asahi_tmp" ]
check "  ... started no installer" [ ! -e "$w/stub.out" ]
check "  ... wrote nothing into the folder" [ -z "$(find -L "$w/good folder" -newer "$w/marker" 2>/dev/null)" ]

runin_env FAKE_CHIP="Apple M3 Pro"
check "preflight blocks an M3 (rc=$rc)" [ "$rc" = 1 ]
check "  ... says NOT READY" says "NOT READY"
check "  ... points to the VM" says "virtual machine"
runin_env FAKE_CHIP="Apple M2 Max"
check "preflight accepts an M2 family chip" [ "$rc" = 0 ]
runin_env FAKE_CHIP="Intel(R) Core(TM) i7"
check "preflight blocks an Intel Mac" rc_says 1 "needs an Apple Silicon Mac"
runin_env FAKE_MACOS=12.6
check "preflight blocks macOS 12" rc_says 1 "too old"
runin_env FAKE_MACOS=27.0.1
check "preflight only warns about macOS 27 (rc=$rc)" rc_says 0 "WARN.*macOS 27.0.1 is newer"
runin_env FAKE_MACOS=
check "preflight warns when the macOS version is unknown" rc_says 0 "macOS version unknown"

# 12 GB free: the KDE system (17.1 GB) cannot fit, the Minimal one (8.7 GB) can
runin_env FAKE_FREE_KB=11700000
check "with 12 GB free the KDE system is reported as not fitting" says "WARN.*Plasma needs 17\.1 GB; only 12\.0 GB is free, so it cannot be installed"
check "  ... but Minimal fits, so the Mac is not blocked (rc=$rc)" [ "$rc" = 0 ]
check "  ... and it warns that macOS would be left with little" says "WARN.*Minimal needs 8\.7 GB; macOS would be left with only"
runin_env FAKE_FREE_KB=5000000
check "with 5 GB free nothing fits: blocked (rc=$rc)" rc_says 1 "none of the systems offered fits"
runin_env FAKE_FREE_KB=30000000
check "with 30 GB free KDE fits but macOS would keep under 20 GB: warning" says "WARN.*Plasma needs 17\.1 GB; macOS would be left with only 13"
runin_env FAKE_FREE_KB=40000000
check "with 41 GB free there is no space warning" lacks "WARN.*needs"

runin_env FAKE_POWER="Battery Power"
check "preflight warns about battery power (rc=$rc)" rc_says 0 "WARN.*battery"
runin_env FAKE_TM=none
check "preflight warns when no backup is found (rc=$rc)" rc_says 0 "WARN.*no Time Machine backup"
runin_env FAKE_FV="FileVault is On."
check "preflight mentions FileVault without failing" rc_says 0 "FileVault is On"

mk pf-flipped; sums pf-flipped
zip=$(ls "$src"/os/*minimal*.zip)
rm "$w/pf-flipped/os/$(basename "$zip")"; cp "$zip" "$w/pf-flipped/os/"
printf '\377' | dd of="$w/pf-flipped/os/$(basename "$zip")" bs=1 seek=1000000 conv=notrunc status=none
runin "$w/pf-flipped" --preflight
if [ "$rc" != 0 ] && says "do not match SHA256SUMS" && ! says "Checking this Mac"; then ok "--preflight on a damaged folder fails in the checksum step, before reading the Mac"
else bad "--preflight did not stop on a damaged folder (rc=$rc): $out"; fi
rm -f "$w/pf-flipped/os/"*.zip
ROOT=$w/empty-root runin "$w/good folder" --preflight
if [ "$rc" != 0 ] && says "runs on a Mac"; then ok "--preflight refuses to run where there is no /System"
else bad "--preflight ran without a macOS marker (rc=$rc): $out"; fi
runin "$w/good folder" --help
check "--help lists --preflight" says "--preflight"
check "the preflight left no /tmp/asahi-install behind" [ ! -e "$asahi_tmp" ]

# --- 3. the full bootstrap with the real pinned Asahi installer -------------------
# Repack the pinned tarball with its install.sh swapped for a stub. The stub records
# what the bootstrap handed over, then opens both OS packages with the real
# osinstall.load_package().
mkdir "$w/tarx"
tar -C "$w/tarx" -xzf "$src/installer-$ver.tar.gz"
check "the unpacked installer has osinstall.py and main.py" [ -f "$w/tarx/osinstall.py" ] && [ -f "$w/tarx/main.py" ]
cat > "$w/tarx/install.sh" <<'SH'
#!/bin/sh
{
    echo "cwd=$PWD"
    echo "REPO_BASE=$REPO_BASE"
    echo "VERSION_FLAG=$VERSION_FLAG"
    echo "INSTALLER_BASE=$INSTALLER_BASE"
    echo "INSTALLER_DATA=$INSTALLER_DATA"
    echo "REPORT=${REPORT-unset}"
    echo "REPORT_TAG=${REPORT_TAG-unset}"
    echo "DISTRO=$DISTRO"
    echo "args=$*"
} > "$QUILL_STUB_OUT"
exec python3 -I - <<'PY'
import json, os, sys
sys.path.insert(0, os.getcwd())          # -I leaves the cwd off sys.path
try:
    import osinstall
except Exception as e:
    print("IMPORT-FAILED: %r" % (e,)); sys.exit(3)
data = json.load(open("installer_data.json"))
for entry in data["os_list"]:
    o = osinstall.OSInstaller(None, {}, entry)
    o.load_package()
    names = set(o.pkg.namelist())
    need = {"boot.img", "root.img", "esp/m1n1/boot.bin"}
    print("PACKAGE %s %s" % (entry["package"], "has " + " ".join(sorted(need)) if need <= names else "MISSING " + " ".join(sorted(need - names))))
PY
SH
chmod +x "$w/tarx/install.sh"
mk full; rm "$w/full/installer-$ver.tar.gz"
tar -C "$w/tarx" -czf "$w/full/installer-$ver.tar.gz" .
sums full

runin "$w/full"
check "full bootstrap runs to the end (rc=$rc)" [ "$rc" = 0 ]
if says "IMPORT-FAILED"; then bad "osinstall could not be imported on Linux, so load_package was NOT exercised: $out"
else
    for k in kde minimal; do
        says "PACKAGE quill-44-$k-.*has boot.img esp/m1n1/boot.bin root.img" \
            && ok "osinstall.load_package() opens the $k package and finds its images" \
            || bad "load_package did not open the $k package: $out"
    done
fi
says "needs to run as root" && bad "took the sudo branch" || ok "no sudo was needed (USER=root)"
st() { sed -n "s/^$1=//p" "$w/stub.out"; }
check "the installer ran in the working directory" [ "$(st cwd)" = "$asahi_tmp" ]
check "REPO_BASE is the folder's absolute path, space included" [ "$(st REPO_BASE)" = "$w/full" ]
check "VERSION_FLAG is a percent-encoded file:// URL" [ "$(st VERSION_FLAG)" = "file://$w/full/latest" ] || \
    [ "$(st VERSION_FLAG)" = "file://$(printf '%s' "$w/full" | sed 's/ /%20/g')/latest" ]
check "REPORT is unset (no statistics)" [ "$(st REPORT)" = unset ]
check "REPORT_TAG is unset" [ "$(st REPORT_TAG)" = unset ]
check "DISTRO is Quill OS" [ "$(st DISTRO)" = "Quill OS" ]
check "installer_data.json was copied into the working directory" cmp -s "$asahi_tmp/installer_data.json" "$w/full/installer_data.json"

# a second run moves the first working directory aside
runin "$w/full"
check "a second run keeps the previous working directory" [ -n "$(ls -d "$asahi_tmp"-* 2>/dev/null)" ]

# answering no stops before anything is created
rm -rf "$asahi_tmp" "$asahi_tmp"-*
ANSWER=$no runin "$w/full"
if [ "$rc" != 0 ] && says "Cancelled" && [ ! -e "$asahi_tmp" ]; then ok "answering no cancels and creates nothing"
else bad "answering no did not cancel cleanly (rc=$rc): $out"; fi

# negative: with a relative REPO_BASE, load_package cannot find the package
mkdir "$w/rel"
rel=$(cd "$w/rel" && REPO_BASE=. python3 -I - "$w/tarx" "$w/full/installer_data.json" 2>&1 <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import osinstall
entry = json.load(open(sys.argv[2]))["os_list"][0]
osinstall.OSInstaller(None, {}, entry).load_package()
print("OPENED")
PY
)
if printf '%s' "$rel" | grep -q 'FileNotFoundError' && ! printf '%s' "$rel" | grep -q OPENED; then ok "negative: a relative REPO_BASE does not find the package"
else bad "negative: relative REPO_BASE was not rejected: $rel"; fi

# --- 4. nothing outside $w was touched ----------------------------------------------
check "/System does not exist in the builder" [ ! -e /System ]
check "/tmp/asahi-install was not created" [ ! -e /tmp/asahi-install ]
check "no /tmp/asahi-install-* either" [ -z "$(ls -d /tmp/asahi-install-* 2>/dev/null)" ]

exit "$fail"
