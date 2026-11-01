#!/usr/bin/env python3
"""Check an installer folder's installer_data.json against the files beside it.

    check-installer.py FOLDER [JSON]     JSON defaults to FOLDER/installer_data.json

Prints one 'ok' or 'FAIL' line per check; exits 1 if any failed. Run with -I."""
import json
import os
import struct
import sys
import zipfile

folder = sys.argv[1]
jpath = sys.argv[2] if len(sys.argv) > 2 else os.path.join(folder, "installer_data.json")
failed = 0


def check(cond, msg, detail=""):
    global failed
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failed = 1
        if detail:
            print("      " + detail)


try:
    data = json.load(open(jpath))
except Exception as e:  # noqa: BLE001
    check(False, "installer_data.json parses", str(e))
    sys.exit(1)
check(True, "installer_data.json parses")

oses = data.get("os_list", [])
check(len(oses) == 2, "two OS entries", "found %d" % len(oses))
names = [o.get("name", "") for o in oses]
check(any("KDE" in n for n in names) and any("Minimal" in n for n in names),
      "entries are KDE and Minimal", str(names))
check(all(n.startswith("Quill OS") for n in names), "entry names start with Quill OS", str(names))

REQUIRED = ["name", "default_os_name", "boot_object", "next_object", "package", "icon",
            "supported_fw", "extras", "partitions"]
fw = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "installer", "supported_fw.json")))

for o in oses:
    n = o.get("name", "?")
    missing = [k for k in REQUIRED if k not in o]
    check(not missing, "%s: has every key" % n, "missing %s" % missing)
    check(o.get("default_os_name") == "Quill OS", "%s: default_os_name is Quill OS" % n)
    check(o.get("boot_object") == "m1n1.bin" and o.get("next_object") == "m1n1/boot.bin",
          "%s: m1n1 boot objects" % n)
    check(o.get("supported_fw") == fw, "%s: supported_fw matches installer/supported_fw.json" % n)
    if "KDE" in n:
        ex = o.get("extras")
        check(isinstance(ex, list) and len(ex) == 2 and all(u.startswith("https://codecs.fedoraproject.org/") for u in ex),
              "%s: openh264 extras" % n, str(ex))

    parts = {p.get("name"): p for p in o.get("partitions", [])}
    check(list(parts) == ["EFI", "Boot", "Root"], "%s: partitions EFI, Boot, Root" % n, str(list(parts)))
    esp, boot, root = parts.get("EFI", {}), parts.get("Boot", {}), parts.get("Root", {})
    check(esp.get("format") == "fat" and esp.get("source") == "esp" and esp.get("copy_firmware") is True
          and esp.get("copy_installer_data") is True, "%s: ESP is FAT from esp/ and gets firmware" % n)
    check(str(esp.get("volume_id", "")).startswith("0x"), "%s: ESP volume_id looks like 0x...." % n, str(esp.get("volume_id")))
    check(boot.get("image") == "boot.img" and root.get("image") == "root.img" and root.get("expand") is True,
          "%s: boot.img, root.img, root expands" % n)

    zpath = os.path.join(folder, "os", str(o.get("package")))
    if not os.path.isfile(zpath):
        check(False, "%s: package exists" % n, zpath)
        continue
    check(True, "%s: package exists" % n)
    z = zipfile.ZipFile(zpath)
    names_in = set(z.namelist())
    for need in ["boot.img", "root.img", "quill.icns", "esp/m1n1/boot.bin", "esp/EFI/fedora/grub.cfg",
                 "esp/EFI/fedora/shimaa64.efi", "esp/EFI/BOOT/BOOTAA64.EFI"]:
        check(need in names_in, "%s: zip has %s" % (n, need))
    for gone in ["esp/EFI/BOOT/grubaa64.efi", "esp/EFI/BOOT/grub.cfg"]:
        check(gone not in names_in, "%s: zip has no %s" % (n, gone))
    if "esp/EFI/fedora/grub.cfg" in names_in:
        cfg = z.read("esp/EFI/fedora/grub.cfg").decode()
        has_source = any(l.lstrip().startswith("source ") for l in cfg.splitlines())
        check(not has_source and "configfile " in cfg, "%s: grub.cfg uses configfile, not source" % n)
    for key, member in (("size", None),):
        pass
    for p, member in ((boot, "boot.img"), (root, "root.img")):
        if member in names_in:
            want = int(str(p.get("size", "0B")).rstrip("B"))
            check(z.getinfo(member).file_size == want, "%s: %s size in JSON equals the zip member" % (n, member),
                  "json %s, zip %d" % (want, z.getinfo(member).file_size))
    if "quill.icns" in names_in:
        b = z.read("quill.icns")
        ok = b[:4] == b"icns" and struct.unpack(">I", b[4:8])[0] == len(b)
        types, i = [], 8
        while ok and i < len(b):
            t, ln = b[i:i + 4], struct.unpack(">I", b[i + 4:i + 8])[0]
            ok = ln >= 8 and b[i + 8:i + 16] == b"\x89PNG\r\n\x1a\n"
            types.append(t.decode()); i += ln
        check(ok and types == ["ic07", "ic08", "ic09", "ic10"], "%s: quill.icns is a valid ICNS" % n, str(types))

sys.exit(failed)
