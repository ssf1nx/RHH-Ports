# yyg_qoi_decode

End-to-end externalizer for GameMaker 2zoq textures. Walks a `data.win`'s TXTR
chunk, decodes every 2zoq blob (bz2 → YYG-QOIF → RGBA), ASTC-compresses each
into a PVR v3 file, then rewrites the TXTR entries to point at 2x1 stub blobs
the gmloader-next texhack maps to those externals at runtime. Optionally
toggles GEN8 `InfoFlags` bits (Fullscreen / Scale / etc.) and recomputes the
GMS2RandomUID checksum in the same pass.

CMake-driven; single source tree builds for the device (aarch64 static binary,
glibc 2.27+ floor) and for PC use (Windows x64 .exe with the MSVC static
runtime). astc-encoder 4.8.0 and bzip2 1.0.8 are both fetched at configure
time (no vendored source in the repo).

## Build

### Windows x64 (MSVC)

From a Visual Studio Developer Command Prompt (any modern VS with the C++
workload + Ninja):

```bat
cmake -S . -B build-msvc -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-msvc
```

Produces `build-msvc/yyg_qoi_decode.exe`. The MSVC C/C++ runtime is statically
linked (`/MT`) so the binary has no VC++ redistributable dependency.

### aarch64 (cross-compile in Docker)

A Debian Bullseye container gives us the glibc 2.31 build floor; the final
binary only references symbols up to GLIBC_2.27, so it runs on every
supported device CFW.

```bash
docker run --rm -v "$PWD:/work" -w /work debian:bullseye bash -c '
  apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    g++-aarch64-linux-gnu cmake ninja-build git ca-certificates
  cmake -S . -B build-aarch64 -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=cmake/aarch64-linux-gnu.cmake \
        -DCMAKE_BUILD_TYPE=Release
  cmake --build build-aarch64
  aarch64-linux-gnu-strip build-aarch64/yyg_qoi_decode
'
```

Produces `build-aarch64/yyg_qoi_decode`. `libstdc++` / `libgcc` are statically
linked; glibc is left dynamic (the bullseye base keeps the symbol floor low).

Commit the resulting binary into the consuming port's `tools/yyg_qoi_decode`
(and the `.exe` alongside it for PC users).

## CLI

```
yyg_qoi_decode DATA.WIN OUT_DIR [opts]
  --block 4x4|5x5|6x6                  ASTC block size (default 4x4)
  --quality -fast|-medium|-thorough    astcenc preset (default -medium)
  --max-strip-pixels N                 tile w*h > N into strips (default 25000000)
  --threads N                          astcenc threads (default = nproc)
  --repack                             bin-pack TPIs into smaller atlases
  --page-size N                        atlas size when --repack (default 512)
  --max-dims N                         solo any TPI with w>N or h>N (default = page-size)
  --max-area N                         solo any TPI with w*h>N (default = page-size^2)
  --set-flags Name[,Name...]           set GEN8 InfoFlags bits (recomputes UID)
  --clear-flags Name[,Name...]         clear GEN8 InfoFlags bits (recomputes UID)

  flag names: Fullscreen SyncVertex1 SyncVertex2 Interpolate Scale
              ShowCursor Sizeable ScreenKey SyncVertex3 BorderlessWindow
```

Writes `<idx>.pvr` into `OUT_DIR`, compacts `DATA.WIN`'s TXTR chunk in place
(file size shrinks; FORM size updated; trailing chunks shifted up; file
truncated), and — if `--set-flags` / `--clear-flags` are given — flips the
GEN8 InfoFlags bits and recomputes the GMS2RandomUID checksum so UTMT and the
GMS2 runtime still accept the file.
