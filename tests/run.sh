#!/bin/sh
# Repository checks that need no container. Run via `make test`.
cd "$(dirname "$0")/.." || exit 1
fail=0

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

for d in build kiwi packages installer policy ci tests docs; do
    [ -d "$d" ] && ok "dir $d/" || bad "missing dir $d/"
done

for f in README.md LICENSE Makefile build/Containerfile tests/doctor.sh .gitignore; do
    [ -f "$f" ] && ok "file $f" || bad "missing file $f"
done

for s in tests/*.sh; do
    sh -n "$s" && ok "syntax $s" || bad "syntax $s"
done

make -n help >/dev/null 2>&1 && ok "Makefile parses" || bad "Makefile does not parse"

exit "$fail"
