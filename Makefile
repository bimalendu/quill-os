# Quill OS build entry points. Works with the make 3.81 shipped on macOS.

FEDORA_RELEASE ?= 44
MACHINE        ?= quill-build
BUILDER_IMAGE  ?= quill-os-builder:f$(FEDORA_RELEASE)
PROFILE        ?= Quill-KDE

# The rootful connection of the dedicated machine, so the user's default
# podman machine is never touched.
PODMAN = podman --connection $(MACHINE)-root

.PHONY: help doctor machine machine-stop builder shell kiwi-version rpms image installer-pkg test clean

help:
	@echo "Quill OS build targets"
	@echo "  make doctor         check host tools and the build machine"
	@echo "  make machine        create and start the rootful '$(MACHINE)' podman machine"
	@echo "  make machine-stop   stop the build machine"
	@echo "  make builder        build the Fedora $(FEDORA_RELEASE) builder container"
	@echo "  make shell          open a shell in the builder container"
	@echo "  make kiwi-version   run kiwi-ng --version in the builder (toolchain check)"
	@echo "  make rpms           build Quill RPMs                  (Phase 3)"
	@echo "  make image          build a kiwi image, PROFILE=$(PROFILE)  (Phase 2)"
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

rpms:
	@echo "make rpms is implemented in Phase 3 (branding RPMs)"; exit 1

image:
	@echo "make image is implemented in Phase 2 (kiwi descriptions fork)"; exit 1

installer-pkg:
	@echo "make installer-pkg is implemented in Phase 7 (installer)"; exit 1

test:
	@./tests/run.sh

clean:
	rm -rf out
