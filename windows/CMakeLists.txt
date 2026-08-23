cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "torrserver_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "torrserver_flutter_plugin")

add_library(${PLUGIN_NAME} SHARED
  "torrserver_flutter_plugin.cpp"
  "torrserver_flutter_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET "hidden"
  VISIBILITY_INLINES_HIDDEN 1
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# --- TorrServer Native Binary Setup ---
set(TORRSERVER_VERSION "0.0.2")
set(TORRSERVER_BIN_NAME "torrserver-windows-amd64.exe")
set(TORRSERVER_DEST_NAME "torrserver.exe")
set(LOCAL_BIN_DIR "$ENV{TORRSERVER_FLUTTER_LOCAL_BINARIES}")
set(TORRSERVER_CACHE_DIR "${CMAKE_CURRENT_BINARY_DIR}/torrserver_cache")
set(TORRSERVER_CACHED_BIN "${TORRSERVER_CACHE_DIR}/${TORRSERVER_DEST_NAME}")

file(MAKE_DIRECTORY "${TORRSERVER_CACHE_DIR}")

if(EXISTS "${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}")
  message(STATUS "Using local TorrServer binary: ${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}")
  file(COPY "${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
  file(RENAME "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}" "${TORRSERVER_CACHED_BIN}")
elseif(EXISTS "${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}")
  message(STATUS "Using local TorrServer binary: ${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}")
  file(COPY "${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
elseif(NOT EXISTS "${TORRSERVER_CACHED_BIN}")
  message(STATUS "Downloading TorrServer binary from GitHub Releases (v${TORRSERVER_VERSION})...")
  set(DOWNLOAD_URL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${TORRSERVER_VERSION}/${TORRSERVER_BIN_NAME}")
  file(DOWNLOAD "${DOWNLOAD_URL}" "${TORRSERVER_CACHED_BIN}"
    STATUS DOWNLOAD_STATUS
    LOG DOWNLOAD_LOG
  )
  list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
  if(NOT STATUS_CODE EQUAL 0)
    message(WARNING "TorrServer binary download skipped/deferred: ${DOWNLOAD_LOG}")
  endif()
endif()

# List of absolute paths to libraries that should be bundled with the plugin
set(torrserver_flutter_bundled_libraries
  "$<TARGET_FILE:${PLUGIN_NAME}>"
  "${TORRSERVER_CACHED_BIN}"
  PARENT_SCOPE
)
