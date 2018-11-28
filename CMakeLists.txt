cmake_minimum_required(VERSION 3.5)

project(console-runner VERSION 1.4.1 LANGUAGES C)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

include(GNUInstallDirs)

add_subdirectory(doc)
add_subdirectory(src)
