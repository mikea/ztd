FROM ubuntu:jammy

# tools
RUN apt-get update && apt-get install -y wget zip xz-utils build-essential

# need fresh 7z to unpack mac .dmg files

# RUN \
#     cd /tmp \
#     && wget https://www.7-zip.org/a/7z2201-linux-x64.tar.xz \
#     && unxz 7z2201-linux-x64.tar.xz \
#     && tar xvf 7z2201-linux-x64.tar \
#     && mv 7zz /usr/local/bin

# zig
RUN \
    cd /tmp \
    && wget https://github.com/marler8997/zigup/releases/download/v2022_08_25/zigup.ubuntu-latest-x86_64.zip \
    && unzip zigup.ubuntu-latest-x86_64.zip \
    && chmod +x zigup \
    && mv zigup /usr/local/bin \
    && zigup master

# linux dependencies
RUN apt-get install -y libglfw3-dev

# # windows dependencies
RUN \
    mkdir /win \
    && cd /win \
    && wget https://github.com/glfw/glfw/releases/download/3.3.8/glfw-3.3.8.bin.WIN64.zip \
    && unzip glfw-3.3.8.bin.WIN64.zip \
    && mv glfw-3.3.8.bin.WIN64 glfw \
    && ls -R glfw/

# # mac dependencies
RUN \
    mkdir /mac \
    && cd /mac \
    && wget https://github.com/glfw/glfw/releases/download/3.3.8/glfw-3.3.8.bin.MACOS.zip \
    && unzip glfw-3.3.8.bin.MACOS.zip \
    && mv glfw-3.3.8.bin.MACOS glfw \
    && ls -R glfw/

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

# mac release build: doesn't work because OpenGL/gl.h is not found
# RUN \
#     rm -rf zig-out \
#     && zig build -Dtarget=aarch64-macos

