# Building Dusklight for Linux ARM64

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

## 2. Clone & build

```bash
git clone --recurse-submodules https://github.com/TwilitRealm/dusklight.git
cd dusklight
git checkout v1.0.1   # or whatever the latest release tag is

cmake --preset linux-clang \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
  -DCMAKE_C_COMPILER=clang-19 -DCMAKE_CXX_COMPILER=clang++-19 \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld-19 -static-libstdc++ -static-libgcc" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld-19" \
  -DDUSK_ENABLE_DISCORD=OFF \
  -DDUSK_ENABLE_UPDATE_CHECKER=OFF \
  -DDUSK_ENABLE_SENTRY_NATIVE=OFF

cmake --build build/linux-clang --parallel "$(nproc)"
cmake --install build/linux-clang

# Binary name flipped from `dusk` to `dusklight` in upstream PR #1064.
# v1.0.1 still produces `dusk`; v1.0.2+ produces `dusklight`. Probe both.
bin=""
for c in build/install/dusklight build/install/dusk; do
  [ -f "$c" ] && bin="$c" && break
done
strip --strip-unneeded "$bin"
```

The install step lands the binary and `res/` (fonts, ImGui assets, RML stylesheets) under `build/install/`.

## 3. Install into the port folder

Copy the built binary to `ports/zelda-dusklight/dusklight` (always renamed to `dusklight` regardless of upstream output name) and `res/` to `ports/zelda-dusklight/res/`:

```bash
cp "$bin"                    /path/to/SDCARD/ports/zelda-dusklight/dusklight
cp -r build/install/res      /path/to/SDCARD/ports/zelda-dusklight/res
```

Then drop your Twilight Princess game files directly into the `ports/zelda-dusklight/` folder.

## 4. Bundled libraries

The buildtool ships `libfreetype.so.6` plus its transitive deps (`libpng16`, `libz`, `libbz2`, `libbrotlidec`, `libbrotlicommon`) under `ports/zelda-dusklight/libs/` because not every handheld OS provides them. **Do not bundle `libvulkan.so.1` or any GPU driver** — those must come from the device.

If you build manually and the port complains about missing `.so` files at runtime, copy the missing libraries from `/usr/lib/aarch64-linux-gnu/` on your build host into `ports/zelda-dusklight/libs/`. The launch script adds `libs/` to `LD_LIBRARY_PATH`.
