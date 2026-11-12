# Bundled zstd

set(ZSTD_VERSION "1.5.7")
FetchContent_Declare(zstd
    GIT_REPOSITORY https://github.com/facebook/zstd.git
    GIT_TAG v${ZSTD_VERSION}
    SOURCE_SUBDIR build/cmake
    ${USE_OVERRIDE_FIND_PACKAGE}
)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_DICTBUILDER OFF CACHE BOOL "" FORCE)
FetchContent_GetProperties(zstd)
if(NOT zstd_POPULATED)
    FetchContent_Populate(zstd)
    add_subdirectory(${zstd_SOURCE_DIR}/build/cmake ${zstd_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

# Decoder window limit.
#
# A zstd streaming decoder refuses, by default, any frame that needs a window
# larger than 128 MiB (2^27, ZSTD_WINDOWLOG_LIMIT_DEFAULT) with
#   "Frame requires too much memory for decoding".
# EVE-OS release images are compressed with "zstd --long=30" (1 GiB window,
# see .github/workflows/assets.yml in lf-edge/eve), so writing them failed.
# libarchive, which does the decompression, offers no option to raise the
# limit, so raise zstd's built-in default instead, to the format maximum on
# 64-bit (2^31; the "+ 1" mirrors zstd's own definition of this macro).
#
# This is only an upper bound on what is accepted: the decoder allocates what
# the frame actually asks for, i.e. up to ~1 GiB of RAM while an EVE image is
# being written, and nothing extra for ordinary frames.
if (TARGET libzstd_static)
    target_compile_definitions(libzstd_static PRIVATE ZSTD_MAXWINDOWSIZE_DEFAULT=2147483649ULL)
endif()
unset(ZSTD_BUILD_PROGRAMS)
unset(ZSTD_BUILD_SHARED)
unset(ZSTD_BUILD_STATIC)
unset(ZSTD_BUILD_TESTS)
unset(ZSTD_BUILD_DICTBUILDER)
set(ZSTD_FOUND true CACHE BOOL "" FORCE)
set(Zstd_VERSION ${ZSTD_VERSION} CACHE STRING "" FORCE)
set(Zstd_INCLUDE_DIR ${CMAKE_CURRENT_BINARY_DIR}/_deps/zstd-src/lib CACHE PATH "" FORCE)
set(ZSTD_INCLUDE_DIR ${CMAKE_CURRENT_BINARY_DIR}/_deps/zstd-src/lib CACHE PATH "" FORCE)
set(Zstd_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/_deps/zstd-src/lib CACHE PATH "" FORCE)
set(ZSTD_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/_deps/zstd-src/lib CACHE PATH "" FORCE)
set(Zstd_LIBRARIES libzstd_static CACHE FILEPATH "" FORCE)
set(ZSTD_LIBRARIES libzstd_static CACHE FILEPATH "" FORCE)
set(ZSTD_LIBRARY ${CMAKE_CURRENT_BINARY_DIR}/_deps/zstd-build/lib/libzstd.a CACHE FILEPATH "" FORCE)


