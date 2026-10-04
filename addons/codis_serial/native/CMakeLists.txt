
cmake_minimum_required(VERSION 3.16)
project(codis_serial VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Build the matching Godot C++ bindings as part of this extension so generated
# headers are available before compiling the serial driver.
set(GODOTCPP_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/godot-cpp" CACHE PATH "Path to the godot-cpp source tree")
if(NOT EXISTS "${GODOTCPP_SOURCE_DIR}/CMakeLists.txt" AND DEFINED GODOT_CPP_DIR)
  if(EXISTS "${GODOT_CPP_DIR}/CMakeLists.txt")
    set(GODOTCPP_SOURCE_DIR "${GODOT_CPP_DIR}")
  elseif(EXISTS "${GODOT_CPP_DIR}/../CMakeLists.txt")
    get_filename_component(GODOTCPP_SOURCE_DIR "${GODOT_CPP_DIR}/.." ABSOLUTE)
  endif()
endif()
if(NOT EXISTS "${GODOTCPP_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "godot-cpp source tree not found. Initialize addons/codis_serial/native/godot-cpp or set GODOTCPP_SOURCE_DIR.")
endif()

set(GODOTCPP_TARGET "template_release" CACHE STRING "Godot build template to target")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot API version to target")
add_subdirectory("${GODOTCPP_SOURCE_DIR}" "godot-cpp-build")

add_library(codis_serial SHARED
  src/codis_serial.cpp
  src/register_types.cpp
)
target_include_directories(codis_serial PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(codis_serial PRIVATE godot-cpp)

if(WIN32)
  set(CODIS_PLATFORM windows)
  set(CODIS_ARCH_SUFFIX "")
elseif(ANDROID)
  set(CODIS_PLATFORM android)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CODIS_ARCH_SUFFIX "arm64.")
  elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(CODIS_ARCH_SUFFIX "arm32.")
  elseif(ANDROID_ABI STREQUAL "x86_64")
    set(CODIS_ARCH_SUFFIX "x86_64.")
  elseif(ANDROID_ABI STREQUAL "x86")
    set(CODIS_ARCH_SUFFIX "x86_32.")
  else()
    message(FATAL_ERROR "Unsupported Android ABI: ${ANDROID_ABI}")
  endif()
elseif(APPLE AND CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(CODIS_PLATFORM macos)
  set(CODIS_ARCH_SUFFIX "")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(CODIS_PLATFORM linux)
  set(CODIS_ARCH_SUFFIX "")
else()
  message(FATAL_ERROR "Unsupported GDExtension platform: ${CMAKE_SYSTEM_NAME}")
endif()

set(CODIS_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin/${CODIS_PLATFORM}")
set_target_properties(codis_serial PROPERTIES
  PREFIX ""
  OUTPUT_NAME "codis_serial.${CODIS_ARCH_SUFFIX}${CODIS_PLATFORM}.${GODOTCPP_TARGET}"
  RUNTIME_OUTPUT_DIRECTORY "${CODIS_OUTPUT_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CODIS_OUTPUT_DIR}"
)