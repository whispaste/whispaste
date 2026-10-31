# check-sherpa-stage.cmake — refuses a staged sherpa-onnx that does not match
# the pins. A stale stage (sherpa_onnx bumped in pubspec.lock, or the pin moved,
# without a rebuild) would otherwise be embedded silently and load with a
# mismatched ABI.
#
# Checks: BUILD_INFO names the tag and commit of scripts/sherpa-onnx.pin, the
# tag's version equals the sherpa_onnx version in pubspec.lock, and the C API
# library is present.
#
# GS-013 (reference only): SHERPA_C_API_SHA256_<PLATFORM> in scripts/sherpa-onnx.pin
# is compared as a warning. The build is reproducible within one checkout path but
# not across checkout paths (ThinLTO bitcode embeds the object path), so a hash
# mismatch is not a release gate. See BUILD.md, residual risk GS-013.
#
# CRLF line endings (Windows checkouts, Set-Content) are accepted.
#
# Script mode (every consumer that has cmake, including the macOS embed phase):
#   cmake -DSTAGE_DIR=<dir> -DREPO_ROOT=<repo> -P scripts/check-sherpa-stage.cmake
# Include mode (Linux/Windows CMake projects):
#   include(<repo>/scripts/check-sherpa-stage.cmake)
#   wp_check_sherpa_stage(<stage_dir> <repo_root>)

function(wp_check_sherpa_stage stage_dir repo_root)
  set(pin_file "${repo_root}/scripts/sherpa-onnx.pin")
  if(NOT EXISTS "${pin_file}")
    message(FATAL_ERROR "sherpa-onnx check: pin file missing: ${pin_file}")
  endif()
  file(STRINGS "${pin_file}" pin_lines)
  foreach(line IN LISTS pin_lines)
    if(line MATCHES "^SHERPA_TAG=(v[0-9.]+)\r?$")
      set(pin_tag "${CMAKE_MATCH_1}")
    elseif(line MATCHES "^SHERPA_COMMIT=([0-9a-f]+)\r?$")
      set(pin_commit "${CMAKE_MATCH_1}")
    elseif(line MATCHES "^SHERPA_C_API_SHA256_([A-Z0-9_]+)=([0-9a-f]*)\r?$")
      set(pin_sha_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
    endif()
  endforeach()
  if(NOT pin_tag OR NOT pin_commit)
    message(FATAL_ERROR "sherpa-onnx check: ${pin_file} must define SHERPA_TAG and SHERPA_COMMIT")
  endif()

  set(lock_file "${repo_root}/pubspec.lock")
  if(NOT EXISTS "${lock_file}")
    message(FATAL_ERROR "sherpa-onnx check: pubspec.lock missing: ${lock_file}")
  endif()
  file(STRINGS "${lock_file}" lock_lines)
  set(in_package FALSE)
  set(lock_version "")
  foreach(line IN LISTS lock_lines)
    if(line MATCHES "^  [^ ].*:$")
      if(line STREQUAL "  sherpa_onnx:")
        set(in_package TRUE)
      else()
        set(in_package FALSE)
      endif()
    elseif(in_package AND line MATCHES "^    version: \"(.+)\"\r?$")
      set(lock_version "${CMAKE_MATCH_1}")
    endif()
  endforeach()
  if(lock_version STREQUAL "")
    message(FATAL_ERROR "sherpa-onnx check: no sherpa_onnx version in ${lock_file}")
  endif()

  set(info_file "${stage_dir}/BUILD_INFO")
  if(NOT EXISTS "${info_file}")
    message(FATAL_ERROR "sherpa-onnx check: ${info_file} missing. Rebuild the stage with scripts/build-sherpa-onnx.sh or .ps1.")
  endif()
  file(STRINGS "${info_file}" info_lines)
  set(stage_tag "")
  set(stage_commit "")
  foreach(line IN LISTS info_lines)
    if(line MATCHES "^sherpa-onnx (v[0-9.]+) \\(([0-9a-f]+)\\)\r?$")
      set(stage_tag "${CMAKE_MATCH_1}")
      set(stage_commit "${CMAKE_MATCH_2}")
      break()
    endif()
  endforeach()
  if(stage_tag STREQUAL "")
    message(FATAL_ERROR "sherpa-onnx check: no 'sherpa-onnx <tag> (<commit>)' line in ${info_file}")
  endif()

  string(REGEX REPLACE "^v" "" pin_version "${pin_tag}")
  set(problems "")

  # GS-013 platform key from the staged library name (and host arch on Linux).
  file(GLOB c_api_libs
    "${stage_dir}/libsherpa-onnx-c-api.dylib"
    "${stage_dir}/libsherpa-onnx-c-api.so*"
    "${stage_dir}/sherpa-onnx-c-api.dll")
  if(NOT c_api_libs)
    message(FATAL_ERROR "sherpa-onnx check: no sherpa-onnx C API library in ${stage_dir}")
  endif()
  list(GET c_api_libs 0 c_api_lib)
  get_filename_component(c_api_name "${c_api_lib}" NAME)
  if(c_api_name MATCHES "\\.dylib$")
    set(pin_key "MACOS")
  elseif(c_api_name MATCHES "\\.dll$")
    set(pin_key "WINDOWS_X64")
  elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(pin_key "LINUX_AARCH64")
  else()
    set(pin_key "LINUX_X64")
  endif()
  set(pin_sha "${pin_sha_${pin_key}}")
  file(SHA256 "${c_api_lib}" c_api_sha)
  if(pin_sha STREQUAL "")
    message(STATUS "sherpa-onnx: no repo pin for ${pin_key} (reference only)")
  elseif(NOT c_api_sha STREQUAL pin_sha)
    message(WARNING "sherpa-onnx: ${c_api_name} sha256 ${c_api_sha} differs from the reference pin ${pin_sha} (SHERPA_C_API_SHA256_${pin_key}). Expected when the checkout path differs; see BUILD.md (GS-013).")
  endif()
  if(NOT stage_commit STREQUAL pin_commit)
    string(APPEND problems "  - stage commit ${stage_commit} != pinned ${pin_commit} (${pin_tag})\n")
  endif()
  if(NOT stage_tag STREQUAL pin_tag)
    string(APPEND problems "  - stage tag ${stage_tag} != pinned ${pin_tag}\n")
  endif()
  if(NOT lock_version STREQUAL pin_version)
    string(APPEND problems "  - pubspec.lock sherpa_onnx ${lock_version} != pinned ${pin_version}\n")
  endif()
  # GS-007: every staged file must carry the SHA-256 recorded at build time, so a
  # library changed after staging (or an unlisted file) fails the build.
  file(GLOB staged_files RELATIVE "${stage_dir}" "${stage_dir}/*")
  foreach(name IN LISTS staged_files)
    if(name STREQUAL "BUILD_INFO")
      continue()
    endif()
    set(recorded "")
    foreach(line IN LISTS info_lines)
      if(line MATCHES "^sha256 ([^ ]+) ([0-9a-f]+)\r?$")
        if("${CMAKE_MATCH_1}" STREQUAL "${name}")
          set(recorded "${CMAKE_MATCH_2}")
        endif()
      endif()
    endforeach()
    if(recorded STREQUAL "")
      string(APPEND problems "  - ${name} has no sha256 line in BUILD_INFO\n")
    else()
      file(SHA256 "${stage_dir}/${name}" actual)
      if(NOT actual STREQUAL recorded)
        string(APPEND problems "  - ${name} changed after staging: sha256 ${actual}, recorded ${recorded}\n")
      endif()
    endif()
  endforeach()

  if(problems)
    message(FATAL_ERROR "sherpa-onnx check FAILED for ${stage_dir}:\n${problems}Rebuild the stage (scripts/build-sherpa-onnx.sh or .ps1) after changing the pin or pubspec.lock.")
  endif()

  message(STATUS "sherpa-onnx stage OK: ${stage_tag} (${stage_commit}), matches pubspec.lock ${lock_version}")
endfunction()

if(CMAKE_SCRIPT_MODE_FILE)
  if(NOT DEFINED STAGE_DIR OR NOT DEFINED REPO_ROOT)
    message(FATAL_ERROR "usage: cmake -DSTAGE_DIR=<dir> -DREPO_ROOT=<repo> -P check-sherpa-stage.cmake")
  endif()
  wp_check_sherpa_stage("${STAGE_DIR}" "${REPO_ROOT}")
endif()
