add_library(WhisPasteShell SHARED explorer_command.cpp exports.def)
target_compile_features(WhisPasteShell PRIVATE cxx_std_17)
target_compile_definitions(WhisPasteShell PRIVATE UNICODE _UNICODE)
target_compile_options(WhisPasteShell PRIVATE /W4 /WX /utf-8)
target_link_libraries(WhisPasteShell PRIVATE ole32 shlwapi uuid)
install(TARGETS WhisPasteShell RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
