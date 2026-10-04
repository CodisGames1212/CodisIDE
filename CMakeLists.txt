cmake_minimum_required(VERSION 3.16)
project(codis-ide VERSION 0.1.0 LANGUAGES C CXX)

# --- Global configuration ---------------------------------------------------
# Use a modern, but widely supported, C++ standard. Make configurable.
if(NOT DEFINED CODIS_CXX_STANDARD)
  set(CODIS_CXX_STANDARD 17 CACHE STRING "C++ standard to use (11/14/17/20)")
endif()
set(CMAKE_CXX_STANDARD ${CODIS_CXX_STANDARD})
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(BUILD_SHARED_LIBS "Build libraries as shared by default" OFF)
option(BUILD_ADDONS "Discover and build native addons under addons/*/native" ON)
option(BUILD_TESTS "Enable building test targets" OFF)
option(BUILD_EXAMPLES "Enable building examples" OFF)

# --- Common packages -------------------------------------------------------
find_package(Threads REQUIRED)

# Helper: create a static library target from a directory's sources when no CMakeLists exists.
function(codis_auto_library dir target_name)
  if(NOT IS_ABSOLUTE "${dir}")
    set(dir "${CMAKE_SOURCE_DIR}/${dir}")
  endif()
  file(GLOB_RECURSE SRCS CONFIGURE_DEPENDS
    "${dir}/*.c"
    "${dir}/*.cc"
    "${dir}/*.cpp"
    "${dir}/*.cxx"
    "${dir}/*.m"
    "${dir}/*.mm"
  )
  if(SRCS)
    add_library(${target_name} STATIC ${SRCS})
    target_include_directories(${target_name}
      PUBLIC "${dir}"
    )
    target_compile_features(${target_name} PUBLIC cxx_std_${CODIS_CXX_STANDARD})
    target_link_libraries(${target_name} PRIVATE Threads::Threads)
    set_target_properties(${target_name} PROPERTIES
      POSITION_INDEPENDENT_CODE ${CMAKE_POSITION_INDEPENDENT_CODE}
    )
  endif()
endfunction()

# Utility: add subdirectory if it exists and contains sources or a CMakeLists
function(codis_try_add_subdir relpath)
  if(EXISTS "${CMAKE_SOURCE_DIR}/${relpath}/CMakeLists.txt")
    add_subdirectory("${relpath}")
    return()
  endif()
  # If there are source files, create an automatic library target.
  file(GLOB_RECURSE _has_src CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/${relpath}/*.c"
    "${CMAKE_SOURCE_DIR}/${relpath}/*.cc"
    "${CMAKE_SOURCE_DIR}/${relpath}/*.cpp"
    "${CMAKE_SOURCE_DIR}/${relpath}/*.cxx"
  )
  if(_has_src)
    string(REPLACE "/" "_" tgt "${relpath}")
    string(REPLACE "-" "_" tgt "${tgt}")
    codis_auto_library("${relpath}" "${tgt}")
  endif()
endfunction()

# --- Discover and add common source locations --------------------------------
# Root src
if(EXISTS "${CMAKE_SOURCE_DIR}/src")
  codis_try_add_subdir("src")
endif()

# modules (common in Godot engine builds)
if(EXISTS "${CMAKE_SOURCE_DIR}/modules")
  file(GLOB children CONFIGURE_DEPENDS RELATIVE "${CMAKE_SOURCE_DIR}" "modules/*")
  foreach(child IN LISTS children)
    codis_try_add_subdir("modules/${child}")
  endforeach()
endif()

# addons native code (Godot addons often put native C++ under addons/<name>/native)
if(BUILD_ADDONS AND EXISTS "${CMAKE_SOURCE_DIR}/addons")
  file(GLOB addon_native_dirs CONFIGURE_DEPENDS RELATIVE "${CMAKE_SOURCE_DIR}" "addons/*/native" "addons/*/native/*")
  foreach(dir IN LISTS addon_native_dirs)
    codis_try_add_subdir("${dir}")
  endforeach()
endif()

# thirdparty
if(EXISTS "${CMAKE_SOURCE_DIR}/thirdparty")
  file(GLOB third_dirs CONFIGURE_DEPENDS RELATIVE "${CMAKE_SOURCE_DIR}" "thirdparty/*")
  foreach(child IN LISTS third_dirs)
    codis_try_add_subdir("thirdparty/${child}")
  endforeach()
endif()

# Optionally detect and add a godot-cpp binding subproject if present
if(EXISTS "${CMAKE_SOURCE_DIR}/addons/codis_serial/native/godot-cpp")
  if(EXISTS "${CMAKE_SOURCE_DIR}/addons/codis_serial/native/godot-cpp/CMakeLists.txt")
    add_subdirectory("addons/codis_serial/native/godot-cpp")
  else()
    # If the godot-cpp sources exist but no CMakeLists, create a target with the typical include dir
    codis_auto_library("addons/codis_serial/native/godot-cpp" "godot_cpp_bindings")
    target_include_directories(godot_cpp_bindings PUBLIC "${CMAKE_SOURCE_DIR}/addons/codis_serial/native/godot-cpp/include")
  endif()
endif()

# --- Install rules (basic) --------------------------------------------------
include(GNUInstallDirs)

# Install every STATIC/SHARED library target by default
get_property(all_targets GLOBAL PROPERTY TARGETS)
foreach(tgt IN LISTS all_targets)
  if(TARGET ${tgt})
    get_target_property(type ${tgt} TYPE)
    if(type STREQUAL "STATIC_LIBRARY" OR type STREQUAL "SHARED_LIBRARY")
      install(TARGETS ${tgt}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
      )
    endif()
  endif()
endforeach()

# Install headers: simple heuristic (install top-level include folders)
if(EXISTS "${CMAKE_SOURCE_DIR}/include")
  install(DIRECTORY "${CMAKE_SOURCE_DIR}/include/" DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
endif()

# --- Useful targets ---------------------------------------------------------
add_custom_target(info
  COMMAND ${CMAKE_COMMAND} -E echo "Project: ${PROJECT_NAME} (${PROJECT_VERSION})"
  COMMENT "Show configured project info"
)

message(STATUS "Configured project '${PROJECT_NAME}' (C++${CODIS_CXX_STANDARD}).")