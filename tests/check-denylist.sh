#!/bin/sh
# Fail if a built image or package group contains something on the AI denylist.
#
# Usage: check-denylist.sh <denylist> [--rpms <kiwi .packages file>] [--flatpaks <file of IDs>]
# --rpms reads the first field (before '|') of each line as the package name;
# --flatpaks reads one application ID per line. Both may be given.
set -u
deny="$1"; shift
rpms=""; flatpaks=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rpms) rpms="$2"; shift 2 ;;
        --flatpaks) flatpaks="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -r "$deny" ] || { echo "cannot read denylist: $deny" >&2; exit 2; }
[ -n "$rpms$flatpaks" ] || { echo "nothing to check" >&2; exit 2; }

fail=0
# entries <kind>: print the patterns for one kind, comments and spaces removed.
entries() {
    sed -n "s/^$1:[[:space:]]*//p" "$deny" | sed 's/[[:space:]]*#.*//' | sed '/^$/d'
}
# scan <kind> <names file>: report every name that matches a pattern.
scan() {
    kind="$1"; names="$2"
    entries "$kind" | while read -r pattern; do
        while read -r name; do
            # shellcheck disable=SC2254  # the glob in $pattern is intended
            case "$name" in $pattern) printf 'FAIL  denylisted %s: %s (matches "%s")\n' "$kind" "$name" "$pattern" ;; esac
        done < "$names"
    done
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
if [ -n "$rpms" ]; then
    cut -d'|' -f1 "$rpms" > "$tmp"
    scan rpm "$tmp" > "$tmp.out"; cat "$tmp.out"; [ -s "$tmp.out" ] && fail=1; rm -f "$tmp.out"
    printf 'checked %s rpm names against %s rpm entries\n' "$(wc -l < "$tmp" | tr -d ' ')" "$(entries rpm | wc -l | tr -d ' ')"
fi
if [ -n "$flatpaks" ]; then
    scan flatpak "$flatpaks" > "$tmp.out"; cat "$tmp.out"; [ -s "$tmp.out" ] && fail=1; rm -f "$tmp.out"
    printf 'checked %s flatpak ids against %s flatpak entries\n' "$(wc -l < "$flatpaks" | tr -d ' ')" "$(entries flatpak | wc -l | tr -d ' ')"
fi
[ "$fail" = 0 ] && echo "ok    no denylisted packages"
exit "$fail"
