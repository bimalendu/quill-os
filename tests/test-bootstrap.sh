#!/bin/sh
# Run installer/install.sh in the Linux builder against the real installer folder
# in /out (mounted read-only) and the real pinned Asahi installer, with a fake
# macOS around it. Run via `make test-bootstrap`.
#
# Nothing here touches a system path. Every scratch file lives in one mktemp
# directory, which is removed on exit. The shipped install.sh is not changed:
# the tests run a copy with exactly two lines rewritten (see "the copy under test").
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
sed -e 's:\[ ! -e /System \]:[ ! -e "$QUILL_TEST_ROOT/System" ]:' \
    -e 's:</dev/tty:<"$QUILL_TEST_ANSWER":' installer/install.sh > "$w/install-under-test.sh"
changed=$(diff installer/install.sh "$w/install-under-test.sh" | grep -c '^<')
check "the copy under test differs from install.sh in exactly 2 lines" [ "$changed" = 2 ]
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
[ "$1" = -lint ] && shift
python3 -m json.tool "$1" >/dev/null
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
    out=$(env PATH="$w/bin:$PATH" USER=root QUILL_TEST_ROOT="${ROOT:-$w/root}" \
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
