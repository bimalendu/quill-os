#!/bin/sh
# Self-test for check-groups.py: good input passes, each kind of bad input fails.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

good='{"id":"a","name":"A","description":"d","order":1,"rpm":["git"],"flatpak":[]}'
mk() { rm -rf "$t/g"; mkdir -p "$t/g"; printf '%s' "$2" > "$t/g/$1.json"; }
expect_fail() { # <label> <file stem> <json>
    mk "$2" "$3"
    python3 tests/check-groups.py "$t/g" >/dev/null 2>&1 && bad "$1 should fail" || ok "$1 is rejected"
}

mk a "$good"; python3 tests/check-groups.py "$t/g" >/dev/null 2>&1 && ok "good group passes" || bad "good group should pass"
expect_fail "invalid JSON"          a '{"id":'
expect_fail "id not matching file"  b "$good"
expect_fail "uppercase id"          A '{"id":"A","name":"A","description":"d","order":1,"rpm":["git"],"flatpak":[]}'
expect_fail "empty group"           a '{"id":"a","name":"A","description":"d","order":1,"rpm":[],"flatpak":[]}'
expect_fail "missing key"           a '{"id":"a","name":"A","order":1,"rpm":["git"],"flatpak":[]}'
expect_fail "unknown key"           a '{"id":"a","name":"A","description":"d","order":1,"rpm":["git"],"flatpak":[],"cmd":"rm -rf /"}'
expect_fail "shell syntax in rpm"   a '{"id":"a","name":"A","description":"d","order":1,"rpm":["git; reboot"],"flatpak":[]}'
expect_fail "option-like rpm"       a '{"id":"a","name":"A","description":"d","order":1,"rpm":["--installroot=/x"],"flatpak":[]}'
expect_fail "bad flatpak id"        a '{"id":"a","name":"A","description":"d","order":1,"rpm":["git"],"flatpak":["not an id"]}'
expect_fail "duplicate rpm"         a '{"id":"a","name":"A","description":"d","order":1,"rpm":["git","git"],"flatpak":[]}'

# A group containing a denylisted package must trip the denylist gate.
mk a '{"id":"a","name":"A","description":"d","order":1,"rpm":["ollama"],"flatpak":["com.jeffser.Alpaca"]}'
python3 tests/check-groups.py "$t/g" --dump "$t/d" >/dev/null 2>&1
sh tests/check-denylist.sh policy/ai-denylist.txt --rpms "$t/d/rpms" --flatpaks "$t/d/flatpaks" >/dev/null 2>&1 \
    && bad "a group with ollama and Alpaca should trip the denylist" || ok "a group with a denylisted package trips the denylist"
exit "$fail"
