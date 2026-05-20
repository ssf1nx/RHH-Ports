cmake_minimum_required(VERSION 3.18)
project(yyg_qoi_decode LANGUAGES C CXX)

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 99)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# ----------------------------------------------------------------------
# astc-encoder (FetchContent, statically linked into our binary)
# ----------------------------------------------------------------------
include(FetchContent)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "(aarch64|arm64|ARM64)")
    set(ASTCENC_ISA_NEON ON CACHE BOOL "" FORCE)
    set(YYG_ASTCENC_LIB astcenc-neon-static)
else()
    set(ASTCENC_ISA_AVX2 ON CACHE BOOL "" FORCE)
    set(YYG_ASTCENC_LIB astcenc-avx2-static)
endif()
set(ASTCENC_CLI OFF CACHE BOOL "" FORCE)
set(ASTCENC_SHAREDLIB OFF CACHE BOOL "" FORCE)
set(ASTCENC_UNITTEST OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    astcenc
    GIT_REPOSITORY https://github.com/ARM-software/astc-encoder.git
    GIT_TAG 4.8.0
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(astcenc)

FetchContent_Declare(
    bzip2_src
    URL https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
    URL_HASH SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
    SOURCE_SUBDIR _no_subdir_
)
FetchContent_MakeAvailable(bzip2_src)

add_library(yyg_bzip2 STATIC
    ${bzip2_src_SOURCE_DIR}/blocksort.c
    ${bzip2_src_SOURCE_DIR}/bzlib.c
    ${bzip2_src_SOURCE_DIR}/compress.c
    ${bzip2_src_SOURCE_DIR}/crctable.c
    ${bzip2_src_SOURCE_DIR}/decompress.c
    ${bzip2_src_SOURCE_DIR}/huffman.c
    ${bzip2_src_SOURCE_DIR}/randtable.c
)
target_include_directories(yyg_bzip2 PUBLIC ${bzip2_src_SOURCE_DIR})
if(MSVC)
    target_compile_definitions(yyg_bzip2 PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(yyg_bzip2 PRIVATE
        /wd4018 /wd4146 /wd4244 /wd4267 /wd4996)
else()
    target_compile_options(yyg_bzip2 PRIVATE
        -Wno-implicit-function-declaration
        -Wno-unused-but-set-variable
        -Wno-unused-parameter
        -Wno-unused-variable
        -O2)
endif()

# ----------------------------------------------------------------------
# Main executable
# ----------------------------------------------------------------------
add_executable(yyg_qoi_decode yyg_qoi_decode.cpp)
target_link_libraries(yyg_qoi_decode PRIVATE ${YYG_ASTCENC_LIB} yyg_bzip2)

if(MSVC)
    target_compile_definitions(yyg_qoi_decode PRIVATE
        _CRT_SECURE_NO_WARNINGS
        NOMINMAX)
    target_compile_options(yyg_qoi_decode PRIVATE /W3 /O2)
else()
    target_compile_options(yyg_qoi_decode PRIVATE -O2 -Wall -Wextra)
    find_package(Threads REQUIRED)
    target_link_libraries(yyg_qoi_decode PRIVATE Threads::Threads)
    if(NOT APPLE)
        target_link_options(yyg_qoi_decode PRIVATE
            -static-libstdc++ -static-libgcc)
    endif()
endif()

install(TARGETS yyg_qoi_decode RUNTIME DESTINATION bin)
