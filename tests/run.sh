#!/bin/sh
# Repository checks that need no container. Run via `make test`.
cd "$(dirname "$0")/.." || exit 1
fail=0

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

for d in build kiwi packages installer policy ci tests docs; do
    [ -d "$d" ] && ok "dir $d/" || bad "missing dir $d/"
done

for f in README.md LICENSE Makefile build/Containerfile build/build-rpms.sh tests/doctor.sh tests/check-packages.sh tests/check-branding.sh tests/check-denylist.sh tests/test-denylist.sh tests/check-no-ai.sh policy/ai-denylist.txt .gitignore; do
    [ -f "$f" ] && ok "file $f" || bad "missing file $f"
done

for s in tests/*.sh; do
    sh -n "$s" && ok "syntax $s" || bad "syntax $s"
done

for x in $(find kiwi -name '*.xml'); do
    xmllint --noout "$x" 2>/dev/null && ok "xml $x" || bad "xml $x is not well-formed"
done

sh tests/test-denylist.sh >/dev/null && ok "denylist self-test" || bad "denylist self-test"

python3 tests/check-groups.py >/dev/null && ok "setup groups are well formed" || bad "setup groups are malformed"
sh tests/test-groups.sh >/dev/null && ok "groups self-test" || bad "groups self-test"

make -n help >/dev/null 2>&1 && ok "Makefile parses" || bad "Makefile does not parse"

exit "$fail"
