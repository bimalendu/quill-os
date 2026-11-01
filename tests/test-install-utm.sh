#!/bin/sh
# Test vm/install-utm.sh with a fake osascript: UTM is never contacted.
# Every scratch file lives in one mktemp directory, removed on exit.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
check() { d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

w=$(mktemp -d) || exit 1
trap 'rm -rf "$w"' EXIT
mkdir "$w/bin" "$w/app" "$w/img" "$w/state"
script=$PWD/vm/install-utm.sh

# a tiny stand-in image with a real checksum file
printf 'not a real disk' > "$w/img/Quill-OS.test.qcow2"
( cd "$w/img" && shasum -a 256 Quill-OS.test.qcow2 > Quill-OS.test.qcow2.sha256 )

# --- fake osascript: records every call, answers from files ---------------------
cat > "$w/bin/osascript" <<'SH'
#!/bin/sh
f=$1; shift
st=$QUILL_T_STATE
txt=$(cat "$f")
case $txt in
  *"repeat with v in virtual machines"*) echo list >> "$st/calls"; cat "$st/vms" ;;
  *"make new virtual machine"*) echo make >> "$st/calls"; cp "$f" "$st/make.applescript"
        printf '%s\n' "$@" > "$st/make.args"
        [ -f "$st/make-fails" ] && exit 1; echo FAKE-ID-1234 ;;
  *"return name of virtual machine id"*) echo name >> "$st/calls"; echo "${FAKE_NAME:-Quill OS}" ;;
  *"status of virtual machine id"*) echo status >> "$st/calls"; echo "${FAKE_STATUS:-stopped}" ;;
  *"start virtual machine id"*) echo "start $*" >> "$st/calls" ;;
  *"delete virtual machine id"*) echo "delete $*" >> "$st/calls"; cp "$f" "$st/delete.applescript" ;;
  *"query ip"*) echo ip >> "$st/calls"; echo "192.168.64.7" ;;
  *"execute virtual machine id"*) echo execute >> "$st/calls"; printf 'NAME="Quill OS"\nVERSION="44"\n' ;;
  *) echo "osascript shim: unknown script" >&2; exit 9 ;;
esac
SH
cat > "$w/bin/uname" <<'SH'
#!/bin/sh
case $1 in -m) echo "${FAKE_ARCH:-arm64}" ;; -s) echo Darwin ;; *) echo Darwin ;; esac
SH
chmod +x "$w/bin/"*

# fresh NAME: a clean state directory; VMs listed: Centos, Windows
# (In sh's POSIX mode VAR=x before a function call persists, so fresh clears every knob.)
fresh() { unset FAKE_STATUS FAKE_NAME FAKE_ARCH QUILL_VM_MEMORY QUILL_VM_CPUS QUILL_VM_MIN_FREE_GB ANSWER T_APP
    rm -rf "$w/state"; mkdir "$w/state"; printf 'Centos\nWindows\n' > "$w/state/vms"; rm -f "$w/id"; }
run() { # ARGS...: run the script with the fakes; output in $w/out, status in $rc
    PATH="$w/bin:$PATH" QUILL_T_STATE="$w/state" QUILL_UTM_APP="${T_APP:-$w/app}" QUILL_VM_IMAGE_DIR="$w/img" \
    QUILL_VM_ID_FILE="$w/id" sh "$script" "$@" > "$w/out" 2>&1 < "${ANSWER:-/dev/null}"; rc=$?; }
calls() { cat "$w/state/calls" 2>/dev/null; }
nocalls() { [ ! -s "$w/state/calls" ]; }
called() { calls | grep -q "$1"; }
didnt() { ! calls | grep -q "$1"; }
yes=$w/yes; echo yes > "$yes"; no=$w/no; echo no > "$no"

echo "== install =="
fresh; run
check "install succeeds (rc=0)" [ "$rc" = 0 ]
check "it asked UTM to make exactly one VM" [ "$(calls | grep -c '^make')" = 1 ]
check "the id UTM returned is saved" [ "$(cat "$w/id")" = FAKE-ID-1234 ]
check "the VM was started by that id" called "start FAKE-ID-1234"
a=$w/state/make.args; m=$w/state/make.applescript
check "name argument is Quill OS" [ "$(sed -n 1p "$a")" = "Quill OS" ]
check "default memory is 4096" [ "$(sed -n 2p "$a")" = 4096 ]
check "default CPUs is 4" [ "$(sed -n 3p "$a")" = 4 ]
check "the image path is the checked qcow2" [ "$(sed -n 4p "$a")" = "$(ls "$w"/img/*.qcow2)" ]
check "notes carry the image sha256" grep -q "Quill OS VM-KDE $(cut -d' ' -f1 "$w"/img/*.sha256)" "$a"
for t in 'architecture:"aarch64"' 'uefi:true' 'hypervisor:true' 'interface:VirtIO' 'mode:shared' 'removable:false' 'virtio-gpu-gl-pci'; do
    check "the script sets $t" grep -qF "$t" "$m"
done
check "the script never names Centos or Windows" sh -c '! grep -qiE "centos|windows" "$1" "$2"' _ "$m" "$script"
check "the other VMs were only listed, never addressed" sh -c '! grep -E "name|status|start|delete" "$1" | grep -qE "Centos|Windows"' _ "$w/state/calls"

fresh; QUILL_VM_MEMORY=6144 QUILL_VM_CPUS=2 run
check "QUILL_VM_MEMORY and QUILL_VM_CPUS are passed through" sh -c '[ "$(sed -n 2p "$1")" = 6144 ] && [ "$(sed -n 3p "$1")" = 2 ]' _ "$w/state/make.args"
fresh; run --no-start
check "--no-start creates the VM but does not start it" sh -c 'grep -q "^make" "$1" && ! grep -q "^start" "$1"' _ "$w/state/calls"
fresh; printf 'Centos\nWindows\nQuill OS 2\n' > "$w/state/vms"; run
check "a VM called 'Quill OS 2' does not block (exact-name match)" [ "$rc" = 0 ]

echo "== install: negatives =="
fresh; printf 'Centos\nWindows\nQuill OS\n' > "$w/state/vms"; run
check "an existing 'Quill OS' makes it refuse" [ "$rc" != 0 ]
check "  ... and it created nothing" didnt '^make'
check "  ... and it saved no id" [ ! -e "$w/id" ]
check "  ... and it says why" grep -q 'already has a VM named' "$w/out"

fresh; cp "$w/img/Quill-OS.test.qcow2" "$w/keep"; printf 'X' | dd of="$w/img/Quill-OS.test.qcow2" bs=1 seek=3 conv=notrunc 2>/dev/null; run
check "a flipped byte in the image makes it refuse" [ "$rc" != 0 ]
check "  ... before UTM is contacted at all" nocalls
check "  ... and it names the checksum" grep -q 'does not match' "$w/out"
cp "$w/keep" "$w/img/Quill-OS.test.qcow2"

fresh; mv "$w/img/Quill-OS.test.qcow2.sha256" "$w/keep.sha"; run
check "a missing .sha256 makes it refuse" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls
mv "$w/keep.sha" "$w/img/Quill-OS.test.qcow2.sha256"

fresh; mv "$w/img/Quill-OS.test.qcow2" "$w/keep"; run
check "a missing qcow2 makes it refuse" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls
mv "$w/keep" "$w/img/Quill-OS.test.qcow2"

fresh; T_APP="$w/nonexistent" run
check "a missing UTM.app makes it refuse" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls
check "  ... and it says where to get UTM" grep -q 'mac.getutm.app' "$w/out"

fresh; FAKE_ARCH=x86_64 run
check "an Intel Mac is refused" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls

fresh; QUILL_VM_MIN_FREE_GB=999999999 run
check "too little free space makes it refuse" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls

for v in abc 512 -1 4096x; do
    fresh; QUILL_VM_MEMORY=$v run
    check "QUILL_VM_MEMORY='$v' is rejected" [ "$rc" != 0 ]
done
fresh; QUILL_VM_MEMORY= run
check "an empty QUILL_VM_MEMORY falls back to 4096" [ "$(sed -n 2p "$w/state/make.args")" = 4096 ]
fresh; QUILL_VM_CPUS=0 run
check "QUILL_VM_CPUS=0 is rejected" [ "$rc" != 0 ]

fresh; echo STALE-ID > "$w/id"; run
check "a stale id file makes it refuse" [ "$rc" != 0 ]
check "  ... and it created nothing" didnt '^make'
check "  ... and it left the file alone" [ "$(cat "$w/id")" = STALE-ID ]

fresh; touch "$w/state/make-fails"; run
check "when UTM fails to make the VM the script fails" [ "$rc" != 0 ]
check "  ... and it saved no id" [ ! -e "$w/id" ]
check "  ... and it started nothing" didnt '^start'

fresh; run --bogus
check "an unknown option is rejected" [ "$rc" != 0 ]
check "  ... before UTM is contacted" nocalls

echo "== status =="
fresh; run status
check "status without a saved id fails" [ "$rc" != 0 ]
check "  ... and contacts nobody" nocalls

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_STATUS=started run status
check "status of a running VM works" [ "$rc" = 0 ]
check "  ... shows the address" grep -q 192.168.64.7 "$w/out"
check "  ... shows NAME from the guest" grep -q 'NAME="Quill OS"' "$w/out"
check "  ... changes nothing (no make/start/delete)" sh -c '! grep -qE "^(make|start|delete)" "$1"' _ "$w/state/calls"

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_STATUS=stopped run status
check "status of a stopped VM does not ask the guest" didnt 'execute'

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_NAME=Windows run status
check "status refuses an id that names another VM" [ "$rc" != 0 ]

echo "== uninstall =="
fresh; ANSWER=$yes run uninstall
check "uninstall without a saved id fails" [ "$rc" != 0 ]
check "  ... and deletes nothing" didnt '^delete'

fresh; echo FAKE-ID-1234 > "$w/id"; ANSWER=$no run uninstall
check "answering 'no' deletes nothing" didnt '^delete'
check "  ... and keeps the id file" [ -s "$w/id" ]

fresh; echo FAKE-ID-1234 > "$w/id"; : > "$w/empty"; ANSWER=$w/empty run uninstall
check "no answer at all deletes nothing" didnt '^delete'

fresh; echo FAKE-ID-1234 > "$w/id"; printf 'y\n' > "$w/y"; ANSWER=$w/y run uninstall
check "answering 'y' (not 'yes') deletes nothing" didnt '^delete'

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_STATUS=started ANSWER=$yes run uninstall
check "a running VM is not deleted" didnt '^delete'
check "  ... and it asks you to shut it down" grep -q 'Shut it down' "$w/out"

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_NAME=Windows ANSWER=$yes run uninstall
check "an id that names another VM is not deleted" didnt '^delete'

fresh; echo FAKE-ID-1234 > "$w/id"; FAKE_STATUS=stopped ANSWER=$yes run uninstall
check "answering 'yes' deletes (rc=0)" [ "$rc" = 0 ]
check "  ... exactly the stored id" [ "$(calls | grep '^delete')" = "delete FAKE-ID-1234" ]
check "  ... and the delete script holds no VM name" sh -c '! grep -qiE "quill|centos|windows" "$1"' _ "$w/state/delete.applescript"
check "  ... and removes the id file" [ ! -e "$w/id" ]

exit "$fail"
