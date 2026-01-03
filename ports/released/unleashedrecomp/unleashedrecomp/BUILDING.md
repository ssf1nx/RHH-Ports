# Building Sonic Unleashed Recomp
The following are build steps taken in a WSL2 chroot for debian bookworm, with a Windows 11 host. Your steps may be different depending on your build host. For example, you may not have to speficy clang-16. If in doubt, ask AI.

#### Gather core game files
You need some specific files to compile `UnleashedRecomp`. Use an existing release from [UnleashedRecomp Repo](https://github.com/hedge-dev/UnleashedRecomp/releases) and install the game. Go through the setup process and install Unleashed, the DLC, and all updates.

Verify the following files exist in `UnleashedRecomp/game` and `UnleashedRecomp/update` subdirectories:

```
default.xex
default.xexp
shader.ar
```

#### Set up repository
Install dependencies and clone the UnleashedRecomp repository:

```
apt-get update && sudo apt-get upgrade
apt install autoconf automake libtool pkg-config curl cmake ninja-build clang-16 lld-16 clang-tools libgtk-3-dev
git clone --recurse-submodules https://github.com/hedge-dev/UnleashedRecomp.git
cd UnleashedRecomp
```

Copy the three files from the first step to `./UnleashedRecompLib/private/`:

```
cp "/mnt/y/Sonic Unleashed Recomp/game/default.xex" ./UnleashedRecompLib/private/
cp "/mnt/y/Sonic Unleashed Recomp/game/shader.ar" ./UnleashedRecompLib/private/
cp "/mnt/y/Sonic Unleashed Recomp/update/default.xexp" ./UnleashedRecompLib/private
```

Change `/mnt/y/Sonic Unleashed Recomp` to the path to your UnleashedRecomp installation.

#### Build DXCompiler
Next you must build DXCompiler or it will be missing during the Recomp build.

Build it using the below steps:

```
cd tools/XenosRecomp/thirdparty/dxc-bin

VERSION="release-1.8.2502"
BUILD_DIR_UNIVERSAL=$(mktemp -d)
git clone -b ${VERSION} https://github.com/microsoft/DirectXShaderCompiler.git
cd DirectXShaderCompiler
git submodule update --init

cmake -B $BUILD_DIR_UNIVERSAL \
  -GNinja \
  -C./cmake/caches/PredefinedParams.cmake \
  -DSPIRV_BUILD_TESTS=ON \
  -DCMAKE_BUILD_TYPE=Release

ninja -C $BUILD_DIR_UNIVERSAL -j$(nproc)
```

This will take some time. Once the build is complete copy the final builds to the appropriate directories:

```
cp "$BUILD_DIR_UNIVERSAL/bin/dxc-3.7" ../bin/arm64/dxc-linux
cp "$BUILD_DIR_UNIVERSAL/lib/libdxcompiler.so" ../lib/arm64/libdxcompiler.so
```

Verify these files copied successfully before moving on. If either are missing, use `ls $BUILD_DIR_UNIVERSAL/bin` and `ls $BUILD_DIR_UNIVERSAL/lib` to check the filenames are correct and they exist.

#### Build UnleashedRecomp
Now you can build the UnleashedRecomp binary:

```
cd ../../../../../
export VCPKG_FORCE_SYSTEM_BINARIES=1
export CC=clang-16
export CXX=clang++-16
(cd thirdparty/vcpkg && [ -f ./vcpkg ] || ./bootstrap-vcpkg.sh)

cmake . --preset linux-release \
  -DVCPKG_TARGET_TRIPLET=arm64-linux \
  -DCMAKE_C_COMPILER=clang-16 \
  -DCMAKE_CXX_COMPILER=clang++-16 \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld-16" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld-16"

cmake --build ./out/build/linux-release --target UnleashedRecomp --parallel $(nproc)
```

Copy `out/build/linux-release/UnleashedRecomp` to the port folder `ports/unleashedrecomp`.

## Failure Points
If you're building on WSL debian bookworm, or lld is older than lld-16, you may get a mismatch in linker vs. clang-16. Use the following commands to fix the issue.

```
update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-16 100
update-alternatives --install /usr/bin/lld lld /usr/bin/lld-16 100
```

After this, `rm -rf out/` and restart from `cmake . --preset...`