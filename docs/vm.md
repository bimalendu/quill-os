# Quill OS in a virtual machine

For Macs the native installer cannot target (M3 Ultra, M4, M5, or any Mac where
you would rather not repartition), and for trying Quill OS before installing it
natively.

The VM image is a generic aarch64 UEFI system: Fedora's own kernel, GRUB and the
QEMU/SPICE guest agents. It contains none of the Asahi hardware packages
(Asahi kernel, m1n1, U-Boot, firmware tools), and no x86 emulation (FEX and muvm
need Apple GPU features a VM does not have). It is the same Quill OS otherwise:
branding, the no-AI policy and the first-login Quill Setup picker.

## Build

    make machine && make builder     # once
    make rpms                        # the Quill packages
    make image PROFILE=VM-KDE        # about 15 minutes
    make fetch-image PROFILE=VM-KDE  # copies the result to ./out/VM-KDE/

The result is `Quill-OS.aarch64-<version>.qcow2`: a 32 GiB virtual disk that
occupies about 3.7 GiB on disk.

## One command

With [UTM](https://mac.getutm.app/) installed and the image fetched
(`make fetch-image PROFILE=VM-KDE`):

    make install-vm        # import and start
    make vm-status         # read-only: state, address, os-release from inside the guest
    make uninstall-vm      # delete the VM (asks you to type yes)

`install-vm` creates one VM named **Quill OS** through UTM's scripting interface
(4096 MiB, 4 cores, UEFI, VirtIO disk and network, virtio-gpu-gl-pci display; set
`QUILL_VM_MEMORY` and `QUILL_VM_CPUS` to change the first two, and add
`INSTALL_VM_ARGS=--no-start` to import without starting). Before it changes anything it
checks that the image matches its `.sha256`, that 8 GB are free, and that UTM has no VM
named Quill OS yet; it refuses otherwise. It never touches your other VMs. UTM stores its
own copy of the disk (about 5.3 GB), so `out/VM-KDE/` can be deleted afterwards.
`uninstall-vm` deletes only the VM whose id `install-vm` saved in `out/utm-vm-id`, and
refuses a running VM.

The first run makes macOS ask whether Terminal may control UTM; allow it.

## Run it in UTM by hand

The same result without the script:

These steps were used to boot the image on 2026-10-31 (UTM on an Apple Silicon
Mac): it reached Plasma Setup, the Quill login screen, the desktop and the
Quill Setup window.

1. Install [UTM](https://mac.getutm.app/) (free from the website).
2. *Create a New Virtual Machine* -> **Virtualize** -> **Other**.
3. Choose **Skip ISO boot**.
4. Memory 4096 MB or more, 4 or more CPU cores. (Quill OS idles near 1 GB, but
   a desktop with Firefox is more comfortable with 4 GB.)
5. In the storage step accept the default, finish, then **edit the VM**:
   delete the default disk and add *Import* -> select the `.qcow2` file.
   Interface: **VirtIO**.
6. Under *Display* use **virtio-gpu-gl-pci** for acceleration; if the screen
   stays black, switch to **virtio-ramfb** or **virtio-gpu-pci**.
7. Make sure UEFI boot is on (the default for aarch64 VMs in UTM).
8. Start the VM.

Expected first boot: GRUB (menu hidden), the boot splash, then **Plasma Setup**
(user, language, keyboard), then the Plasma Login Manager, then your desktop and
the **Quill Setup** window offering software groups.

## Where the image comes from, and what to check

`make check-vm` runs 26 static checks on the image (it does not boot it; it needs the
raw disk, which `make image` leaves in the build volume until space is reclaimed): the
qcow2 is consistent and identical to the raw disk, the UEFI fallback loader
`EFI/BOOT/BOOTAA64.EFI` exists, the boot entry names the stock kernel and the
right root UUID, `/etc/fstab` matches the partitions, the drivers needed to
mount the disk are built into the kernel or in the initramfs, and the services
for a graphical login, first-boot setup and the guest agents are enabled.

## Enlarging the disk

The image ships with a 32 GiB disk. To make it larger: resize the disk in UTM
with the VM shut down, then inside Quill OS grow the partition and the Btrfs
filesystem (for example `sudo growpart /dev/vda 3` and
`sudo btrfs filesystem resize max /`). `growpart` is in `cloud-utils-growpart`.

## Known limits

- No GPU acceleration beyond what virtio-gpu offers; expect software rendering
  for heavy 3D.
- No Asahi hardware: audio, Wi-Fi, camera and so on come from the host and
  UTM's virtual devices.
- Booted in UTM only; Parallels and VMware Fusion are untested.
