# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "whispaste")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "de.whispaste.app")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Debug and Profile builds run under their own application ID, so their
# desktop entry and portal registration never replace an installed release's
# (the Dart side keeps their data apart in the same way, see isLocalBuild).
if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")
  set(APPLICATION_ID "${APPLICATION_ID}.dev")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  # -Werror dropped: this function is applied to bundled plugins too (see note
  # above), and third-party plugin sources (e.g. flutter_soloud's vendored
  # SoLoud) emit warnings under the CI clang that would otherwise fail the
  # Linux build. Keep -Wall for visibility without turning warnings fatal.
  target_compile_options(${TARGET} PRIVATE -Wall)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
# gtk+-3.0's own pkg-config Libs never includes -lX11 (verified: `pkg-config --libs
# gtk+-3.0` omits it even though gdk-x11-3.0 is a private/transitive dependency) —
# needed explicitly for runner/snippet_picker_host.cc's direct Xlib calls
# (XGetInputFocus/XSetInputFocus, visual-refresh-2026 ticket 30).
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
# XInput2 raw key events for the Linux push-to-talk key-up
# (runner/keyboard_monitor_host.cc, catchup/09). libxi-dev is already a
# dependency of libgtk-3-dev, so this adds no new build requirement.
pkg_check_modules(XI REQUIRED IMPORTED_TARGET xi)
pkg_check_modules(XSS IMPORTED_TARGET xscrnsaver)
# Without XScreenSaver the undo gate has no idle source: every input then
# counts as typing (fail-safe), so the build must say so instead of quietly
# losing the feature. Install libxss-dev to enable it.
if(NOT XSS_FOUND)
  message(WARNING "libxss-dev (xscrnsaver) not found: the Linux undo idle gate is disabled and any input counts as typing. Install libxss-dev.")
endif()

# Optional: libei headers for the portal keyboard (RemoteDesktop + EIS, see
# runner/portal_remote_desktop.cc). libei.so.1 is dlopen()ed at run time, so
# only the headers are a build dependency and the binary has no libei link.
# Without them the portal path reports unavailable and uinput stays the path.
pkg_check_modules(LIBEI IMPORTED_TARGET libei-1.0)
if(NOT LIBEI_FOUND)
  message(WARNING "libei-dev (libei-1.0) not found: the portal keyboard input (RemoteDesktop/EIS) is disabled. Install libei-dev to enable it.")
endif()
# Decoders for imported audio files (WP-35b, runner/audio_file_decode_core.cc):
# libopusfile for Ogg/Opus, libFLAC for FLAC. MP3 uses the vendored minimp3.
pkg_check_modules(OPUSFILE REQUIRED IMPORTED_TARGET opusfile)
pkg_check_modules(FLAC REQUIRED IMPORTED_TARGET flac)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# sherpa-onnx without TTS. The sherpa_onnx pub plugin bundles a prebuilt C API
# that statically contains espeak-ng (GPL-3.0-or-later). Swap it and its
# onnxruntime for the TTS-free build staged by scripts/build-sherpa-onnx.sh.
# A missing stage is only a warning here: release.yml stages it before building
# and scripts/check-no-espeak.sh fails the release if the pub original ships.
set(WP_SHERPA_STAGE "${CMAKE_CURRENT_SOURCE_DIR}/../.build/sherpa-onnx/linux")
file(GLOB WP_SHERPA_LIBS
  "${WP_SHERPA_STAGE}/libsherpa-onnx-c-api.so*"
  "${WP_SHERPA_STAGE}/libonnxruntime.so*")
if(WP_SHERPA_LIBS)
  # A stale stage (pin or pubspec.lock moved without a rebuild) fails here.
  include("${CMAKE_CURRENT_SOURCE_DIR}/../scripts/check-sherpa-stage.cmake")
  wp_check_sherpa_stage("${WP_SHERPA_STAGE}" "${CMAKE_CURRENT_SOURCE_DIR}/..")
  list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX "/lib(sherpa-onnx-c-api|onnxruntime)\\.so")
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${WP_SHERPA_LIBS})
else()
  message(WARNING "sherpa-onnx TTS-free build not staged in ${WP_SHERPA_STAGE}: bundling the pub original (contains espeak-ng). Run: bash scripts/build-sherpa-onnx.sh linux")
endif()

# On-device Whisper: libwhisper.so, the libggml* backends and libwp_ffi_guard.so
# staged by scripts/build-libwhisper-linux.sh. Bundled here so every
# `flutter build linux` (debug too) ships them; the install step wipes the
# bundle first, so copying them in beforehand does not survive. A missing
# stage is only a warning, like the macOS embed phase.
set(WP_WHISPER_STAGE "${CMAKE_CURRENT_SOURCE_DIR}/../.build/libwhisper/linux")
file(GLOB WP_WHISPER_LIBS "${WP_WHISPER_STAGE}/*.so*")
if(WP_WHISPER_LIBS)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${WP_WHISPER_LIBS})
else()
  message(WARNING "libwhisper not staged in ${WP_WHISPER_STAGE}: on-device Whisper is missing from the bundle. Run: bash scripts/build-libwhisper-linux.sh")
endif()


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Silero-VAD model, looked up next to libwhisper.so (whisperVadModelPathFor).
# Vendored in the repo, so it needs no stage.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../assets/models/vad/ggml-silero-v5.1.2.bin"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# On-device Smart Mode: libsmartmode_shim.so, libllama and its own ggml,
# staged by scripts/build-libllama-linux.sh. They go into lib/smart_mode/ so
# ggml's backend scan never mixes them with libwhisper's (see that script).
set(WP_LLAMA_STAGE "${CMAKE_CURRENT_SOURCE_DIR}/../.build/libllama/linux")
file(GLOB WP_LLAMA_LIBS "${WP_LLAMA_STAGE}/*.so*")
if(WP_LLAMA_LIBS)
  install(FILES ${WP_LLAMA_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/smart_mode"
    COMPONENT Runtime)
else()
  message(WARNING "libllama not staged in ${WP_LLAMA_STAGE}: on-device Smart Mode is missing from the bundle. Run: bash scripts/build-libllama-linux.sh")
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
