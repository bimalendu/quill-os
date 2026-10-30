# Quill OS build entry points. Works with the make 3.81 shipped on macOS.

FEDORA_RELEASE ?= 44
MACHINE        ?= quill-build
BUILDER_IMAGE  ?= quill-os-builder:f$(FEDORA_RELEASE)
PROFILE        ?= Workstation-KDE
# Images are built on a named volume inside the podman machine: kiwi needs
# loop devices and a real filesystem, which a macOS bind mount cannot give.
OUTVOL         ?= quill-out

# The rootful connection of the dedicated machine, so the user's default
# podman machine is never touched.
PODMAN = podman --connection $(MACHINE)-root

.PHONY: help doctor machine machine-stop builder shell kiwi-version profiles rpms image fetch-image installer-pkg test clean

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
	@echo "  make fetch-image    copy the built image from the volume to ./out/"
	@echo "  make rpms           build Quill RPMs                  (Phase 3)"
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

KIWI_RUN = $(PODMAN) run --rm --privileged -v "$(CURDIR)/kiwi":/code:ro,z -v $(OUTVOL):/out $(BUILDER_IMAGE)

# kiwi cannot list profiles without a type, so read the XML directly.
profiles:
	@grep -rhoE '<profile name="[^"]+" description="[^"]*"' kiwi --include='*.xml' \
		| sed -E 's/<profile name="([^"]+)" description="([^"]*)"/\1\t\2/' | sort

image:
	$(KIWI_RUN) kiwi-ng --debug --type=oem --profile=$(PROFILE) --color-output \
		system build --description /code --target-dir /out/$(PROFILE)

fetch-image:
	mkdir -p out
	$(PODMAN) run --rm -v $(OUTVOL):/out $(BUILDER_IMAGE) tar -C /out -cf - $(PROFILE) | tar -C out -xf -

rpms:
	@echo "make rpms is implemented in Phase 3 (branding RPMs)"; exit 1

installer-pkg:
	@echo "make installer-pkg is implemented in Phase 7 (installer)"; exit 1

test:
	@./tests/run.sh

clean:
	rm -rf out
