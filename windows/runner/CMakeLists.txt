cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "attention_host.cpp"
  "clipboard_monitor_host.cpp"
  "desktop_paste_host.cpp"
  "audio_file_decode_host.cpp"
  "audio_file_decode_mf.cpp"
  "../../linux/runner/audio_file_decode_core.cc"
  "../../linux/runner/mp4_gapless.cc"
  "flutter_window.cpp"
  "floating_button_host.cpp"
  "floating_button_window.cpp"
  "floating_overlay_host.cpp"
  "floating_overlay_window.cpp"
  "gdiplus_helper.cpp"
  "keyboard_monitor_host.cpp"
  "main.cpp"
  "power_event_host.cpp"
  "side_panel_host.cpp"
  "side_panel_window.cpp"
  "snippet_picker_host.cpp"
  "snippet_picker_window.cpp"
  "store_review_channel.cpp"
  "support_store_channel.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Release builds also emit a PDB so Partner Center (.msixupload) and Sentry
# can symbolicate native crash frames in whispaste.exe. /DEBUG alone would
# switch the linker to /OPT:NOREF, so REF/ICF are restored explicitly. The PDB
# goes to symbols/ next to the runner build dir, not into the Release bundle
# dir: everything there ships as-is (portable ZIP, NSIS, MSIX).
# /PDBALTPATH records only the file name in the exe instead of the absolute
# build path. Spelled out instead of the linker's %_PDB% macro: the VS
# generator escapes % so the exe would name "%%%whispaste.pdb%%%", which
# symbol servers would never match against the uploaded whispaste.pdb.
set(WHISPASTE_SYMBOLS_DIR "${CMAKE_BINARY_DIR}/symbols")
file(MAKE_DIRECTORY "${WHISPASTE_SYMBOLS_DIR}")
target_compile_options(${BINARY_NAME} PRIVATE "$<$<CONFIG:Release>:/Zi>")
target_link_options(${BINARY_NAME} PRIVATE
  "$<$<CONFIG:Release>:/DEBUG>"
  "$<$<CONFIG:Release>:/OPT:REF>"
  "$<$<CONFIG:Release>:/OPT:ICF>"
  "$<$<CONFIG:Release>:/PDB:${WHISPASTE_SYMBOLS_DIR}/${BINARY_NAME}.pdb>"
  "$<$<CONFIG:Release>:/PDBALTPATH:${BINARY_NAME}.pdb>"
)

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Shared Linux/Windows decoder core (Ogg/Opus and MP3). FLAC stays with Media
# Foundation on Windows, so the core is built without libFLAC.
target_compile_definitions(${BINARY_NAME} PRIVATE "WP_WITH_FLAC=0")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../linux/runner")

# C++/WinRT (support_store_channel.cpp) needs C++20 coroutines; under C++17 it
# falls back to <experimental/coroutine>, which current MSVC toolsets reject.
target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
include("${CMAKE_CURRENT_SOURCE_DIR}/opus_audio.cmake")
target_link_libraries(${BINARY_NAME} PRIVATE whispaste_opusfile)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "gdiplus.lib" "dwrite.lib" "comctl32.lib" "ole32.lib" "windowsapp.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Copy the dedicated tray icon next to the executable for dev runs.
set(TRAY_ICON_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../resources/tray.ico")
if(EXISTS "${TRAY_ICON_SOURCE}")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>/resources"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${TRAY_ICON_SOURCE}"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/resources/tray.ico"
  )
else()
  message(WARNING "WhisPaste: tray icon not found at ${TRAY_ICON_SOURCE}")
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
