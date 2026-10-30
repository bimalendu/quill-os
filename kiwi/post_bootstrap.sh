#!/bin/bash

# Flag file to ensure update-m1n1 doesn't try to autodetect the ESP
mkdir -p /boot/efi/m1n1
touch /boot/efi/.builder

exit 0
