FROM ubuntu:focal

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update

RUN apt install -y --no-install-recommends \
        ca-certificates apt-utils wget curl \
        lsb-release zip

RUN apt install -y --no-install-recommends \
        build-essential git make cmake \
        pkg-config ninja-build

# SDL2 build deps — build from source so RSDKv3 links against a modern SDL2.
# The built libSDL2 is NOT shipped; devices provide it at runtime.
RUN apt install -y --no-install-recommends \
        libasound2-dev libpulse-dev \
        libaudio-dev libjack-dev libsndio-dev libx11-dev libxext-dev \
        libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev \
        libxkbcommon-dev libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev \
        libegl1-mesa-dev libdbus-1-dev libibus-1.0-dev libudev-dev fcitx-libs-dev \
        libwayland-dev

# RSDKv3 (Sonic CD decomp) dependencies
RUN apt install -y --no-install-recommends \
        libglew-dev libglfw3-dev libogg-dev libtheora-dev libvorbis-dev

# Newer CMake (focal's is 3.16)
RUN wget https://github.com/Kitware/CMake/releases/download/v3.31.3/cmake-3.31.3-linux-`uname -m`.sh
RUN chmod a+x ./cmake-3.31.3-linux-`uname -m`.sh
RUN ./cmake-3.31.3-linux-`uname -m`.sh --prefix=/usr/local --exclude-subdir --skip-license

WORKDIR "/root"

CMD ["bash"]
