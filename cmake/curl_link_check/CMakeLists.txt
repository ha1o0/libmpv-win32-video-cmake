cmake_minimum_required(VERSION 3.19)
project(curl_static_link_check C)

if(NOT WIN32)
    message(FATAL_ERROR "The curl link check must target Windows")
endif()

find_package(PkgConfig REQUIRED)
if(MINGW)
    # FindPkgConfig resolves -l flags to absolute paths before the linker runs.
    # Prefer archives here too, otherwise -static cannot replace a .dll.a path.
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
endif()
pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)
add_library(curl_static_link_check SHARED check.c)
target_link_libraries(curl_static_link_check PRIVATE PkgConfig::CURL)
if(MINGW)
    # Also reject an accidental dependency on a shared MinGW/network runtime.
    target_link_options(curl_static_link_check PRIVATE -static)
endif()
