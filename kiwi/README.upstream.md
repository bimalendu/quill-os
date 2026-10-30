# Fedora Asahi Remix KIWI descriptions

This contains the KIWI descriptions for building the Fedora Asahi Remix.

This repository has multiple branches, one for each supported Fedora release. The default branch is `rawhide`, and is probably _not_ what you want.

## Spin variants

* Minimal (image type: `oem`, image profiles: `Minimal`)
* Server (image type: `oem`, image profiles: `Server`)
* Workstation GNOME (image type: `oem`, image profiles: `Workstation-GNOME`)
* Workstation KDE (image type: `oem`, image profiles: `Workstation-KDE`)

## Spin build quickstart

### Pre-requisites for non-AArch64 hosts

On non-AArch64 hosts, install `qemu-user-static` and restart the binfmt service:

```bash
$ sudo dnf --assumeyes install qemu-user-static
$ sudo systemctl restart systemd-binfmt.service
```

Note that building non-aarch64 is untested and likely to expose bugs.

### Podman

The instructions below will use the `podman` command. Only Podman is supported for this workflow.

First, pull down the container of the required environment (Fedora Linux 36 or higher works). We'll use Fedora Linux 42.

```bash
$ sudo podman pull registry.fedoraproject.org/fedora:42-aarch64
```

Assuming you're in the root directory of the Git checkout, set up the container:

```bash
$ sudo podman run --privileged --rm -it -v $PWD:/code:z -w /code registry.fedoraproject.org/fedora:42-aarch64 /bin/bash
```

Once in the container environment, set up your development environment and run the image build (substitute `<image_type>` and `<image_profile>` for the appropriate settings):

```bash
# Install kiwi and qemu-img
[]$ dnf --assumeyes install kiwi qemu-img
# Run the image build
[]$ kiwi-ng --type=<image_type> --profile=<image_profile> --color-output system build --description ./ --target-dir ./outdir
```

For example, to build the --profile=Workstation-GNOME profile:

```bash
[]$ kiwi-ng --debug --type=oem --profile=Workstation-GNOME --color-output system build --description ./ --target-dir ./outdir
```

We also provide a script to generate an [Asahi Installer](https://github.com/AsahiLinux/asahi-installer) package from the raw image that kiwi produces:

```bash
# Install prerequsites
[]$ dnf --assumeyes install fatcat gawk p7zip-plugins rpmdistro-repoquery util-linux zip zstd
# Build the package
[]$ ./make-asahi-installer-package.sh outdir/Fedora-Asahi-Remix.aarch64-0.0.0.raw package.zip
```

## Contributing

Please default to submitting PRs against the `rawhide` branch. Release branches should generally merge from `rawhide` and only deviate where absolutely necessary.

This project is tested using the [Software Factory Zuul CI instance](https://fedora.softwarefactory-project.io/zuul/project/pagure.io/fedora-asahi/kiwi-descriptions)
using the [Test Management Tool](https://tmt.readthedocs.io/).

## Licensing

This is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, under version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
