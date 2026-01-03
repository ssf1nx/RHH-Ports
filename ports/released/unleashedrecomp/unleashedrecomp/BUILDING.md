# Building Sonic Unleashed Recomp
You need some specific files to compile `UnleashedRecomp`. Use an existing release from [UnleashedRecomp Repo](https://github.com/hedge-dev/UnleashedRecomp/releases) and install the game. Then get the following files:

```
default.xex
default.xexp
shader.ar
```
When sourcing these files from an Unleashed Recompiled installation, they will be stored under `game` and `update` subdirectories.

```
sudo apt-get update && sudo apt-get upgrade
sudo apt-get install cmake clang
git clone --recurse-submodules https://github.com/hedge-dev/UnleashedRecomp.git
cd UnleashedRecomp
```

At this point, gather the above files and place them in `./UnleashedRecompLib/private/`. Next you must build `libdxcompiler.so` or it will be missing during the Recomp build.

Build it and copy the final result to `/UnleashedRecomp/tools/XenosRecomp/thirdparty/dxc-bin/lib/arm64/libdxcompiler.so`:

```
cd UnleashedRecomp/tools/XenosRecomp/thirdparty/dxc-bin

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

ninja -C $BUILD_DIR_UNIVERSAL
```

This will take some time. Once the build is complete copy the library to the appropriate directory.

```
cp "$BUILD_DIR_UNIVERSAL/bin/dxc-3.7" ../bin/arm64/dxc
cp "$BUILD_DIR_UNIVERSAL/lib/libdxcompiler.so" ../lib/arm64/libdxcompiler.so
```

Now you can build the UnleashedRecomp binary:

```
cd ../../../../../
export VCPKG_FORCE_SYSTEM_BINARIES=1
cmake . --preset linux-release -DVCPKG_TARGET_TRIPLET=arm64-linux
cmake --build ./out/build/linux-release --target UnleashedRecomp
```

Build will be in `out/build/linux-release`.