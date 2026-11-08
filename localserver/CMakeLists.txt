cmake_minimum_required(VERSION 3.21)
project(FileSyncLocalUploadServer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Network WebSockets)

add_executable(FileSyncLocalUploadServer
    local_server_main.cpp
    LocalUploadServer.h
    LocalUploadServer.cpp
)

target_link_libraries(FileSyncLocalUploadServer PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::WebSockets
)
