#!/usr/bin/env python3
"""Ask a running Firefox (Marionette) which AI settings are in effect, and assert
that Quill's policy took effect. Used by `make check-firefox`, which starts the
image's Firefox in a chroot and runs this against it. Exits 1 on any mismatch."""
import json, socket, sys, time

def connect(port=2828, tries=60):
    for _ in range(tries):
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=5)
            return s
        except OSError:
            time.sleep(1)
    sys.exit("marionette never came up")

def read_msg(s):
    buf = b""
    while b":" not in buf:
        buf += s.recv(1)
    n = int(buf.split(b":")[0])
    data = b""
    while len(data) < n:
        data += s.recv(n - len(data))
    return json.loads(data)

n = 0
def call(s, name, params=None):
    global n
    n += 1
    body = json.dumps([0, n, name, params or {}]).encode()
    s.sendall(str(len(body)).encode() + b":" + body)
    while True:
        m = read_msg(s)
        if isinstance(m, list) and m[0] == 1 and m[1] == n:
            if m[2]:
                raise RuntimeError(m[2])
            return m[3]

s = connect()
read_msg(s)  # hello
call(s, "WebDriver:NewSession", {"capabilities": {}})
call(s, "Marionette:SetContext", {"value": "chrome"})
script = """
const out = {};
const names = ["browser.ai.control.default","browser.ai.control.sidebarChatbot","browser.ai.control.linkPreviewKeyPoints",
  "browser.ai.control.smartTabGroups","browser.ai.control.translations","browser.ai.control.pdfjsAltText",
  "browser.ai.control.smartWindow","browser.ai.control.speechRecognition",
  "browser.ml.chat.enabled","browser.ml.linkPreview.enabled","browser.tabs.groups.smart.userEnabled",
  "browser.translations.enable","pdfjs.enableAltText"];
for (const n of names) {
  const t = Services.prefs.getPrefType(n);
  out[n] = t == 0 ? "(unset)" : t == 32 ? Services.prefs.getStringPref(n)
         : t == 128 ? Services.prefs.getBoolPref(n) : Services.prefs.getIntPref(n);
  out[n + " [locked]"] = Services.prefs.prefIsLocked(n);
}
const p = Services.policies;
out["policies.status"] = p.status;
out["activePolicies"] = JSON.stringify(p.getActivePolicies());
return out;
"""
res = call(s, "WebDriver:ExecuteScript", {"script": script, "args": []})
val = res.get("value", res)
bad = []
for k, v in val.items():
    print(f"{k} = {v}")
    if k.startswith("browser.ai.control.") and not k.endswith("[locked]") and v != "blocked":
        bad.append(f"{k} is {v!r}, want 'blocked'")
    if k in ("browser.ml.chat.enabled", "browser.ml.linkPreview.enabled",
             "browser.tabs.groups.smart.userEnabled", "browser.translations.enable",
             "pdfjs.enableAltText") and v is not False:
        bad.append(f"{k} is {v!r}, want False")
    if k.endswith("[locked]") and v:
        bad.append(f"{k[:-9]} is locked (policy is deliberately unlocked)")
if val.get("policies.status") != 1:
    bad.append("policy engine is not active (policies.status != 1)")
for b in bad:
    print("FAIL  " + b)
if not bad:
    print("ok    Firefox applied the Quill no-AI policy: all AI features blocked, none locked")
sys.exit(1 if bad else 0)
