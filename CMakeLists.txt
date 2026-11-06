cmake_minimum_required(VERSION 3.21)

project(FileSync VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Network)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(FileSync
    include/UploadManager.h
    main.cpp
    src/UploadManager.cpp

)
target_include_directories(FileSync PRIVATE ${CMAKE_SOURCE_DIR}/include)

qt_add_library(FileSyncComponents STATIC)

qt_add_qml_module(FileSyncComponents
    URI FileSyncComponents
    VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/FileSyncComponents
    QML_FILES
        qml/sections/LoginSection.qml
        qml/sections/FileSection.qml

        qml/components/ThirdParty.qml
        qml/components/Feature.qml
        qml/components/LoginField.qml
        qml/components/NavItem.qml
        qml/components/WindowButton.qml
        qml/components/UploadDialog.qml
    RESOURCES
        assets/eye-off.svg
        assets/eye.svg
)

qt_add_qml_module(FileSync
    URI FileSync
    VERSION 1.0
    QML_FILES
        qml/Main.qml
    RESOURCES
        assets/logo.svg
        assets/hero-sync.svg
        assets/avatar.svg
        assets/icon-home.svg
        assets/icon-file.svg
        assets/icon-sync.svg
        assets/icon-task.svg
        assets/icon-history.svg
        assets/icon-settings.svg
        assets/icon-user.svg
        assets/icon-lock.svg
        assets/icon-wechat.svg
        assets/icon-qq.svg
        assets/icon-apple.svg
        assets/icon-smartphone.svg
        assets/icon-verification_code.svg
        assets/icon-email.svg
        assets/icon-email_code.svg
        assets/window-close.svg
        assets/window-maximize.svg
        assets/window-minimize.svg
        assets/window-restore.svg
)

if(WIN32)
    set_target_properties(FileSync PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
endif()

target_link_libraries(FileSync PRIVATE
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    FileSyncComponents
)

add_subdirectory(${CMAKE_SOURCE_DIR}/localserver)

