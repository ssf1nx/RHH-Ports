# Building Dusk for Linux ARM64

This port is built automatically on each upstream release via the [Build Ports](../../../../.github/workflows/build_ports.yml) workflow.

If you want to build it yourself for development, see below.

## 1. Dependencies (Debian trixie / equivalent)

```bash
sudo apt-get install -y \
  git cmake ninja-build python3 python3-markupsafe pkg-config \
  clang-19 lld-19 \
  libvulkan-dev libcurl4-openssl-dev libpng-dev libfreetype-dev libjpeg-dev \
  libgtk-3-dev libssl-dev zlib1g-dev libdbus-1-dev \
  libxi-dev libxrandr-dev libxinerama-dev libxcursor-dev libxss-dev \
  libx11-xcb-dev libxkbcommon-dev libwayland-dev libdecor-0-dev \
  libasound2-dev libpulse-dev libudev-dev libusb-1.0-0-dev \
  libpipewire-0.3-dev \
  autoconf automake libtool
```

Plus a **Rust toolchain** (Aurora's `nod` is built from source via Corrosion on aarch64 since no prebuilt nod release exists for that arch):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
```

And **vcpkg** at a stable path:

```bash
git clone --depth 1 https://github.com/microsoft/vcpkg.git ~/vcpkg
VCPKG_FORCE_SYSTEM_BINARIES=1 ~/vcpkg/bootstrap-vcpkg.sh
export VCPKG_ROOT=~/vcpkg
```

## 2. Clone & build

```bash
git clone --recurse-submodules https://github.com/TwilitRealm/dusk.git
cd dusk
git checkout v1.0.0   # or whatever the latest release tag is

cmake --preset linux-clang-relwithdebinfo \
  -DVCPKG_TARGET_TRIPLET=arm64-linux \
  -DCMAKE_C_COMPILER=clang-19 -DCMAKE_CXX_COMPILER=clang++-19 \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld-19" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld-19" \
  -DDUSK_ENABLE_DISCORD=OFF \
  -DDUSK_ENABLE_UPDATE_CHECKER=OFF \
  -DDUSK_ENABLE_SENTRY_NATIVE=OFF

cmake --build build/linux-clang-relwithdebinfo --parallel "$(nproc)"
cmake --install build/linux-clang-relwithdebinfo
```

The install step lands the `dusk` binary and `res/` (fonts, ImGui assets, RML stylesheets) under `build/install/`.

## 3. Install into the port folder

Copy the built `dusk` executable to `ports/zelda-dusk/dusk` and `res/` to `ports/zelda-dusk/res/`:

```bash
cp build/install/dusk        /path/to/SDCARD/ports/zelda-dusk/dusk
cp -r build/install/res      /path/to/SDCARD/ports/zelda-dusk/res
```

Then drop your Twilight Princess game files directly into the `ports/zelda-dusk/` folder.

## 4. Bundled libraries

The buildtool ships `libfreetype.so.6` plus its transitive deps (`libpng16`, `libz`, `libbz2`, `libbrotlidec`, `libbrotlicommon`) under `ports/zelda-dusk/libs/` because not every handheld OS provides them. **Do not bundle `libvulkan.so.1` or any GPU driver** — those must come from the device.

If you build manually and the port complains about missing `.so` files at runtime, copy the missing libraries from `/usr/lib/aarch64-linux-gnu/` on your build host into `ports/zelda-dusk/libs/`. The launch script adds `libs/` to `LD_LIBRARY_PATH`.
