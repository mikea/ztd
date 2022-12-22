FROM ubuntu:jammy

# tools
RUN apt-get update && apt-get install -y wget zip xz-utils build-essential

# zig
RUN \
    cd /tmp \
    && wget https://github.com/marler8997/zigup/releases/download/v2022_08_25/zigup.ubuntu-latest-x86_64.zip \
    && unzip zigup.ubuntu-latest-x86_64.zip \
    && chmod +x zigup \
    && mv zigup /usr/local/bin \
    && zigup master

# linux dependencies
RUN apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libcairo2-dev

# windows dependencies
RUN \
    mkdir /win \
    && cd /win \
    && wget https://github.com/libsdl-org/SDL/releases/download/release-2.26.1/SDL2-devel-2.26.1-VC.zip \
    && unzip SDL2-devel-2.26.1-VC.zip \
    && mv SDL2-2.26.1 SDL2 \
    && wget https://github.com/libsdl-org/SDL_image/releases/download/release-2.6.2/SDL2_image-devel-2.6.2-VC.zip \
    && unzip SDL2_image-devel-2.6.2-VC.zip \
    && mv SDL2_image-2.6.2 SDL2_image \
    && wget https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.20.1/SDL2_ttf-devel-2.20.1-VC.zip \
    && unzip SDL2_ttf-devel-2.20.1-VC.zip \
    && mv SDL2_ttf-2.20.1 SDL2_ttf \
    && wget https://github.com/preshing/cairo-windows/releases/download/1.17.2/cairo-windows-1.17.2.zip \
    && unzip cairo-windows-1.17.2.zip \
    && mv cairo-windows-1.17.2 cairo

RUN mkdir /work
WORKDIR  /work
ADD . /work/

# linux release build
RUN \
    rm -rf zig-out \
    && zig build -Drelease-fast=true \
    && cd zig-out/bin \
    && zip -r ../../ztd-x86_64-linux.zip .

# windows release build
RUN \
    rm -rf zig-out \
    && zig build -Drelease-fast=true -Dtarget=x86_64-windows \
    && cd zig-out/bin \
    && zip -r ../../ztd-x86_64-windows.zip .

RUN ls -al  
