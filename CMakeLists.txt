cmake_minimum_required(VERSION 3.21)

project(FileSync VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Network WebSockets)

find_package(ZLIB QUIET)

if(ZLIB_FOUND)
    message(STATUS "使用系统 Zlib：${ZLIB_VERSION_STRING}")
else()
    message(STATUS "未找到系统 Zlib，使用 FetchContent 获取 Zlib 1.3.1")

    include(FetchContent)

    # 不构建 Zlib 示例，不修改整个项目的 BUILD_SHARED_LIBS
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "Disable Zlib examples" FORCE)

    FetchContent_Declare(zlib
        GIT_REPOSITORY https://github.com/madler/zlib.git
        GIT_TAG        v1.3.1
        GIT_SHALLOW    TRUE
    )

    FetchContent_MakeAvailable(zlib)

    # 统一为目标 ZLIB::ZLIB，与 find_package 的结果保持一致
    if(TARGET zlibstatic AND NOT TARGET ZLIB::ZLIB)
        set_target_properties(zlibstatic PROPERTIES
            POSITION_INDEPENDENT_CODE ON
        )
        add_library(ZLIB::ZLIB ALIAS zlibstatic)
    elseif(TARGET zlib AND NOT TARGET ZLIB::ZLIB)
        add_library(ZLIB::ZLIB ALIAS zlib)
    endif()
endif()

if(NOT TARGET ZLIB::ZLIB)
    message(FATAL_ERROR
        "Zlib 不可用：系统查找和 FetchContent 均未创建 ZLIB::ZLIB"
    )
endif()

# MSYS2 UCRT64 MuPDF（动态库）
# 安装包：pacman -S mingw-w64-ucrt-x86_64-libmupdf
# 非默认安装位置可配置：-DMuPDF_ROOT=D:/msys64/ucrt64
set(MuPDF_ROOT "C:/msys64/ucrt64" CACHE PATH
    "MSYS2 UCRT64 前缀目录，其中应包含 include、lib 和 bin"
)

# 同时从编译器路径推导前缀，兼容 MSYS2 未安装在 C:/msys64 的情况。
get_filename_component(_MuPDF_COMPILER_BIN_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
get_filename_component(_MuPDF_COMPILER_PREFIX "${_MuPDF_COMPILER_BIN_DIR}" DIRECTORY)
set(_MuPDF_PREFIX_HINTS
    "${MuPDF_ROOT}"
    "${_MuPDF_COMPILER_PREFIX}"
)

if(WIN32 AND NOT MINGW)
    message(FATAL_ERROR
        "当前配置使用 MSYS2 UCRT64 MinGW 版 MuPDF，不能与 MSVC 或其他 ABI 的 Qt/编译器混用。"
        "请为项目选择 UCRT64 的编译器、Qt 和 CMake 工具包。"
    )
endif()

find_path(MuPDF_INCLUDE_DIR
    NAMES mupdf/fitz.h
    HINTS ${_MuPDF_PREFIX_HINTS}
    PATH_SUFFIXES include
    NO_DEFAULT_PATH
)

if(MINGW)
    # 明确选择动态库的导入库，避免误选 libmupdf.a 后遗漏静态链接依赖。
    find_file(MuPDF_LIBRARY
        NAMES libmupdf.dll.a
        HINTS ${_MuPDF_PREFIX_HINTS}
        PATH_SUFFIXES lib
        NO_DEFAULT_PATH
    )
    find_file(MuPDF_RUNTIME_LIBRARY
        NAMES libmupdf.dll
        HINTS ${_MuPDF_PREFIX_HINTS}
        PATH_SUFFIXES bin
        NO_DEFAULT_PATH
    )
else()
    find_library(MuPDF_LIBRARY
        NAMES mupdf
        HINTS ${_MuPDF_PREFIX_HINTS}
        PATH_SUFFIXES lib
        NO_DEFAULT_PATH
    )
endif()

set(_MuPDF_FILES_MISSING FALSE)
if(NOT MuPDF_INCLUDE_DIR OR NOT MuPDF_LIBRARY)
    set(_MuPDF_FILES_MISSING TRUE)
endif()
if(MINGW AND NOT MuPDF_RUNTIME_LIBRARY)
    set(_MuPDF_FILES_MISSING TRUE)
endif()

if(_MuPDF_FILES_MISSING)
    message(FATAL_ERROR
        "未找到完整的 MSYS2 UCRT64 MuPDF 动态库开发文件。\n"
        "请在 MSYS2 UCRT64 终端执行：\n"
        "  pacman -S mingw-w64-ucrt-x86_64-libmupdf\n"
        "需要存在：include/mupdf/fitz.h、lib/libmupdf.dll.a、bin/libmupdf.dll。\n"
        "当前 MuPDF_ROOT=${MuPDF_ROOT}；如安装位置不同，请通过 -DMuPDF_ROOT=... 指定。"
    )
endif()

if(NOT TARGET MuPDF::MuPDF)
    if(MINGW)
        add_library(MuPDF::MuPDF SHARED IMPORTED)
        set_target_properties(MuPDF::MuPDF PROPERTIES
            IMPORTED_IMPLIB "${MuPDF_LIBRARY}"
            IMPORTED_LOCATION "${MuPDF_RUNTIME_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${MuPDF_INCLUDE_DIR}"
        )
    else()
        add_library(MuPDF::MuPDF UNKNOWN IMPORTED)
        set_target_properties(MuPDF::MuPDF PROPERTIES
            IMPORTED_LOCATION "${MuPDF_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${MuPDF_INCLUDE_DIR}"
        )
    endif()
endif()

if(MuPDF_RUNTIME_LIBRARY)
    get_filename_component(MuPDF_RUNTIME_DIR "${MuPDF_RUNTIME_LIBRARY}" DIRECTORY)
endif()

message(STATUS "MuPDF 头文件目录：${MuPDF_INCLUDE_DIR}")
message(STATUS "MuPDF 链接库：${MuPDF_LIBRARY}")
if(MuPDF_RUNTIME_LIBRARY)
    message(STATUS "MuPDF 运行库：${MuPDF_RUNTIME_LIBRARY}")
endif()

mark_as_advanced(
    MuPDF_INCLUDE_DIR
    MuPDF_LIBRARY
    MuPDF_RUNTIME_LIBRARY
)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(FileSync
    include/UploadManager.h
    include/MuPdfRenderer.h
    include/MuPdfImageProvider.h
    main.cpp
    src/UploadManager.cpp
    src/MuPdfRenderer.cpp
    src/MuPdfImageProvider.cpp
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
        qml/components/FilePreviewDialog.qml
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
    Qt6::WebSockets
    ZLIB::ZLIB
    MuPDF::MuPDF
    FileSyncComponents
)

if(MINGW)
    # 将 libmupdf.dll 及其 UCRT64 第三方 DLL 依赖复制到可执行文件目录。
    add_custom_command(TARGET FileSync POST_BUILD
        COMMAND "${CMAKE_COMMAND}"
            "-DOUTPUT_DIR=$<TARGET_FILE_DIR:FileSync>"
            "-DMUPDF_DLL=${MuPDF_RUNTIME_LIBRARY}"
            "-DMUPDF_BIN_DIR=${MuPDF_RUNTIME_DIR}"
            "-DOBJDUMP=${CMAKE_OBJDUMP}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CopyMuPdfRuntime.cmake"
        VERBATIM
    )
endif()

add_subdirectory(${CMAKE_SOURCE_DIR}/localserver)
