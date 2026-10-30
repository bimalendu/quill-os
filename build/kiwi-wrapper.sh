#!/bin/sh
# Run a command while keeping /dev/loopN nodes alive.
#
# kiwi bind-mounts the container's /dev into the image chroot, and something
# there removes /dev/loop0 before kiwi creates the raw disk ("device node
# /dev/loop0 is lost"). Recreate missing nodes in the background and log each
# recreation to /out/loop-nodes.log so the culprit can be found later.
n=${LOOP_NODES:-16}
(
    while :; do
        i=0
        while [ "$i" -lt "$n" ]; do
            if [ ! -b "/dev/loop$i" ]; then
                mknod "/dev/loop$i" b 7 "$i" 2>/dev/null &&
                    echo "$(date +%T) recreated /dev/loop$i" >> /out/loop-nodes.log
            fi
            i=$((i + 1))
        done
        sleep 0.2
    done
) &
exec "$@"
