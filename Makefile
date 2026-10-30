# Quill OS build entry points. Works with the make 3.81 shipped on macOS.

FEDORA_RELEASE ?= 44
MACHINE        ?= quill-build
BUILDER_IMAGE  ?= quill-os-builder:f$(FEDORA_RELEASE)
PROFILE        ?= Workstation-KDE
# Apple NVMe disks use 4096-byte sectors, so the Apple Silicon images are written that
# way; a VM disk (a profile with VM in its name) uses 512.
SECTOR         = $(if $(findstring VM,$(PROFILE)),512,4096)
# Images are built on a named volume inside the podman machine: kiwi needs
# loop devices and a real filesystem, which a macOS bind mount cannot give.
OUTVOL         ?= quill-out
# The kiwi description is copied into this volume before each build. Reading
# it straight from the macOS bind mount fails: the mount carries no SELinux
# labels, and kiwi's `rsync -X` then tries to strip the label from the copy,
# which SELinux never allows.
SRCVOL         ?= quill-src
# Local rpm-md repository of Quill packages and the dev key that signs them.
RPMVOL         ?= quill-rpms
KEYVOL         ?= quill-keys

# The rootful connection of the dedicated machine, so the user's default
# podman machine is never touched.
PODMAN = podman --connection $(MACHINE)-root

.PHONY: help doctor machine machine-stop builder shell kiwi-version profiles sync-src check-image check-branding check-no-ai check-firefox check-group-packages check-setup-helper check-setup-app rpms image fetch-image installer-pkg test clean

help:
	@echo "Quill OS build targets"
	@echo "  make doctor         check host tools and the build machine"
	@echo "  make machine        create and start the rootful '$(MACHINE)' podman machine"
	@echo "  make machine-stop   stop the build machine"
	@echo "  make builder        build the Fedora $(FEDORA_RELEASE) builder container"
	@echo "  make shell          open a shell in the builder container"
	@echo "  make kiwi-version   run kiwi-ng --version in the builder (toolchain check)"
	@echo "  make profiles       list kiwi profiles in kiwi/"
	@echo "  make image          build the kiwi image for PROFILE=$(PROFILE)"
	@echo "  make check-image    assert package expectations on the built image"
	@echo "  make check-branding assert the built image's on-disk branding"
	@echo "  make check-no-ai    validate the no-AI Firefox policy against the image"
	@echo "  make check-firefox  run the image's Firefox headless and assert the no-AI policy"
	@echo "  make check-group-packages  check the setup groups name real aarch64 packages (network)"
	@echo "  make check-setup-helper  test the group installer as root with real dnf"
	@echo "  make check-setup-app  install the quill-setup RPM and test it (autostart, files)"
	@echo "  make fetch-image    copy the built image from the volume to ./out/"
	@echo "  make rpms           build, sign and publish packages/ to the local repo"
	@echo "  make installer-pkg  package an image for asahi-installer (Phase 7)"
	@echo "  make test           run repository checks"
	@echo "  make clean          remove build output"

doctor:
	@./tests/doctor.sh "$(MACHINE)"

machine:
	@if podman machine inspect $(MACHINE) >/dev/null 2>&1; then \
		echo "machine '$(MACHINE)' already exists"; \
	else \
		podman machine init --rootful --cpus 4 --memory 4096 --disk-size 80 $(MACHINE); \
	fi
	@podman machine list --format '{{.Name}} {{.Running}}' | grep -q '^$(MACHINE)\*\? true' \
		|| podman machine start $(MACHINE)

machine-stop:
	podman machine stop $(MACHINE)

builder:
	$(PODMAN) build --build-arg FEDORA_RELEASE=$(FEDORA_RELEASE) \
		-t $(BUILDER_IMAGE) -f build/Containerfile build

shell:
	$(PODMAN) run --rm -it --privileged -v "$(CURDIR)":/work $(BUILDER_IMAGE) bash

# kiwi-ng 11.x exits 1 for --version and --help (no subcommand), so judge the
# output, not the exit code.
kiwi-version:
	$(PODMAN) run --rm --privileged $(BUILDER_IMAGE) \
		sh -c 'out=$$(kiwi-ng --version 2>&1); echo "$$out"; echo "$$out" | grep -q "^KIWI"'

# The VM's real /dev is mounted because a container's static /dev never gets
# the partition nodes (/dev/loop0p1 ...) kiwi needs after attaching the disk.
KIWI_RUN = $(PODMAN) run --rm --privileged -v /dev:/dev -v $(SRCVOL):/code:ro -v $(RPMVOL):/quill-repo:ro -v $(OUTVOL):/out $(BUILDER_IMAGE)

# kiwi cannot list profiles without a type, so read the XML directly.
profiles:
	@grep -rhoE '<profile name="[^"]+" description="[^"]*"' kiwi --include='*.xml' \
		| sed -E 's/<profile name="([^"]+)" description="([^"]*)"/\1\t\2/' | sort

sync-src:
	-$(PODMAN) volume rm -f $(SRCVOL) >/dev/null
	$(PODMAN) volume create $(SRCVOL) >/dev/null
	COPYFILE_DISABLE=1 tar -C kiwi -cf - . | $(PODMAN) run --rm -i -v $(SRCVOL):/code $(BUILDER_IMAGE) tar -C /code -xf -

image: sync-src
	$(KIWI_RUN) kiwi-ng --debug --type=oem --profile=$(PROFILE) --color-output \
		system build --description /code --target-dir /out/$(PROFILE)

# Assert the built image's package list and the AI denylist; PROFILE selects the expectations.
check-image:
	COPYFILE_DISABLE=1 tar -cf - tests/check-packages.sh tests/check-denylist.sh policy/ai-denylist.txt | \
		$(PODMAN) run --rm -i -v $(OUTVOL):/out:ro $(BUILDER_IMAGE) \
		sh -c 'mkdir /c && tar -C /c -xf - && cd /c \
		&& sh tests/check-packages.sh /out/$(PROFILE)/*.packages $(PROFILE) \
		&& sh tests/check-denylist.sh policy/ai-denylist.txt --rpms /out/$(PROFILE)/*.packages'

# Mount the built image read-only and assert its on-disk branding.
check-branding:
	$(PODMAN) run --rm -i --privileged -v /dev:/dev -v $(OUTVOL):/out:ro $(BUILDER_IMAGE) \
		sh -c 'cat > /tmp/c.sh; d=$$(losetup -P --sector-size $(SECTOR) -f --show /out/$(PROFILE)/*.raw); \
		sleep 1; mkdir -p /m; mount -o ro,subvol=root $${d}p3 /m; \
		sh /tmp/c.sh /m $(PROFILE); rc=$$?; umount /m; losetup -d $$d; exit $$rc' < tests/check-branding.sh

# Validate the no-AI policy against the built image's own Firefox schema.
check-no-ai:
	$(PODMAN) run --rm -i --privileged -v /dev:/dev -v $(OUTVOL):/out:ro $(BUILDER_IMAGE) \
		sh -c 'cat > /tmp/c.sh; d=$$(losetup -P --sector-size $(SECTOR) -f --show /out/$(PROFILE)/*.raw); \
		sleep 1; mkdir -p /m; mount -o ro,subvol=root $${d}p3 /m; \
		sh /tmp/c.sh /m; rc=$$?; umount /m; losetup -d $$d; exit $$rc' < tests/check-no-ai.sh

# Start the image's own Firefox headless (in a chroot) and assert that the no-AI
# policy is applied. Slow (about a minute) and needs the built image.
check-firefox:
	$(PODMAN) run --rm -i --privileged -v /dev:/dev -v $(OUTVOL):/out:ro $(BUILDER_IMAGE) \
		sh -c 'cat > /tmp/probe.py; d=$$(losetup -P --sector-size $(SECTOR) -f --show /out/$(PROFILE)/*.raw); sleep 1; \
		mkdir -p /m; mount -o ro,subvol=root $${d}p3 /m; rm -rf /ffhome; mkdir -p /ffhome/prof; \
		mount --bind /ffhome /m/tmp; mount --bind /proc /m/proc; mount --bind /dev /m/dev; \
		chroot /m /usr/bin/env HOME=/tmp MOZ_HEADLESS=1 MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 \
			timeout 90 /usr/bin/firefox --headless --no-remote --marionette --profile /tmp/prof about:blank >/tmp/ff.out 2>&1 & \
		python3 /tmp/probe.py; rc=$$?; pkill -f bin/firefox; sleep 2; \
		umount /m/dev /m/proc /m/tmp /m; losetup -d $$d; exit $$rc' < tests/probe-firefox.py

# Check every package and Flatpak in the Quill Setup groups exists for aarch64 (needs network).
check-group-packages:
	rm -rf out/groups && python3 tests/check-groups.py --dump out/groups
	COPYFILE_DISABLE=1 tar -cf - -C out groups -C .. tests/check-group-packages.sh | \
		$(PODMAN) run --rm -i $(BUILDER_IMAGE) \
		sh -c 'mkdir /c && tar -C /c -xf - && sh /c/tests/check-group-packages.sh /c/groups'

# Test the privileged installer as root with real dnf (changes only the throwaway container).
check-setup-helper:
	COPYFILE_DISABLE=1 tar -cf - -C packages/quill-setup/src quill-setup-helper groups -C ../../.. tests/test-setup-helper.sh | \
		$(PODMAN) run --rm -i $(BUILDER_IMAGE) \
		sh -c 'mkdir /c && tar -C /c -xf - && sh /c/tests/test-setup-helper.sh'

# Install the built quill-setup RPM in a clean container and test it, including autostart.
check-setup-app:
	$(PODMAN) run --rm -i -v $(RPMVOL):/repo:ro $(BUILDER_IMAGE) \
		sh -c 'cat > /tmp/t.sh; sh /tmp/t.sh' < tests/test-setup-app.sh

fetch-image:
	mkdir -p out
	$(PODMAN) run --rm -v $(OUTVOL):/out $(BUILDER_IMAGE) tar -C /out -cf - $(PROFILE) | tar -C out -xf -

# Build, sign and publish packages/ as an rpm-md repo in the $(RPMVOL) volume.
# The dev signing key lives in $(KEYVOL), never in the working tree.
rpms:
	-$(PODMAN) volume create $(KEYVOL) >/dev/null
	-$(PODMAN) volume create $(RPMVOL) >/dev/null
	rm -rf out/stage && mkdir -p out/stage
	cp -R packages/. out/stage/
	cp policy/ai-denylist.txt out/stage/quill-no-ai/ai-denylist.txt
	# quill-setup ships a source tarball built from its src/ tree.
	tar -czf out/stage/quill-setup/quill-setup-44.tar.gz -s ',^src,quill-setup-44,' -C packages/quill-setup src
	rm -rf out/stage/quill-setup/src
	COPYFILE_DISABLE=1 tar -C out/stage -cf - . | $(PODMAN) run --rm -i \
		-v $(KEYVOL):/keys -v $(RPMVOL):/repo $(BUILDER_IMAGE) \
		sh -c 'mkdir /src && tar -C /src -xf - && build-rpms'

installer-pkg:
	@echo "make installer-pkg is implemented in Phase 7 (installer)"; exit 1

test:
	@./tests/run.sh

clean:
	rm -rf out
