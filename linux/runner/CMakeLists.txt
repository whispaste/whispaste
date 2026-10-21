cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "floating_overlay_window.cc"
  "floating_overlay_host.cc"
  "floating_button_window.cc"
  "floating_button_host.cc"
  "window_drag_mover.cc"
  "clipboard_hint.cc"
  "clipboard_receipt.cc"
  "x11_window.cc"
  "desktop_paste_host.cc"
  "eis_keyboard_sender.cc"
  "portal_remote_desktop.cc"
  "audio_file_decode_core.cc"
  "audio_file_decode_gst.cc"
  "audio_file_decode_host.cc"
  "snippet_picker_window.cc"
  "snippet_picker_host.cc"
  "secondary_plugin_registrant.cc"
  "side_panel_window.cc"
  "side_panel_host.cc"
  "keyboard_monitor_host.cc"
  "desktop_entry_installer.cc"
  "power_event_host.cc"
  "file_dialog_host.cc"
  "xvfb_launcher.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
# App version for the runner's own `--diagnose` report (diagnose_launch.h).
add_definitions(-DWHISPASTE_VERSION="${FLUTTER_VERSION_MAJOR}.${FLUTTER_VERSION_MINOR}.${FLUTTER_VERSION_PATCH}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::XI)
# Optional: XScreenSaver idle time for the undo gate (DEV-232). Only the headers
# are needed at build time: libXss.so.1 is dlopen()ed at run time, so the binary
# still starts without libxss1, and inputIdleSnapshot answers null there.
if(XSS_FOUND)
  target_include_directories(${BINARY_NAME} PRIVATE ${XSS_INCLUDE_DIRS})
  target_compile_definitions(${BINARY_NAME} PRIVATE WHISPASTE_HAVE_XSS=1)
endif()
# Optional: libei headers for the portal keyboard path (see linux/CMakeLists.txt).
if(LIBEI_FOUND)
  target_include_directories(${BINARY_NAME} PRIVATE ${LIBEI_INCLUDE_DIRS})
  target_compile_definitions(${BINARY_NAME} PRIVATE WHISPASTE_HAVE_LIBEI=1)
endif()
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::OPUSFILE)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::FLAC)
target_link_libraries(${BINARY_NAME} PRIVATE ${CMAKE_DL_LIBS})

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
