# Build once, then ship the same audio-only helper and corresponding source
# in every desktop bundle. It is never linked to or loaded by the runner.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(WP_VIDEO_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
if(WIN32)
  set(WP_VIDEO_PLATFORM windows)
  # CMAKE_CXX_COMPILER is .../VC/Tools/MSVC/<version>/bin/Hostx64/x64/cl.exe.
  string(REGEX REPLACE "/Tools/MSVC/.*$" "/Auxiliary/Build/vcvars64.bat"
    WP_VIDEO_VCVARS "${CMAKE_CXX_COMPILER}")
  set(WP_VIDEO_ARGS --vcvars "${WP_VIDEO_VCVARS}")
else()
  set(WP_VIDEO_PLATFORM linux)
endif()
set(WP_VIDEO_STAGE "${WP_VIDEO_ROOT}/.build/video-decoder/${WP_VIDEO_PLATFORM}")
add_custom_target(wp_video_decoder ALL
  COMMAND "${Python3_EXECUTABLE}" "${WP_VIDEO_ROOT}/scripts/build-video-decoder.py"
    --platform "${WP_VIDEO_PLATFORM}" ${WP_VIDEO_ARGS}
  COMMENT "Building local video audio decoder (cached)"
  VERBATIM)
add_dependencies(${BINARY_NAME} wp_video_decoder)
install(DIRECTORY "${WP_VIDEO_STAGE}/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/video-decoder"
  USE_SOURCE_PERMISSIONS
  COMPONENT Runtime
  PATTERN "stamp" EXCLUDE)
