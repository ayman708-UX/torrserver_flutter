cmake_minimum_required(VERSION 3.18)
set(PROJECT_NAME "torrserver_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "torrserver_flutter_plugin")

add_library(${PLUGIN_NAME} SHARED
  "torrserver_flutter_plugin.cc"
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

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# --- TorrServer Native Binary Setup for Linux ---
set(TORRSERVER_VERSION "0.0.7")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(TORRSERVER_ARCH "arm64")
else()
  set(TORRSERVER_ARCH "amd64")
endif()

set(TORRSERVER_ARCHIVE_NAME "torrserver-linux-${TORRSERVER_ARCH}.tar.gz")
set(TORRSERVER_BIN_NAME "torrserver-linux-${TORRSERVER_ARCH}")
set(TORRSERVER_DEST_NAME "torrserver")
set(LOCAL_BIN_DIR "$ENV{TORRSERVER_FLUTTER_LOCAL_BINARIES}")
set(TORRSERVER_CACHE_DIR "${CMAKE_CURRENT_BINARY_DIR}/torrserver_cache")
set(TORRSERVER_CACHED_BIN "${TORRSERVER_CACHE_DIR}/${TORRSERVER_DEST_NAME}")

file(MAKE_DIRECTORY "${TORRSERVER_CACHE_DIR}")

if(EXISTS "${LOCAL_BIN_DIR}/${TORRSERVER_ARCHIVE_NAME}")
  message(STATUS "Using local TorrServer archive: ${LOCAL_BIN_DIR}/${TORRSERVER_ARCHIVE_NAME}")
  file(ARCHIVE_EXTRACT INPUT "${LOCAL_BIN_DIR}/${TORRSERVER_ARCHIVE_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
  if(EXISTS "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}")
    file(RENAME "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}" "${TORRSERVER_CACHED_BIN}")
  endif()
elseif(EXISTS "${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}")
  message(STATUS "Using local TorrServer binary: ${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}")
  file(COPY "${LOCAL_BIN_DIR}/${TORRSERVER_BIN_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
  file(RENAME "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}" "${TORRSERVER_CACHED_BIN}")
elseif(EXISTS "${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}")
  message(STATUS "Using local TorrServer binary: ${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}")
  file(COPY "${LOCAL_BIN_DIR}/${TORRSERVER_DEST_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
elseif(NOT EXISTS "${TORRSERVER_CACHED_BIN}")
  message(STATUS "Downloading compressed TorrServer binary from GitHub Releases (v${TORRSERVER_VERSION})...")
  set(DOWNLOAD_URL "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${TORRSERVER_VERSION}/${TORRSERVER_ARCHIVE_NAME}")
  file(DOWNLOAD "${DOWNLOAD_URL}" "${TORRSERVER_CACHE_DIR}/${TORRSERVER_ARCHIVE_NAME}"
    STATUS DOWNLOAD_STATUS
    LOG DOWNLOAD_LOG
  )
  list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
  if(STATUS_CODE EQUAL 0)
    # Verify SHA-256 checksum against release checksums.txt if available
    file(DOWNLOAD "https://github.com/ayman708-UX/torrserver_flutter/releases/download/v${TORRSERVER_VERSION}/checksums.txt"
      "${TORRSERVER_CACHE_DIR}/checksums.txt"
      STATUS CHECKSUM_STATUS
    )
    list(GET CHECKSUM_STATUS 0 CS_CODE)
    if(CS_CODE EQUAL 0)
      file(READ "${TORRSERVER_CACHE_DIR}/checksums.txt" CHECKSUM_FILE_CONTENT)
      file(SHA256 "${TORRSERVER_CACHE_DIR}/${TORRSERVER_ARCHIVE_NAME}" COMPUTED_SHA256)
      if(CHECKSUM_FILE_CONTENT MATCHES "([a-fA-F0-9]+)[ \t]+[*]?${TORRSERVER_ARCHIVE_NAME}")
        set(EXPECTED_SHA256 "${CMAKE_MATCH_1}")
        string(TOLOWER "${COMPUTED_SHA256}" COMPUTED_SHA256)
        string(TOLOWER "${EXPECTED_SHA256}" EXPECTED_SHA256)
        if(NOT COMPUTED_SHA256 STREQUAL EXPECTED_SHA256)
          file(REMOVE "${TORRSERVER_CACHE_DIR}/${TORRSERVER_ARCHIVE_NAME}")
          message(FATAL_ERROR "SHA-256 mismatch for ${TORRSERVER_ARCHIVE_NAME}! Expected: ${EXPECTED_SHA256}, got: ${COMPUTED_SHA256}")
        endif()
        message(STATUS "Verified SHA-256 for ${TORRSERVER_ARCHIVE_NAME}: ${COMPUTED_SHA256}")
      endif()
      file(REMOVE "${TORRSERVER_CACHE_DIR}/checksums.txt")
    endif()

    file(ARCHIVE_EXTRACT INPUT "${TORRSERVER_CACHE_DIR}/${TORRSERVER_ARCHIVE_NAME}" DESTINATION "${TORRSERVER_CACHE_DIR}")
    if(EXISTS "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}")
      file(RENAME "${TORRSERVER_CACHE_DIR}/${TORRSERVER_BIN_NAME}" "${TORRSERVER_CACHED_BIN}")
    endif()
    file(REMOVE "${TORRSERVER_CACHE_DIR}/${TORRSERVER_ARCHIVE_NAME}")
  else()
    message(WARNING "TorrServer binary download skipped/deferred: ${DOWNLOAD_LOG}")
  endif()
endif()

if(EXISTS "${TORRSERVER_CACHED_BIN}")
  file(CHMOD "${TORRSERVER_CACHED_BIN}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
  )
endif()

# List of absolute paths to libraries that should be bundled with the plugin
set(torrserver_flutter_bundled_libraries
  "$<TARGET_FILE:${PLUGIN_NAME}>"
  "${TORRSERVER_CACHED_BIN}"
  PARENT_SCOPE
)
