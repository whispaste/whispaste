# Ogg/Opus decoding for the Windows runner (WP-35b). libogg, libopus and
# opusfile are BSD-3-Clause (Xiph.org). Their release tarballs are pinned by
# SHA-256 and linked statically into whispaste.exe. Media Foundation has no Ogg
# demuxer, so opusfile does the container and Opus decoding.
#
# None of these projects is added with add_subdirectory(). Their install rules
# would land in the bundle's install script, whose prefix is a generator
# expression ($<TARGET_FILE_DIR:...>) that the install step cannot create. libogg
# and opusfile are compiled from their sources here; libopus is built by
# ExternalProject, which runs no install step.

include(FetchContent)
include(ExternalProject)

FetchContent_Declare(whispaste_libogg
  URL https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.gz
  URL_HASH SHA256=83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638
)
FetchContent_Declare(whispaste_opusfile
  URL https://downloads.xiph.org/releases/opus/opusfile-0.12.tar.gz
  URL_HASH SHA256=118d8601c12dd6a44f52423e68ca9083cc9f2bfe72da7a8c1acb22a80ae3550b
)
FetchContent_Populate(whispaste_libogg)
FetchContent_Populate(whispaste_opusfile)

# libogg: framing and bitwise, compiled from source with the checked-in MSVC
# config_types.h (ogg_config/).
add_library(whispaste_ogg STATIC
  "${whispaste_libogg_SOURCE_DIR}/src/bitwise.c"
  "${whispaste_libogg_SOURCE_DIR}/src/framing.c"
)
target_include_directories(whispaste_ogg PUBLIC
  "${whispaste_libogg_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/ogg_config"
)

# libopus: built by its own CMake project. INSTALL_COMMAND is empty, so the
# static library stays in the build tree and is only linked from there.
set(WP_OPUS_SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/opus-src")
set(WP_OPUS_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/opus-build")
set(WP_OPUS_LIBRARY "${WP_OPUS_BINARY_DIR}/Release/opus.lib")
ExternalProject_Add(whispaste_libopus_ext
  URL https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
  URL_HASH SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SOURCE_DIR "${WP_OPUS_SOURCE_DIR}"
  BINARY_DIR "${WP_OPUS_BINARY_DIR}"
  CMAKE_ARGS
    -DOPUS_BUILD_PROGRAMS=OFF
    -DOPUS_BUILD_TESTING=OFF
    -DOPUS_BUILD_SHARED_LIBRARY=OFF
  BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --config Release --target opus
  INSTALL_COMMAND ""
  BUILD_BYPRODUCTS "${WP_OPUS_LIBRARY}"
)

add_library(whispaste_libopus STATIC IMPORTED GLOBAL)
# Imported targets must have existing include directories at configure time,
# and the Opus sources only appear at build time, so the include path goes on
# whispaste_opusfile below.
set_target_properties(whispaste_libopus PROPERTIES
  IMPORTED_LOCATION "${WP_OPUS_LIBRARY}"
)

# opusfile has no build system of its own; its four sources are compiled as in
# the earlier setup (every src/*.c except http.c and wincerts.c).
add_library(whispaste_opusfile STATIC
  "${whispaste_opusfile_SOURCE_DIR}/src/info.c"
  "${whispaste_opusfile_SOURCE_DIR}/src/internal.c"
  "${whispaste_opusfile_SOURCE_DIR}/src/opusfile.c"
  "${whispaste_opusfile_SOURCE_DIR}/src/stream.c"
)
target_include_directories(whispaste_opusfile
  PUBLIC "${whispaste_opusfile_SOURCE_DIR}/include" "${WP_OPUS_SOURCE_DIR}/include"
  PRIVATE "${whispaste_opusfile_SOURCE_DIR}/src"
)
target_compile_definitions(whispaste_opusfile PRIVATE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(whispaste_opusfile PUBLIC whispaste_ogg whispaste_libopus)
add_dependencies(whispaste_opusfile whispaste_libopus_ext)
