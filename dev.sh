#!/bin/bash -eux

if (( $# != 1 )); then
    >&2 echo "Usage: dev.sh <command>"
    exit 1
fi

clean() {
    rm -rf zig-out
}

dist() {
    docker build -t ztd .
    mkdir -p release
    docker run --rm -v $(pwd)/release:/out ztd /bin/sh -c "cp /work/*.zip /out"
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