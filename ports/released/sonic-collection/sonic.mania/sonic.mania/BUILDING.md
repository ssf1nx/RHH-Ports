## Building Sonic Mania & RSDKv5
This guide assumes you will be using WSL2 or similar with debian bullseye chroot. The Plus content is disabled in distributions and must be built by the end user.

Install dependencies:

```
apt install -y \
  build-essential \
  cmake \
  libglew-dev \
  libglfw3-dev \
  libtheora-dev \
  libdrm-dev \
  libgbm-dev
```

If you do use WSL2 with debian bullseye chroot, the bundled SDL2 will be quite old. Your build will benefit from using a newer SDL2 installed prior to building Sonic Mania:

```
git clone https://github.com/libsdl-org/SDL.git
cd SDL
git checkout release-2.32.0
mkdir -p build && cd build
cmake ..
make -j$(nproc)
make install
cd ../..
```

To build Mania:
```
git clone --recursive https://github.com/RSDKModding/Sonic-Mania-Decompilation
cd Sonic-Mania-Decompilation

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
  -DRETRO_REVISION=2 \
  -DRETRO_SUBSYSTEM=SDL2 \
  -DRETRO_DISABLE_PLUS=ON

cmake --build build --config release -j$(nproc)
```

To build Plus:
```
apt install build-essential cmake libglew-dev libglfw3-dev libtheora-dev libdrm-dev libgbm-dev
git clone --recursive https://github.com/RSDKModding/Sonic-Mania-Decompilation
cd Sonic-Mania-Decompilation

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
  -DRETRO_REVISION=2 \
  -DRETRO_SUBSYSTEM=SDL2 \
  -DRETRO_DISABLE_PLUS=OFF

cmake --build build --config release -j$(nproc)
```

In both cases, when the build is completed, retrieve the following files:

`Sonic-Mania-Decompilation\build\libGame.so` -- Copy to `ports/sonicmania` as `Game.so`  
`Sonic-Mania-Decompilation\build\dependencies\RSDKv5\RSDKv5` -- Copy to `ports/sonicmania` as `sonicmania`
