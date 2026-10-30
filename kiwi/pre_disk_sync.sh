#!/bin/bash

# Remove kiwi leftovers we don't need
# https://github.com/OSInside/kiwi/issues/2343#issuecomment-1663427508
rm /boot/mbrid /config.bootoptions /config.partids

## Create /etc/X11/xorg.conf.d, see rhbz#2240159
mkdir -p /etc/X11/xorg.conf.d

exit 0
