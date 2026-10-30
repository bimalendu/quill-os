#!/bin/sh
# Assert the no-AI policy files in a built image, and validate the Firefox
# policy against the schema inside the image's own Firefox.
# Usage: check-no-ai.sh <root>   (run in the builder container with the image mounted)
root="$1"
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

pol="$root/usr/lib64/firefox/distribution/policies.json"
[ -f "$pol" ] && ok "Firefox policies.json installed" || { bad "Firefox policies.json missing"; exit 1; }
[ -f "$root/usr/share/quill/ai-denylist.txt" ] && ok "denylist copy installed" || bad "denylist copy missing"

python3 - "$root" <<'PY' || fail=1
import json, sys, zipfile
root = sys.argv[1]
policy = json.load(open(root + "/usr/lib64/firefox/distribution/policies.json"))["policies"]
schema = json.loads(zipfile.ZipFile(root + "/usr/lib64/firefox/browser/omni.ja")
                    .read("modules/policies/policies-schema.json"))["properties"]
errors = []
for name, value in policy.items():
    if name not in schema:
        errors.append(f"unknown policy {name}")
        continue
    if name == "AIControls":
        feats = schema["AIControls"]["properties"]
        for feat, cfg in value.items():
            if feat not in feats:
                errors.append(f"AIControls has no feature {feat}")
                continue
            allowed = [o["const"] for o in feats[feat]["properties"]["Value"]["oneOf"]]
            if cfg.get("Value") not in allowed:
                errors.append(f"AIControls.{feat}.Value {cfg.get('Value')!r} not in {allowed}")
            extra = set(cfg) - set(feats[feat]["properties"])
            if extra:
                errors.append(f"AIControls.{feat} unknown keys {sorted(extra)}")
ai = policy.get("AIControls", {}).get("Default", {})
if ai.get("Value") != "blocked":
    errors.append("AIControls.Default.Value must be 'blocked'")
if ai.get("Locked") is not False:
    errors.append("AIControls.Default.Locked must be false (decided: not locked)")
for e in errors:
    print("FAIL  " + e)
if not errors:
    print("ok    policies.json is valid for this Firefox and blocks AI by default, unlocked")
    print("ok    AIControls features in this Firefox: " + ", ".join(schema["AIControls"]["properties"]))
sys.exit(1 if errors else 0)
PY
exit "$fail"
