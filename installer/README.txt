Quill OS installer for Apple Silicon Macs (M1 and later)
=========================================================

STATUS: built and checked on a build machine, but NOT yet tested on a real Mac.
Read the warnings. Install on a Mac you can afford to restore.

What this folder is
-------------------
Everything needed to install Quill OS except Apple's own firmware, which the
installer downloads from Apple (a network connection is needed for that step).
  install.sh                the starting point
  installer_data.json       the list of systems offered
  os/                       the Quill OS images (KDE Plasma, Minimal)
  installer-<version>.tar.gz  Asahi Linux's installer, unmodified
  SHA256SUMS                checksums of every file here

How to install
--------------
1. Copy this whole folder to the Mac (a USB disk or AirDrop). Keep the files together.
2. Back up your data. The installer resizes macOS to make room.
3. Open Terminal, then run:   cd "<this folder>" && ./install.sh
   (macOS may ask to let Terminal read the disk the folder is on.)
   Use  ./install.sh --verify  first to check the folder without installing.
4. Follow the installer's prompts. It will ask how much space to give Quill OS
   and which system to install. It will reboot into the Apple recovery screen once;
   follow the instructions it prints there.
5. First boot starts Quill Setup, where you pick your software.

Recovery
--------
Asahi Linux documents how to uninstall and how to recover macOS:
https://asahilinux.org/docs/ (Uninstall, and Platform notes).

The installer sends no statistics. Nothing in this folder phones home except
the installer's download of Apple firmware.
