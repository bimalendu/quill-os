#!/bin/sh
# Self-test for check-denylist.sh: it must pass clean input and fail bad input.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
D=policy/ai-denylist.txt
C=tests/check-denylist.sh

# Clean list, including names that merely look similar (Haskell's copilot DSL, goose-like names).
printf '%s\n' 'firefox|1|1|x' 'okular|1|1|x' 'tesseract-libs|1|1|x' 'ghc-copilot-core|1|1|x' 'llamaindex-unrelated-name|1|1|x' > "$t/clean"
sh $C $D --rpms "$t/clean" >/dev/null 2>&1 && ok "clean package list passes" || bad "clean package list should pass"

# Exact name, glob, and prospective entries must each trip the gate.
for name in ollama llama-cpp-devel python3-llama-cpp-python kaichat goose gpt4all-chat; do
    printf '%s\n' 'firefox|1|1|x' "$name|1|1|x" > "$t/bad"
    sh $C $D --rpms "$t/bad" >/dev/null 2>&1 && bad "$name should be denied" || ok "$name is denied"
done

# Flatpaks.
printf '%s\n' org.mozilla.firefox org.kde.okular > "$t/fp-clean"
sh $C $D --flatpaks "$t/fp-clean" >/dev/null 2>&1 && ok "clean flatpak list passes" || bad "clean flatpak list should pass"
printf '%s\n' org.kde.okular com.jeffser.Alpaca > "$t/fp-bad"
sh $C $D --flatpaks "$t/fp-bad" >/dev/null 2>&1 && bad "Alpaca flatpak should be denied" || ok "Alpaca flatpak is denied"

# No input is an error, not a pass.
sh $C $D >/dev/null 2>&1; [ $? = 2 ] && ok "no input is an error" || bad "no input should exit 2"

exit "$fail"
