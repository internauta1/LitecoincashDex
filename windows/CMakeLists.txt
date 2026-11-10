# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(gleecdex LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "litecoincashdexnext")

# An experimental build can use audited, pre-populated local dependencies.
# Missing inputs fail here; plugin builds cannot invoke a NuGet downloader.
if("$ENV{LCC_NEXT_OFFLINE_BUILD}" STREQUAL "1")
  set(FETCHCONTENT_FULLY_DISCONNECTED ON)
  set(NUGET "${CMAKE_CURRENT_SOURCE_DIR}/../tool/windows/nuget_offline.cmd")
  set(ENV{FIREBASE_CPP_SDK_DIR}
      "${CMAKE_BINARY_DIR}/extracted/firebase_cpp_sdk_windows")
  if(DEFINED ENV{LCC_NEXT_FIREBASE_SDK_DIR})
    set(ENV{FIREBASE_CPP_SDK_DIR} "$ENV{LCC_NEXT_FIREBASE_SDK_DIR}")
  endif()
  if(NOT EXISTS "$ENV{FIREBASE_CPP_SDK_DIR}/include/firebase/version.h")
    message(FATAL_ERROR "Offline Firebase SDK missing; refusing download.")
  endif()
  file(READ "$ENV{FIREBASE_CPP_SDK_DIR}/include/firebase/version.h" NEXT_FIREBASE_VERSION)
  if(NOT NEXT_FIREBASE_VERSION MATCHES "FIREBASE_VERSION_MAJOR 12" OR
     NOT NEXT_FIREBASE_VERSION MATCHES "FIREBASE_VERSION_MINOR 7" OR
     NOT NEXT_FIREBASE_VERSION MATCHES "FIREBASE_VERSION_REVISION 0")
    message(FATAL_ERROR "Offline Firebase SDK must be 12.7.0; refusing download.")
  endif()
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by build hooks.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
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
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Public Windows release: provisioned immutable executable; no engine download here.
set(LCC_PINNED_ENGINE "${CMAKE_CURRENT_SOURCE_DIR}/../artifacts/kdf/windows/mm2_lccnext_8762.exe")
if(NOT EXISTS "${LCC_PINNED_ENGINE}")
  message(FATAL_ERROR "Approved KDF missing. Run python tool/windows/prepare_kdf.py --file <verified-engine>.")
endif()
file(SHA256 "${LCC_PINNED_ENGINE}" LCC_ENGINE_SHA256)
if(NOT LCC_ENGINE_SHA256 STREQUAL "e752b26c8208111da9aa2f4a1af61ca0ed818c5bf65e745c1db21acf5c34b6d8")
  message(FATAL_ERROR "KDF SHA-256 mismatch; no fallback or binary patch is permitted.")
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/runner/native_profile.cmake")
next_runner_is_isolated("${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake" LCC_PUBLIC_ISOLATED)
if(LCC_PUBLIC_ISOLATED)
  set(LCC_ENGINE_NAME "mm2_lccnext_isolated.exe")
else()
  set(LCC_ENGINE_NAME "mm2_lccnext_8762.exe")
endif()
install(FILES "${LCC_PINNED_ENGINE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" RENAME "${LCC_ENGINE_NAME}" COMPONENT Runtime)
