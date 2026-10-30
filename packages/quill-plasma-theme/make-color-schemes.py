#!/usr/bin/env python3
"""Derive the Quill colour schemes from KDE's Breeze schemes.

Usage: make-color-schemes.py BreezeLight.colors BreezeDark.colors

Writes QuillLight.colors and QuillDark.colors next to this script. Only the
accent colours change (Breeze blue -> Quill indigo #4B4ACF); the translated
Name[...] lines are dropped. The outputs are committed, so building the RPM
does not depend on Breeze's files.
"""
import re
import sys
from pathlib import Path

INDIGO = "75,74,207"          # #4B4ACF, the Quill accent
INDIGO_DEEP = "59,58,176"     # links on light backgrounds
INDIGO_LIGHT = "120,119,240"  # focus/hover on dark backgrounds
INDIGO_TEXT = "150,149,255"   # active text and links on dark backgrounds
SEL_ALT_DARK = "50,50,150"

BREEZE_BLUE = "61,174,233"
BREEZE_LINK_LIGHT = "41,128,185"
BREEZE_LINK_DARK = "29,153,243"
BREEZE_SEL_ALT = "30,87,116"


def derive(src: Path, dark: bool) -> str:
    out, section = [], ""
    for line in src.read_text().splitlines():
        m = re.match(r"\[(.*)\]", line)
        if m:
            section = line
        if re.match(r"Name\[", line):
            continue
        key, _, val = line.partition("=")
        if key == "Name":
            line = f"Name=Quill {'Dark' if dark else 'Light'}"
        elif key == "ColorScheme":
            line = f"ColorScheme=Quill{'Dark' if dark else 'Light'}"
        elif val == BREEZE_BLUE:
            if key == "BackgroundNormal" and section == "[Colors:Selection]":
                line = f"{key}={INDIGO}"
            elif dark and key in ("DecorationFocus", "DecorationHover"):
                line = f"{key}={INDIGO_LIGHT}"
            elif dark and key == "ForegroundActive":
                line = f"{key}={INDIGO_TEXT}"
            else:
                line = f"{key}={INDIGO}"
        elif val == BREEZE_LINK_LIGHT and key == "ForegroundLink":
            line = f"{key}={INDIGO_DEEP}"
        elif val == BREEZE_LINK_DARK and key == "ForegroundLink":
            line = f"{key}={INDIGO_TEXT}"
        elif val == BREEZE_SEL_ALT and key == "BackgroundAlternate":
            line = f"{key}={SEL_ALT_DARK if dark else INDIGO_DEEP}"
        out.append(line)
    return "\n".join(out) + "\n"


def main() -> None:
    light, dark = map(Path, sys.argv[1:3])
    here = Path(__file__).resolve().parent
    (here / "QuillLight.colors").write_text(derive(light, False))
    (here / "QuillDark.colors").write_text(derive(dark, True))


if __name__ == "__main__":
    main()
