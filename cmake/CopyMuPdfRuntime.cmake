# 由 FileSync 的 POST_BUILD 命令以 cmake -P 方式调用。
# 复制 libmupdf.dll，并递归复制其非 Windows 系统 DLL 依赖。

foreach(_required_var OUTPUT_DIR MUPDF_DLL MUPDF_BIN_DIR)
    if(NOT DEFINED ${_required_var} OR "${${_required_var}}" STREQUAL "")
        message(FATAL_ERROR "CopyMuPdfRuntime.cmake 缺少参数：${_required_var}")
    endif()
endforeach()

if(NOT EXISTS "${MUPDF_DLL}")
    message(FATAL_ERROR "MuPDF 运行库不存在：${MUPDF_DLL}")
endif()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")

# 在脚本模式中显式指定 PE/MinGW 依赖扫描工具。
set(CMAKE_GET_RUNTIME_DEPENDENCIES_PLATFORM "windows+pe")
set(CMAKE_GET_RUNTIME_DEPENDENCIES_TOOL "objdump")
if(DEFINED OBJDUMP AND NOT "${OBJDUMP}" STREQUAL "")
    if(NOT EXISTS "${OBJDUMP}")
        message(FATAL_ERROR "objdump 不存在：${OBJDUMP}")
    endif()
    set(CMAKE_GET_RUNTIME_DEPENDENCIES_COMMAND "${OBJDUMP}")
endif()

file(GET_RUNTIME_DEPENDENCIES
    LIBRARIES "${MUPDF_DLL}"
    DIRECTORIES "${MUPDF_BIN_DIR}"
    RESOLVED_DEPENDENCIES_VAR _mupdf_dependencies
    UNRESOLVED_DEPENDENCIES_VAR _mupdf_unresolved
    PRE_EXCLUDE_REGEXES
        "^api-ms-win-"
        "^ext-ms-"
    POST_EXCLUDE_REGEXES
        "^[A-Za-z]:/[Ww][Ii][Nn][Dd][Oo][Ww][Ss]/"
)

# Windows API Set 等虚拟依赖不需要、也无法从磁盘复制。
set(_mupdf_unexpected_unresolved)
foreach(_dependency IN LISTS _mupdf_unresolved)
    string(TOLOWER "${_dependency}" _dependency_lower)
    if(NOT _dependency_lower MATCHES "^(api-ms-win-|ext-ms-)")
        list(APPEND _mupdf_unexpected_unresolved "${_dependency}")
    endif()
endforeach()

if(_mupdf_unexpected_unresolved)
    list(JOIN _mupdf_unexpected_unresolved "\n  " _unresolved_text)
    message(FATAL_ERROR
        "无法解析以下 MuPDF 运行库依赖：\n  ${_unresolved_text}\n"
        "请确认使用 UCRT64 工具链，并且依赖位于 ${MUPDF_BIN_DIR}。"
    )
endif()

set(_files_to_copy "${MUPDF_DLL}" ${_mupdf_dependencies})
list(REMOVE_DUPLICATES _files_to_copy)

foreach(_source_file IN LISTS _files_to_copy)
    # 双保险：即使工具返回了系统目录，也不复制 Windows 自带 DLL。
    if(NOT "${_source_file}" MATCHES "^[A-Za-z]:/[Ww][Ii][Nn][Dd][Oo][Ww][Ss]/")
        get_filename_component(_file_name "${_source_file}" NAME)
        file(COPY_FILE
            "${_source_file}"
            "${OUTPUT_DIR}/${_file_name}"
            ONLY_IF_DIFFERENT
        )
    endif()
endforeach()

list(LENGTH _files_to_copy _dependency_count)
message(STATUS
    "MuPDF 运行库处理完成：${OUTPUT_DIR}（扫描到 ${_dependency_count} 个文件，系统 DLL 已排除）"
)
