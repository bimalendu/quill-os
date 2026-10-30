#!/usr/bin/env python3
"""Validate the Quill Setup package group definitions (packages/quill-setup/src/groups/*.json).

Structure only, and the AI denylist. Whether the packages exist is checked
against the live repositories by `make check-group-packages`.

Usage: check-groups.py [groups-dir]   (default packages/quill-setup/src/groups)
Prints the group contents as '--rpms' / '--flatpaks' input files when given
--dump DIR, so check-denylist.sh can scan them.
"""
import json
import re
import sys
from pathlib import Path

args = sys.argv[1:]
dump = None
if "--dump" in args:
    i = args.index("--dump")
    dump = Path(args[i + 1])
    del args[i:i + 2]
root = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "packages/quill-setup/src/groups"

errors = []
ids, orders, rpms, flatpaks = set(), set(), [], []
RPM_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
FLATPAK_ID = re.compile(r"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$")

files = sorted(root.glob("*.json"))
if not files:
    errors.append(f"no group files in {root}")
for f in files:
    try:
        g = json.loads(f.read_text())
    except ValueError as e:
        errors.append(f"{f.name}: invalid JSON: {e}")
        continue
    def err(msg):
        errors.append(f"{f.name}: {msg}")
    for key, typ in (("id", str), ("name", str), ("description", str), ("order", int), ("rpm", list), ("flatpak", list)):
        if not isinstance(g.get(key), typ):
            err(f"'{key}' missing or not a {typ.__name__}")
    extra = set(g) - {"id", "name", "description", "order", "rpm", "flatpak"}
    if extra:
        err(f"unknown keys {sorted(extra)}")
    gid = g.get("id", "")
    if not re.fullmatch(r"[a-z][a-z0-9-]*", str(gid)):
        err(f"id {gid!r} must be lowercase letters, digits and dashes")
    if gid != f.stem:
        err(f"id {gid!r} must match the file name {f.stem!r}")
    if gid in ids:
        err(f"duplicate id {gid!r}")
    ids.add(gid)
    if g.get("order") in orders:
        err(f"duplicate order {g.get('order')}")
    orders.add(g.get("order"))
    if not (g.get("rpm") or g.get("flatpak")):
        err("group installs nothing")
    for p in g.get("rpm", []):
        if not isinstance(p, str) or not RPM_NAME.match(p):
            err(f"bad rpm name {p!r}")
        elif p in rpms:
            err(f"rpm {p!r} is in more than one group")
        rpms.append(p)
    if len(set(g.get("rpm", []))) != len(g.get("rpm", [])):
        err("duplicate rpm entries")
    for a in g.get("flatpak", []):
        if not isinstance(a, str) or not FLATPAK_ID.match(a):
            err(f"bad flatpak id {a!r}")
        flatpaks.append(a)
    if len(g.get("description", "")) > 400:
        err("description is longer than 400 characters")

if dump is not None:
    dump.mkdir(parents=True, exist_ok=True)
    (dump / "rpms").write_text("".join(f"{p}|||\n" for p in rpms))
    (dump / "flatpaks").write_text("".join(f"{a}\n" for a in flatpaks))

for e in errors:
    print("FAIL  " + e)
if not errors:
    print(f"ok    {len(files)} groups, {len(rpms)} rpms, {len(flatpaks)} flatpaks are well formed")
sys.exit(1 if errors else 0)
