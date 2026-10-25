cmake_minimum_required(VERSION 3.15)
project(miniaudio_reframework LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(miniaudio_reframework SHARED main.cpp)

target_link_libraries(miniaudio_reframework PRIVATE winmm)

set_target_properties(miniaudio_reframework PROPERTIES
    PREFIX ""
    OUTPUT_NAME "miniaudio_reframework"
)
