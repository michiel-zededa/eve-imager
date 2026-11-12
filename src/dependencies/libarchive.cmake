# Bundled libarchive configured for static zlib and zstd

set(ENABLE_WERROR OFF CACHE BOOL "")
set(ENABLE_INSTALL OFF CACHE BOOL "")
set(ENABLE_TEST OFF CACHE BOOL "")
set(ENABLE_CNG OFF CACHE BOOL "")
set(ENABLE_MBEDTLS OFF CACHE BOOL "")
set(ENABLE_NETTLE OFF CACHE BOOL "")
set(ENABLE_OPENSSL OFF CACHE BOOL "")
set(ENABLE_ZLIB ON CACHE BOOL "")
set(ENABLE_BZip2 OFF CACHE BOOL "")
set(ENABLE_LZ4 OFF CACHE BOOL "")
set(ENABLE_LZO OFF CACHE BOOL "")
set(ENABLE_LIBB2 OFF CACHE BOOL "")
set(ENABLE_LIBXML2 OFF CACHE BOOL "")
set(ENABLE_EXPAT OFF CACHE BOOL "")
set(ENABLE_PCREPOSIX OFF CACHE BOOL "")
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "")
set(ENABLE_LIBGCC OFF CACHE BOOL "")
set(ENABLE_TAR OFF CACHE BOOL "")
set(ENABLE_CPIO OFF CACHE BOOL "")
set(ENABLE_CAT OFF CACHE BOOL "")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
set(ARCHIVE_BUILD_STATIC_LIBS ON CACHE BOOL "")
set(ARCHIVE_BUILD_EXAMPLES OFF CACHE BOOL "")
set(ENABLE_ZSTD ON CACHE BOOL "")
set(POSIX_REGEX_LIB "libc" CACHE STRING "" FORCE)
set(LIBARCHIVE_VERSION "3.8.6")

# zstd support.
#
# libarchive decides whether it can call libzstd directly by link-testing
# ZSTD_decompressStream & co. against ${ZSTD_LIBRARY} at configure time
# (CHECK_FUNCTION_EXISTS). Our zstd is the bundled one, which has not been
# built yet when libarchive is configured, so that link test always fails.
# libarchive then still accepts zstd input, but by spawning an external
# "zstd -d -qq" program - which does not exist on end-user machines, so
# writing a .zst image failed with:
#   "Can't initialize filter; unable to run program "zstd -d -qq""
#
# The bundled zstd (see zstd.cmake) is known to provide these functions, so
# answer the checks up front; CHECK_FUNCTION_EXISTS skips a result that is
# already in the cache. INTERNAL implies FORCE, which also repairs build
# directories that cached the failed result.
set(HAVE_LIBZSTD 1 CACHE INTERNAL "bundled zstd provides ZSTD_decompressStream")
set(HAVE_ZSTD_compressStream 1 CACHE INTERNAL "bundled zstd provides ZSTD_compressStream")
set(HAVE_ZSTD_minCLevel 1 CACHE INTERNAL "bundled zstd provides ZSTD_minCLevel")

FetchContent_Declare(libarchive
    GIT_REPOSITORY https://github.com/libarchive/libarchive.git
    GIT_TAG v${LIBARCHIVE_VERSION}
    ${USE_OVERRIDE_FIND_PACKAGE}
)
FetchContent_GetProperties(libarchive)
if(NOT libarchive_POPULATED)
    FetchContent_Populate(libarchive)
    add_subdirectory(${libarchive_SOURCE_DIR} ${libarchive_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

if (TARGET archive_static AND TARGET ZLIB::ZLIB)
    add_dependencies(archive_static ZLIB::ZLIB)
endif()
if (TARGET archive_static AND TARGET libzstd_static)
    add_dependencies(archive_static libzstd_static)
endif()

unset(POSIX_REGEX_LIB)
unset(ENABLE_WERROR)
unset(ENABLE_INSTALL)
unset(ENABLE_TEST)
unset(ENABLE_CNG)
unset(ENABLE_MBEDTLS)
unset(ENABLE_NETTLE)
unset(ENABLE_OPENSSL)
unset(ENABLE_ZLIB)
unset(ENABLE_BZip2)
unset(ENABLE_LZ4)
unset(ENABLE_LZO)
unset(ENABLE_LIBB2)
unset(ENABLE_LIBXML2)
unset(ENABLE_EXPAT)
unset(ENABLE_PCREPOSIX)
unset(ENABLE_PCRE2POSIX)
unset(ENABLE_LIBGCC)
unset(ENABLE_TAR)
unset(ENABLE_CPIO)
unset(ENABLE_CAT)
unset(ARCHIVE_BUILD_STATIC_LIBS)
unset(ENABLE_ZSTD)
set(LibArchive_FOUND true CACHE BOOL "" FORCE)
set(LibArchive_LIBRARIES archive_static CACHE FILEPATH "" FORCE)
set(LibArchive_INCLUDE_DIR ${libarchive_SOURCE_DIR}/libarchive CACHE PATH "" FORCE)
set(LibArchive_INCLUDE_DIRS ${libarchive_SOURCE_DIR}/libarchive CACHE PATH "" FORCE)


