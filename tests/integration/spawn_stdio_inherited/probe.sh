#!/bin/sh
# Exits 0 when the standard streams are open, 1 naming the first that is not.
for fd in 0 1 2; do
    if ! test -e /dev/fd/$fd; then exit $((fd + 1)); fi
done
exit 0
