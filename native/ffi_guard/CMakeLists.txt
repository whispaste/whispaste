# Builds wp_ffi_guard (see ffi_guard.h) against the pinned whisper.cpp
# headers. Only headers are needed — the guard never links whisper or ggml.
#   cmake -S native/ffi_guard -B <build> -DWHISPER_SOURCE_DIR=<whisper.cpp>
cmake_minimum_required(VERSION 3.14)
project(wp_ffi_guard CXX)

set(WHISPER_SOURCE_DIR "" CACHE PATH "whisper.cpp source tree (headers only)")
if(NOT EXISTS "${WHISPER_SOURCE_DIR}/include/whisper.h")
  message(FATAL_ERROR "WHISPER_SOURCE_DIR must point at a whisper.cpp checkout")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(wp_ffi_guard SHARED ffi_guard.cpp ffi_guard_selftest.cpp)
target_include_directories(wp_ffi_guard PRIVATE
  "${WHISPER_SOURCE_DIR}/include"
  "${WHISPER_SOURCE_DIR}/ggml/include")

if(MSVC)
  # Set per TU so an overridden CMAKE_CXX_FLAGS cannot drop them: the guard
  # needs /EHs without /EHc (see ffi_guard.cpp; /EHc- cancels the `c` of
  # CMake's default /EHsc), the self-test uses /EHsc like whisper/ggml/sherpa.
  set_source_files_properties(ffi_guard.cpp PROPERTIES
    COMPILE_OPTIONS "/EHs;/EHc-")
  set_source_files_properties(ffi_guard_selftest.cpp PROPERTIES
    COMPILE_OPTIONS "/EHsc")
else()
  target_compile_options(wp_ffi_guard PRIVATE -fexceptions)
  set_target_properties(wp_ffi_guard PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    INSTALL_NAME_DIR "@rpath"
    BUILD_WITH_INSTALL_NAME_DIR ON)
endif()
