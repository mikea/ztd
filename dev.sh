#!/bin/bash -eux

if (( $# != 1 )); then
    >&2 echo "Usage: dev.sh <command>"
    exit 1
fi

clean() {
    rm -rf zig-out
}

dist() {
    clean
    zig build -Drelease-fast=true -Dtarget=x86_64-windows
    (cd zig-out/bin && zip -r ztd.zip . && mv *.zip ../..)
}

case $1 in
    dist)
        dist
        ;;
    *)
        >&2 echo "Unknown command: $1"
        exit 1
        ;;
esac