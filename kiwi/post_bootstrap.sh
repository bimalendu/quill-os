#!/bin/bash

# Quill: only the Apple Silicon images use m1n1; the generic VM image has no use for it.
test -f /.profile && . /.profile
if [[ "${kiwi_profiles:-}" != *"BootVM"* ]]; then
	# Flag file to ensure update-m1n1 doesn't try to autodetect the ESP
	mkdir -p /boot/efi/m1n1
	touch /boot/efi/.builder
fi

exit 0
