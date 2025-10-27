# Build Steps

## Debian Bullseye
```
apt install -y \
git cmake g++ make ninja-build pkg-config \
libsdl2-dev libbz2-dev libfluidsynth-dev libopenal-dev \
libvpx-dev libwebp-dev zlib1g-dev libzmusic-dev \
libgtk-3-dev libgl1-mesa-dev libgles2-mesa-dev
git clone --recursive https://github.com/ZDoom/gzdoom.git
cd gzdoom
git checkout g4.14.2
git submodule update --init --recursive
```

Switch the tag to any desired e.g. 4.11.3. If building the "Lite" version (mirroring [Knulli](https://github.com/knulli-cfw/distribution/blob/d0e0324d49f534c4cb14ef36a288293333ef8ab0/package/batocera/ports/gzdoom/gzdoom.mk)), also perform the following.

## GZDoom Lite

```
sed -i 's/#define USE_GLES2 0/#define USE_GLES2 1/' src/common/rendering/gles/gles_system.h
sed -i '1i #define __ANDROID__' src/common/rendering/gles/gles_system.cpp
```

Configure for Lite:

```
mkdir build
cd build
cmake .. \
-DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=ON \
-DHAVE_GLES2=ON \
-DHAVE_VULKAN=OFF \
-DFORCE_CROSSCOMPILE=OFF \
-DCMAKE_INSTALL_PREFIX=/usr/local

cmake --build . -j$(nproc)
```

## ZMusic

In some later versions of GZDoom you must manually build zmusic.

```
cd ~
git clone https://github.com/coelckers/zmusic.git
cd zmusic
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j$(nproc)
cmake --install .
```