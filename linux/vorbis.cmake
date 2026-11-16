# SoLoud's prebuilt Vorbis uses full-version SONAMEs, unlike the system audio
# stack. Give private build-tree copies the standard ABI names so both users
# share one loaded object (#94). Never modify the shared pub cache.
find_program(WP_PATCHELF patchelf)
if(NOT WP_PATCHELF)
  message(FATAL_ERROR "patchelf is required to normalize the bundled Vorbis SONAMEs (install patchelf).")
endif()

set(WP_VORBIS_DIR "${CMAKE_CURRENT_BINARY_DIR}/vorbis")
file(MAKE_DIRECTORY "${WP_VORBIS_DIR}")
foreach(pair "libvorbis.so.0.4.9|libvorbis.so.0" "libvorbisfile.so.3.3.8|libvorbisfile.so.3")
  string(REPLACE "|" ";" names "${pair}")
  list(GET names 0 original)
  list(GET names 1 soname)
  configure_file("${WP_SOLOUD_LINUX}/libs/${original}"
    "${WP_VORBIS_DIR}/${soname}" COPYONLY)
  execute_process(COMMAND "${WP_PATCHELF}" --set-soname "${soname}"
    --set-rpath "$ORIGIN"
    --replace-needed libvorbis.so.0.4.9 libvorbis.so.0
    "${WP_VORBIS_DIR}/${soname}" RESULT_VARIABLE result)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Could not normalize ${original}: patchelf returned ${result}")
  endif()
endforeach()

# Relink the plugin against the normalized copies, so its NEEDED entries use
# the same ABI names too. Fail closed if the upstream link layout changes.
get_target_property(WP_SOLOUD_LINKS flutter_soloud_plugin LINK_LIBRARIES)
foreach(name vorbis vorbisfile)
  set(found FALSE)
  set(relinked "")
  foreach(link IN LISTS WP_SOLOUD_LINKS)
    if(link MATCHES "/lib${name}\\.so$")
      if(name STREQUAL "vorbis")
        list(APPEND relinked "${WP_VORBIS_DIR}/libvorbis.so.0")
      else()
        list(APPEND relinked "${WP_VORBIS_DIR}/libvorbisfile.so.3")
      endif()
      set(found TRUE)
    else()
      list(APPEND relinked "${link}")
    endif()
  endforeach()
  if(NOT found)
    message(FATAL_ERROR "SoLoud's ${name} link changed: update linux/vorbis.cmake.")
  endif()
  set(WP_SOLOUD_LINKS "${relinked}")
endforeach()
set_property(TARGET flutter_soloud_plugin PROPERTY LINK_LIBRARIES "${WP_SOLOUD_LINKS}")
