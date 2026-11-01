#!/bin/sh
# Check the newest installer folder in /out/installer (mounted read-only) against
# the raw images it was built from. Run via `make check-installer`.
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

dir=$(ls -d /out/installer/quill-os-* 2>/dev/null | sort | tail -n 1)
[ -n "$dir" ] || { bad "no installer folder in /out/installer (run make installer-pkg)"; exit 1; }
echo "folder: $dir"

# 1. JSON and zip structure
python3 -I tests/check-installer.py "$dir" || fail=1

# 2. The pinned installer and the checksums
ver=$(sed -n 's/^version=//p' installer/installer.lock)
want=$(sed -n 's/^sha256=//p' installer/installer.lock)
got=$(sha256sum "$dir/installer-$ver.tar.gz" 2>/dev/null | awk '{print $1}')
[ -n "$got" ] && [ "$got" = "$want" ] && ok "installer-$ver.tar.gz matches installer.lock" || bad "installer tarball does not match installer.lock"
[ "$(tr -d '\r\n' < "$dir/latest")" = "$ver" ] && ok "latest names the pinned version" || bad "latest does not name $ver"
( cd "$dir" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) && ok "SHA256SUMS verifies every file" || bad "SHA256SUMS does not verify"
for f in install.sh README.txt installer_data.json latest; do
    grep -q " \./$f\$" "$dir/SHA256SUMS" && ok "SHA256SUMS lists $f" || bad "SHA256SUMS does not list $f"
done
[ -x "$dir/install.sh" ] && ok "install.sh is executable" || bad "install.sh is not executable"
cmp -s "$dir/install.sh" installer/install.sh && ok "install.sh is the committed one" || bad "install.sh differs from installer/install.sh"

# 3. The zipped images are byte-identical to the raw images' partitions
sha_part() { # IMAGE N -> sha256 of partition N
    fdisk -Lnever -lu -b 4096 "$1" | awk -v img="$1" -v n="$2" '$1 == img n { print $2, $4 }' | {
        read -r start count
        dd if="$1" skip="$start" count="$count" bs=4096 status=none | sha256sum | awk '{print $1}'; }
}
serial_part1() {
    fdisk -Lnever -lu -b 4096 "$1" | awk -v img="$1" '$1 == img "1" { print $2, $4 }' | {
        read -r start count
        dd if="$1" skip="$start" count="$count" bs=4096 status=none | file - | awk -v 'RS=,' '/serial number/ { print $3 }'; }
}
for pair in kde:Workstation-KDE minimal:Minimal; do
    key=${pair%%:*} prof=${pair#*:}
    raw=$(ls /out/$prof/*.raw)
    zip=$(ls "$dir"/os/quill-*-"$key"-*.zip 2>/dev/null)
    [ -n "$zip" ] || { bad "$key: no package zip"; continue; }
    for pn in "2 boot.img" "3 root.img"; do
        set -- $pn
        a=$(sha_part "$raw" "$1"); b=$(unzip -p "$zip" "$2" | sha256sum | awk '{print $1}')
        [ -n "$a" ] && [ "$a" = "$b" ] && ok "$key: $2 is byte-identical to partition $1 of the raw image" || bad "$key: $2 differs from partition $1"
    done
    s=$(serial_part1 "$raw")
    grep -q "\"volume_id\": \"$s\"" "$dir/installer_data.json" && ok "$key: volume_id $s matches the ESP" || bad "$key: volume_id does not match the ESP ($s)"
    unzip -p "$zip" boot.img | head -c 4194304 | file - | grep -q 'ext[234] filesystem' && ok "$key: boot.img is ext4" || bad "$key: boot.img is not ext"
    unzip -p "$zip" root.img | head -c 4194304 | file - | grep -qi 'btrfs' && ok "$key: root.img is btrfs" || bad "$key: root.img is not btrfs"
done

# 4. Negative checks: the checker must reject damage
t=$(mktemp -d)
python3 -I - "$dir/installer_data.json" "$t" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["os_list"][0]["partitions"][2]["size"] = "1B"           # wrong size
json.dump(d, open(sys.argv[2] + "/wrong-size.json", "w"))
d = json.load(open(sys.argv[1])); del d["os_list"][1]["icon"]   # missing key
json.dump(d, open(sys.argv[2] + "/no-icon.json", "w"))
d = json.load(open(sys.argv[1])); d["os_list"].pop()        # one entry only
json.dump(d, open(sys.argv[2] + "/one-entry.json", "w"))
PY
for n in wrong-size no-icon one-entry; do
    python3 -I tests/check-installer.py "$dir" "$t/$n.json" >/dev/null && bad "negative: $n.json was accepted" || ok "negative: $n.json is rejected"
done
printf 'x' > "$t/garbled.json"; python3 -I tests/check-installer.py "$dir" "$t/garbled.json" >/dev/null && bad "negative: unparseable JSON accepted" || ok "negative: unparseable JSON is rejected"

# A lock that names a different hash must stop the build before anything is written.
# assemble.sh runs against scratch copies of the lock and the output dir.
mkdir -p "$t/out/.cache"
cp "/out/installer/.cache/installer-$ver.tar.gz" "$t/out/.cache/" 2>/dev/null
sed 's/^sha256=.*/sha256=0000000000000000000000000000000000000000000000000000000000000000/' installer/installer.lock > "$t/bad.lock"
msg=$(QUILL_LOCK="$t/bad.lock" QUILL_INSTALLER_OUT="$t/out" sh installer/assemble.sh build 20990101 2>&1) && bad "negative: a lock with the wrong sha256 was accepted" \
    || { echo "$msg" | grep -q 'pins 0000' && ok "negative: a lock with the wrong sha256 stops the build" || bad "negative: wrong lock failed for another reason: $msg"; }
[ -z "$(ls -d "$t"/out/quill-os-* 2>/dev/null)" ] && ok "negative: the refused build created no folder" || bad "negative: a folder was created despite the wrong lock"
rm -rf "$t"

exit "$fail"
