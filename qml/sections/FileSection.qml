import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import FileSyncComponents 1.0

/*
 * FileSync - 文件工作台
 *
 * 用法：
 *   FileManagerPage { anchors.fill: parent }
 *
 * 文件列表使用本地 ListModel；上传、列表和预览通过 C++ UploadManager 接入 HTTP 服务。
 * 服务器文件变化通过 WebSocket 主动推送，客户端自动刷新当前目录并在断线后重连。
 * 行菜单的打开、下载、重命名和移动由 UploadManager 完成；分享、删除、刷新和立即同步仍通过 signals 暴露给业务层。
 */
Item {
    id: root
    objectName: "fileManagerPage"

    // 可由 C++ 设置为 QAbstractListModel；模型角色需包含 name/kind/ext/modified/size/status/iconBg/iconColor。
    // 文件预览使用 path；服务端还可提供 previewType（image/text/binary）和 mimeType。
    property var fileModelSource: fileModel

    // 图片高度按原始尺寸和宽高比计算；该值仅限制极端长图，不会裁切或拉伸图片。
    property real maxImagePreviewHeight: 720
    property int textPreviewByteLimit: 65536

    // 与登录页面保持一致的主题色
    property color primaryColor: "#4B6EF5"
    property color primaryDarkColor: "#3558DD"
    property color textDarkColor: "#1E2A45"
    property color textMidColor: "#71809B"
    property color textLightColor: "#A9B5C9"
    property color panelColor: "#FFFFFF"
    property color pageColor: "#F7F9FD"
    property color lineColor: "#E8EDF6"
    property color successColor: "#28B985"
    property color warningColor: "#F2A64A"

    property string currentNav: "我的文件"
    property string currentFilter: "全部"
    property string searchKeyword: ""
    property bool detailsVisible: true
    property string selectedName: ""
    property string selectedKind: ""
    property string selectedModified: ""
    property string selectedSize: ""
    property string selectedStatus: ""
    property string selectedExt: ""
    property string pendingCreatedFolderName: ""
    property string pendingCreatedFolderPath: ""
    property string pendingRenamedPath: ""
    property bool refreshAfterCurrentFileLoad: false
    property var breadcrumbItems: root.makeBreadcrumbs(uploadManager.currentPath)
    property string currentLocationText: uploadManager.currentPath.length === 0
                                        ? "我的文件" : "我的文件 / " + uploadManager.currentPath

    // 供 C++ 业务层连接的接口
    signal uploadRequested()
    signal createFolderRequested(string folderName)
    signal downloadRequested(string fileName)
    signal shareRequested(string fileName)
    signal deleteRequested(string fileName)
    signal openFileRequested(string fileName)
    signal previewRequested(string fileName, string filePath, string previewType,
                            string extension, string mimeType)
    signal refreshRequested()
    signal syncNowRequested()
    signal navigationChanged(string navigation)
    signal fileSelected(string fileName, string fileKind)

    // 两个上传按钮共用独立的上传面板；新建文件夹沿用同样的异步请求模式。
    onUploadRequested: uploadDialog.open()
    onCreateFolderRequested: uploadManager.createFolder(folderName)
    onRefreshRequested: uploadManager.loadFiles()

    function makeBreadcrumbs(path) {
        var items = [{ name: "我的文件", path: "" }]
        if (path === undefined || path === null || path.length === 0)
            return items

        var parts = path.split("/")
        var currentPath = ""
        for (var i = 0; i < parts.length; ++i) {
            if (parts[i].length === 0)
                continue
            currentPath = currentPath.length === 0 ? parts[i] : currentPath + "/" + parts[i]
            items.push({ name: parts[i], path: currentPath })
        }
        return items
    }

    function openFolder(path) {
        uploadManager.openFolder(path === undefined || path === null ? "" : path.toString())
    }

    // 自定义模型未提供 path 时，按当前云端目录和文件名构造相对路径。
    function cloudItemPath(path, name) {
        if (path !== undefined && path !== null && path.toString().length > 0)
            return path.toString()
        var itemName = name === undefined || name === null ? "" : name.toString()
        return uploadManager.currentPath.length > 0
               ? uploadManager.currentPath + "/" + itemName : itemName
    }

    function requestDownload(path, kind) {
        var sourcePath = path === undefined || path === null ? "" : path.toString()
        if (sourcePath.length === 0 || uploadManager.downloading)
            return

        if (kind === "folder") {
            downloadFolderDialog.cloudPath = sourcePath
            downloadFolderDialog.open()
            return
        }

        downloadFileDialog.cloudPath = sourcePath
        downloadFileDialog.currentFile = uploadManager.defaultDownloadUrl(sourcePath)
        downloadFileDialog.open()
    }

    function showDownloadResult(succeeded, isFolder, localPath, reason) {
        downloadResultDialog.showResult(succeeded, isFolder, localPath, reason)
    }

    function clearSelection() {
        selectedName = ""
        selectedKind = ""
        selectedModified = ""
        selectedSize = ""
        selectedStatus = ""
        selectedExt = ""
    }

    function selectFile(name, kind, modified, size, status, ext) {
        selectedName = name
        selectedKind = kind
        selectedModified = modified
        selectedSize = size
        selectedStatus = status
        selectedExt = ext
        fileSelected(name, kind)
    }

    function matchesFilter(kind) {
        if (currentFilter === "文件")
            return kind !== "folder"
        if (currentFilter === "文件夹")
            return kind === "folder"
        return true
    }

    function matchesSearch(name) {
        return searchKeyword.length === 0 || name.toLowerCase().indexOf(searchKeyword.toLowerCase()) !== -1
    }

    // 与客户端和服务端保持一致，提前给出名称错误，服务端仍会进行最终校验。
    function validateItemName(itemName, itemKind) {
        var name = itemName === undefined || itemName === null ? "" : itemName.toString().trim()
        var typeName = itemKind === "folder" ? "文件夹名称" : "文件名称"
        if (name.length === 0)
            return "请输入" + typeName
        if (name.length > 100)
            return typeName + "不能超过 100 个字符"
        if (name === "." || name === "..")
            return typeName + "不能是“.”或“..”"

        var invalidCharacters = "<>:\"/\\|?*"
        for (var i = 0; i < name.length; ++i) {
            if (name.charCodeAt(i) < 32 || invalidCharacters.indexOf(name.charAt(i)) !== -1)
                return "名称不能包含 < > : \" / \\ | ? * 或控制字符"
        }
        if (name.charAt(name.length - 1) === "." || name.charAt(name.length - 1) === " ")
            return typeName + "不能以句点或空格结尾"

        var baseName = name
        var firstDot = baseName.indexOf(".")
        if (firstDot > 0)
            baseName = baseName.substring(0, firstDot)
        baseName = baseName.toUpperCase()
        if (["CON", "PRN", "AUX", "NUL"].indexOf(baseName) !== -1
                || /^(COM|LPT)[1-9]$/.test(baseName))
            return "该名称是系统保留名称，请更换" + typeName

        return ""
    }

    function validateFolderName(folderName) {
        return validateItemName(folderName, "folder")
    }

    function isImageExtension(extension) {
        if (extension === undefined || extension === null)
            return false

        var value = extension.toString().toLowerCase()
        return ["jpg", "jpeg", "png", "gif", "bmp", "webp",
                "svg", "ico", "tif", "tiff"].indexOf(value) !== -1
    }

    function isTextExtension(extension) {
        if (extension === undefined || extension === null)
            return false

        var value = extension.toString().toLowerCase()
        return ["txt", "md", "markdown", "log", "json", "xml", "yaml", "yml",
                "csv", "tsv", "ini", "cfg", "conf", "properties", "html", "htm",
                "css", "js", "ts", "qml", "c", "h", "cpp", "hpp", "cc", "cxx",
                "java", "py", "sh", "bat", "sql", "vue", "php", "rb", "go", "rs"
               ].indexOf(value) !== -1
    }

    function previewTypeForExtension(extension) {
        if (isImageExtension(extension))
            return "image"
        if (isTextExtension(extension))
            return "text"
        return "binary"
    }

    function fileTypeDescription(extension) {
        if (extension === undefined || extension === null)
            return "文件"

        var value = extension.toString().toLowerCase()
        if (value === "pdf")
            return "PDF 文档"
        if (["doc", "docx", "rtf", "odt"].indexOf(value) !== -1)
            return "文字文档"
        if (["xls", "xlsx", "csv", "ods"].indexOf(value) !== -1)
            return "表格文件"
        if (["ppt", "pptx", "odp"].indexOf(value) !== -1)
            return "演示文稿"
        if (["txt", "md", "log", "json", "xml"].indexOf(value) !== -1)
            return "文本文件"
        if (["mp4", "mov", "avi", "mkv", "webm"].indexOf(value) !== -1)
            return "视频文件"
        if (["mp3", "wav", "flac", "aac", "ogg"].indexOf(value) !== -1)
            return "音频文件"
        if (["zip", "rar", "7z", "tar", "gz"].indexOf(value) !== -1)
            return "压缩文件"
        return value.length > 0 ? value.toUpperCase() + " 文件" : "文件"
    }

    Rectangle {
        anchors.fill: parent
        color: root.pageColor
    }

    Row {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        // 左侧导航栏
        // ============================================================
        Rectangle {
            id: sidebar
            width: 218
            height: parent.height
            color: "#FFFFFF"
            border.color: "#EDF1F7"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 0

                // Logo 与产品名称
                Item {
                    width: parent.width
                    height: 76

                    Rectangle {
                        x: 3
                        y: 19
                        width: 38
                        height: 38
                        radius: 11
                        color: root.primaryColor

                        Text {
                            anchors.centerIn: parent
                            text: "↔"
                            color: "white"
                            font.pixelSize: 25
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        x: 51
                        y: 19
                        text: "FileSync"
                        color: root.textDarkColor
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        x: 52
                        y: 43
                        text: "云端文件空间"
                        color: root.textLightColor
                        font.pixelSize: 10
                    }
                }

                // 上传入口
                Button {
                    id: sidebarUploadButton
                    width: parent.width
                    height: 42
                    hoverEnabled: true
                    enabled: !uploadManager.uploading
                    background: Rectangle {
                        radius: 8
                        color: !sidebarUploadButton.enabled ? "#AAB8E8"
                               : sidebarUploadButton.down ? root.primaryDarkColor
                               : sidebarUploadButton.hovered ? "#5878F7" : root.primaryColor
                    }
                    contentItem: Row {
                        spacing: 8
                        anchors.centerIn: parent
                        Text {
                            text: "+"
                            color: "white"
                            font.pixelSize: 21
                            font.weight: Font.Light
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "上传文件"
                            color: "white"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    onClicked: root.uploadRequested()
                }

                Item { width: 1; height: 22 }

                Text {
                    text: "文件空间"
                    color: "#A3AEC1"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    leftPadding: 10
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: [
                        { title: "我的文件", icon: "▣" },
                        { title: "最近使用", icon: "◷" },
                        { title: "收藏夹", icon: "☆" },
                        { title: "共享给我", icon: "♧" },
                        { title: "回收站", icon: "⌫" }
                    ]

                    delegate: Item {
                        width: sidebar.width - 32
                        height: 43
                        property bool active: root.currentNav === modelData.title

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.active ? "#EEF2FF" : (navMouse.containsMouse ? "#F7F9FE" : "transparent")
                        }
                        Rectangle {
                            width: 3
                            height: 20
                            radius: 2
                            color: root.primaryColor
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.active
                        }
                        Text {
                            x: 15
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: parent.active ? root.primaryColor : "#8794AA"
                            font.pixelSize: 17
                            width: 23
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            x: 49
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: parent.active ? root.primaryColor : "#596981"
                            font.pixelSize: 13
                            font.weight: parent.active ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentNav = modelData.title
                                root.navigationChanged(modelData.title)
                            }
                        }
                    }
                }

                Item { width: 1; height: 18 }
                Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
                Item { width: 1; height: 15 }

                Text {
                    text: "同步管理"
                    color: "#A3AEC1"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    leftPadding: 10
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                }

                Item {
                    width: parent.width
                    height: 43
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: syncNavMouse.containsMouse ? "#F7F9FE" : "transparent"
                    }
                    Text {
                        x: 15
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↻"
                        color: "#8794AA"
                        font.pixelSize: 18
                        width: 23
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        x: 49
                        anchors.verticalCenter: parent.verticalCenter
                        text: "同步任务"
                        color: "#596981"
                        font.pixelSize: 13
                    }
                    Rectangle {
                        width: 22
                        height: 19
                        radius: 9
                        color: "#EEF2FF"
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: uploadManager.syncingFileCount
                            color: root.primaryColor
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                    MouseArea {
                        id: syncNavMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.syncNowRequested()
                    }
                }

                Item { Layout.fillHeight: true; width: 1; height: 1 }

                // 存储空间卡片
                Rectangle {
                    width: parent.width
                    height: 128
                    radius: 10
                    color: "#F8FAFF"
                    border.color: "#EAF0FC"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 7
                            Text { text: "☁"; color: root.primaryColor; font.pixelSize: 17 }
                            Text {
                                text: "云端存储"
                                color: root.textDarkColor
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Text {
                                text: "68%"
                                color: root.primaryColor
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            text: "6.8 GB  /  10 GB"
                            color: root.textMidColor
                            font.pixelSize: 11
                        }
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: "#E7ECF6"
                            Rectangle {
                                width: parent.width * 0.68
                                height: parent.height
                                radius: 3
                                color: root.primaryColor
                            }
                        }
                        Text {
                            text: "空间使用情况良好"
                            color: "#98A5B9"
                            font.pixelSize: 10
                        }
                    }
                }

                Item { width: 1; height: 12 }

                // 用户信息
                Row {
                    width: parent.width
                    height: 52
                    spacing: 9
                    Rectangle {
                        width: 33
                        height: 33
                        radius: 17
                        color: "#EAF0FF"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "U"
                            color: root.primaryColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: "我的账号"
                            color: root.textDarkColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "个人免费版"
                            color: root.textLightColor
                            font.pixelSize: 10
                        }
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "⋯"
                        color: "#9AA6B8"
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ============================================================
        // 右侧工作区
        // ============================================================
        Item {
            id: workspace
            width: parent.width - sidebar.width
            height: parent.height

            Row {
                anchors.fill: parent
                spacing: 0

                // 中央文件区域
                Item {
                    id: mainArea
                    width: workspace.width - (root.detailsVisible && workspace.width >= 850 ? 270 : 0)
                    height: parent.height

                    Behavior on width {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 13

                        // 顶部标题、搜索和快捷操作
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 54
                            spacing: 12

                            Column {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: root.currentNav
                                    color: root.textDarkColor
                                    font.pixelSize: 22
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "管理和同步你的所有文件"
                                    color: root.textLightColor
                                    font.pixelSize: 11
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 225
                                Layout.minimumWidth: 150
                                Layout.preferredHeight: 36
                                radius: 8
                                color: "#FFFFFF"
                                border.color: searchField.activeFocus ? root.primaryColor : "#E7ECF4"
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 11
                                    anchors.rightMargin: 9
                                    spacing: 7
                                    Text {
                                        text: "⌕"
                                        color: "#98A5B9"
                                        font.pixelSize: 21
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    TextField {
                                        id: searchField
                                        width: parent.width - 34
                                        height: parent.height
                                        placeholderText: "搜索文件或文件夹"
                                        color: root.textDarkColor
                                        font.pixelSize: 11
                                        selectByMouse: true
                                        background: Item {}
                                        onTextChanged: root.searchKeyword = text.trim()
                                    }
                                }
                            }

                            Button {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 8
                                    color: parent.hovered ? "#EEF2FF" : "#FFFFFF"
                                    border.color: "#E7ECF4"
                                }
                                contentItem: Text {
                                    text: "♧"
                                    color: "#8290A8"
                                    font.pixelSize: 17
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: root.refreshRequested()
                                ToolTip.visible: hovered
                                ToolTip.text: "刷新文件列表"
                            }
                        }

                        // 面包屑与主要操作
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 39
                            spacing: 8

                            ListView {
                                id: breadcrumbView
                                Layout.fillWidth: true
                                Layout.preferredHeight: 39
                                orientation: ListView.Horizontal
                                model: root.breadcrumbItems
                                currentIndex: Math.max(0, count - 1)
                                spacing: 7
                                clip: true
                                interactive: contentWidth > width
                                boundsBehavior: Flickable.StopAtBounds
                                highlight: null

                                // 等路径模型和代理尺寸更新后再定位，确保最后一级目录可见。
                                function revealCurrentFolder() {
                                    Qt.callLater(function() {
                                        if (count <= 0 || contentWidth <= width) {
                                            contentX = 0
                                            return
                                        }
                                        positionViewAtIndex(count - 1, ListView.End)
                                    })
                                }

                                onModelChanged: revealCurrentFolder()
                                onCountChanged: revealCurrentFolder()
                                onContentWidthChanged: revealCurrentFolder()
                                onWidthChanged: revealCurrentFolder()
                                Component.onCompleted: revealCurrentFolder()

                                delegate: Item {
                                    id: breadcrumbDelegate
                                    readonly property bool isCurrent: index === breadcrumbView.currentIndex
                                    width: breadcrumbDelegateRow.implicitWidth
                                    height: breadcrumbView.height

                                    Row {
                                        id: breadcrumbDelegateRow
                                        height: parent.height
                                        spacing: 7

                                        Text {
                                            visible: index > 0
                                            text: "›"
                                            color: "#C0C9D7"
                                            font.pixelSize: 15
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            id: breadcrumbText
                                            width: Math.min(implicitWidth, 180)
                                            text: modelData.name
                                            color: breadcrumbDelegate.isCurrent ? root.textDarkColor
                                                   : (breadcrumbMouse.containsMouse ? root.primaryColor : "#8794AA")
                                            font.pixelSize: 11
                                            font.weight: breadcrumbDelegate.isCurrent ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: breadcrumbMouse
                                        anchors.fill: parent
                                        enabled: !breadcrumbDelegate.isCurrent
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.openFolder(modelData.path)
                                    }
                                }
                            }

                            Button {
                                id: newFolderButton
                                Layout.preferredWidth: 108
                                Layout.preferredHeight: 36
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 8
                                    color: newFolderButton.hovered ? "#F2F5FF" : "#FFFFFF"
                                    border.color: "#DCE4F4"
                                }
                                contentItem: Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "+"
                                        color: root.primaryColor
                                        font.pixelSize: 17
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "新建文件夹"
                                        color: "#53637D"
                                        font.pixelSize: 11
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                onClicked: createFolderDialog.open()
                            }

                            Button {
                                id: uploadButton
                                Layout.preferredWidth: 102
                                Layout.preferredHeight: 36
                                hoverEnabled: true
                                enabled: !uploadManager.uploading
                                background: Rectangle {
                                    radius: 8
                                    color: !uploadButton.enabled ? "#AAB8E8"
                                           : uploadButton.down ? root.primaryDarkColor
                                           : uploadButton.hovered ? "#5878F7" : root.primaryColor
                                }
                                contentItem: Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "↑"
                                        color: "white"
                                        font.pixelSize: 17
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "上传文件"
                                        color: "white"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                onClicked: root.uploadRequested()
                            }
                        }

                        // 概览卡片
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            spacing: 10

                            Repeater {
                                model: [
                                    { label: "文件总数", value: uploadManager.cloudFileCount,
                                      note: uploadManager.loadingFiles ? "正在刷新…" : "当前目录及子目录",
                                      icon: "▤", tint: "#EEF2FF", ink: "#4B6EF5" },
                                    { label: "已完成同步", value: uploadManager.syncedFileCount,
                                      note: "云端已保存", icon: "✓", tint: "#EAF8F2", ink: "#28B985" },
                                    { label: "正在同步", value: uploadManager.syncingFileCount,
                                      note: uploadManager.syncingFileCount > 0 ? "任务进行中" : "暂无同步任务",
                                      icon: "↻", tint: "#FFF5E8", ink: "#E8A044" }
                                ]
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 76
                                    radius: 10
                                    color: "#FFFFFF"
                                    border.color: "#EDF1F7"

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 11
                                        spacing: 9
                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 9
                                            color: modelData.tint
                                            anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.icon
                                                color: modelData.ink
                                                font.pixelSize: 16
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text {
                                                text: modelData.label
                                                color: root.textMidColor
                                                font.pixelSize: 10
                                            }
                                            Row {
                                                spacing: 7
                                                Text {
                                                    text: modelData.value
                                                    color: root.textDarkColor
                                                    font.pixelSize: 18
                                                    font.weight: Font.DemiBold
                                                }
                                                Text {
                                                    text: modelData.note
                                                    color: "#A2AEC0"
                                                    font.pixelSize: 9
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 3
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 文件列表卡片
                        Rectangle {
                            id: fileListCard
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 11
                            color: "#FFFFFF"
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // 列表标题与筛选
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 49
                                    Layout.leftMargin: 16
                                    Layout.rightMargin: 14
                                    spacing: 12

                                    Text {
                                        text: "文件列表"
                                        color: root.textDarkColor
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: fileListView.count + " 个项目"
                                        color: "#A7B2C2"
                                        font.pixelSize: 10
                                    }
                                    Item { Layout.fillWidth: true }

                                    Repeater {
                                        model: ["全部", "文件", "文件夹"]
                                        delegate: Item {
                                            width: 43
                                            height: 28
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: root.currentFilter === modelData ? "#EEF2FF" : (filterMouse.containsMouse ? "#F7F9FD" : "transparent")
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: root.currentFilter === modelData ? root.primaryColor : "#8592A8"
                                                font.pixelSize: 10
                                                font.weight: root.currentFilter === modelData ? Font.DemiBold : Font.Normal
                                            }
                                            MouseArea {
                                                id: filterMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.currentFilter = modelData
                                            }
                                        }
                                    }

                                    Button {
                                        Layout.preferredWidth: 27
                                        Layout.preferredHeight: 27
                                        hoverEnabled: true
                                        background: Rectangle {
                                            radius: 6
                                            color: parent.hovered ? "#F2F5FA" : "transparent"
                                        }
                                        contentItem: Text {
                                            text: "⋯"
                                            color: "#91A0B5"
                                            font.pixelSize: 19
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: root.refreshRequested()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: "#EEF1F6"
                                }

                                // 表头
                                Item {
                                    Layout.fillWidth: true
                                    height: 38
                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 13
                                        spacing: 0
                                        Text {
                                            width: parent.width - 320
                                            text: "名称"
                                            color: "#9AA6B8"
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            width: 130
                                            text: "修改时间"
                                            color: "#9AA6B8"
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            width: 72
                                            text: "大小"
                                            color: "#9AA6B8"
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            width: 85
                                            text: "同步状态"
                                            color: "#9AA6B8"
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text { width: 33; text: "" }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: "#F1F3F8"
                                }

                                ListView {
                                    id: fileListView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: root.fileModelSource
                                    spacing: 0
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Item {
                                        id: fileRow
                                        width: fileListView.width

                                        readonly property int informationHeight: 56
                                        property string filePath: typeof path === "undefined" || path === null ? "" : path.toString()
                                        property string serverPreviewType: typeof previewType === "undefined" || previewType === null ? "" : previewType.toString()
                                        property string serverMimeType: typeof mimeType === "undefined" || mimeType === null ? "" : mimeType.toString()
                                        property bool hasPreview: kind !== "folder"
                                        property bool isImage: hasPreview && (serverPreviewType === "image"
                                                               || (serverPreviewType.length === 0 && root.isImageExtension(ext)))
                                        property bool isText: hasPreview && !isImage && (serverPreviewType === "text"
                                                              || (serverPreviewType.length === 0 && root.isTextExtension(ext)))
                                        property string contentSource: (isImage || isText) && filePath.length > 0
                                                                       ? uploadManager.fileContentUrl(filePath) : ""
                                        property string imageSource: isImage ? contentSource : ""
                                        property string textSource: {
                                            if (!isText || contentSource.length === 0)
                                                return ""
                                            if (contentSource.indexOf("http://") !== 0 && contentSource.indexOf("https://") !== 0)
                                                return contentSource
                                            return contentSource + (contentSource.indexOf("?") >= 0 ? "&" : "?")
                                                   + "maxBytes=" + root.textPreviewByteLimit
                                        }

                                        // 使用图片原始 implicit 尺寸计算显示大小，小图不放大，大图等比缩小。
                                        property real availableImageWidth: Math.max(1, previewRow.width - 12)
                                        property real imageScale: {
                                            if (previewImage.status !== Image.Ready
                                                    || previewImage.implicitWidth <= 0
                                                    || previewImage.implicitHeight <= 0)
                                                return 1
                                            return Math.min(1,
                                                            availableImageWidth / previewImage.implicitWidth,
                                                            Math.max(1, root.maxImagePreviewHeight) / previewImage.implicitHeight)
                                        }
                                        property real imageContentWidth: previewImage.status === Image.Ready
                                                                         ? Math.max(1, Math.round(previewImage.implicitWidth * imageScale))
                                                                         : availableImageWidth
                                        property real imageContentHeight: previewImage.status === Image.Ready
                                                                          ? Math.max(1, Math.round(previewImage.implicitHeight * imageScale))
                                                                          : 96

                                        property string textContent: ""
                                        property string textLoadError: ""
                                        property bool textLoading: false
                                        property bool textTruncated: false
                                        property bool copySucceeded: false
                                        property int textRequestGeneration: 0
                                        property real previewHeight: isImage ? Math.ceil(imageContentHeight + 12)
                                                                              : (isText ? Math.min(260, Math.max(96, Math.ceil(textPreviewEdit.contentHeight + 50))) : 52)
                                        property bool rowVisible: root.matchesFilter(kind) && root.matchesSearch(name)

                                        height: rowVisible ? informationHeight + (hasPreview ? previewHeight + 10 : 0) : 0
                                        visible: rowVisible

                                        function loadTextPreview() {
                                            var source = textSource
                                            var generation = ++textRequestGeneration
                                            textContent = ""
                                            textLoadError = ""
                                            textTruncated = false
                                            copySucceeded = false

                                            if (!isText) {
                                                textLoading = false
                                                return
                                            }
                                            if (source.length === 0) {
                                                textLoading = false
                                                textLoadError = "暂无文本文件地址"
                                                return
                                            }

                                            textLoading = true
                                            var request = new XMLHttpRequest()
                                            request.onreadystatechange = function() {
                                                if (request.readyState !== XMLHttpRequest.DONE
                                                        || generation !== textRequestGeneration)
                                                    return

                                                textLoading = false
                                                var remoteRequest = source.indexOf("http://") === 0 || source.indexOf("https://") === 0
                                                var succeeded = (request.status >= 200 && request.status < 300)
                                                                || (request.status === 0 && !remoteRequest)
                                                if (succeeded) {
                                                    textContent = request.responseText === undefined ? "" : request.responseText
                                                    try {
                                                        textTruncated = request.getResponseHeader("X-Preview-Truncated") === "1"
                                                    } catch (error) {
                                                        textTruncated = false
                                                    }
                                                } else {
                                                    textLoadError = request.status > 0
                                                            ? "文本加载失败（HTTP " + request.status + "）"
                                                            : "文本加载失败，请检查网络或文件地址"
                                                }
                                            }
                                            request.open("GET", source, true)
                                            request.send()
                                        }

                                        function copyTextPreview() {
                                            if (textContent.length === 0)
                                                return

                                            // 在切换焦点前保存选区状态。
                                            var hasSelection = textPreviewEdit.selectedText.length > 0
                                            var selectionStart = textPreviewEdit.selectionStart
                                            var selectionEnd = textPreviewEdit.selectionEnd

                                            textPreviewEdit.forceActiveFocus()

                                            if (hasSelection) {
                                                // 恢复用户选区，避免焦点变化造成选区丢失。
                                                textPreviewEdit.select(selectionStart, selectionEnd)
                                            } else {
                                                // 没有选区时，复制当前已加载的预览全文。
                                                textPreviewEdit.selectAll()
                                            }

                                            textPreviewEdit.copy()

                                            if (hasSelection) {
                                                // 保留用户原有选区，方便再次复制或调整。
                                                textPreviewEdit.select(selectionStart, selectionEnd)
                                            } else {
                                                // 如果选区是本次 selectAll() 临时创建的，复制后恢复无选区状态。
                                                textPreviewEdit.deselect()
                                            }

                                            copySucceeded = true
                                            copyFeedbackTimer.restart()
                                        }

                                        onTextSourceChanged: {
                                            textRequestGeneration += 1
                                            textContent = ""
                                            textLoadError = ""
                                            textLoading = isText && textSource.length > 0
                                            textLoadTimer.restart()
                                        }
                                        Component.onCompleted: textLoadTimer.start()
                                        Component.onDestruction: textRequestGeneration += 1

                                        Rectangle {
                                            anchors.fill: parent
                                            color: root.selectedName === name ? "#F4F7FF" : (rowMouse.containsMouse ? "#FAFBFE" : "#FFFFFF")
                                        }
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: "#F3F5F9"
                                        }

                                        MouseArea {
                                            id: rowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selectFile(name, kind, modified, size, status, ext)
                                            onDoubleClicked: {
                                                if (kind === "folder") {
                                                    root.openFolder(fileRow.filePath)
                                                    return
                                                }

                                                // 文件预览由 Main.qml 的全屏对话框统一处理；
                                                // 不支持的二进制类型会在 openPreview() 中直接忽略。
                                                root.previewRequested(name, fileRow.filePath,
                                                                      fileRow.serverPreviewType,
                                                                      ext, fileRow.serverMimeType)
                                            }
                                        }

                                        // 第一行：名称、修改时间、大小和同步状态。
                                        Row {
                                            id: informationRow
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 16
                                            anchors.rightMargin: 13
                                            height: fileRow.informationHeight
                                            spacing: 0

                                            Row {
                                                width: parent.width - 320
                                                height: parent.height
                                                spacing: 10

                                                Rectangle {
                                                    width: 34
                                                    height: 34
                                                    radius: 8
                                                    color: kind === "folder" ? "#FFF5E3" : iconBg
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: kind === "folder" ? "▰" : ext
                                                        color: kind === "folder" ? "#E9AD4E" : iconColor
                                                        font.pixelSize: kind === "folder" ? 19 : 9
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                                Column {
                                                    width: parent.width - 47
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 3
                                                    Text {
                                                        width: parent.width
                                                        text: name
                                                        color: root.textDarkColor
                                                        font.pixelSize: 11
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: kind === "folder" ? "文件夹" : ("." + ext.toLowerCase() + " 文件")
                                                        color: "#AAB4C3"
                                                        font.pixelSize: 9
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            Text {
                                                width: 130
                                                height: parent.height
                                                text: modified
                                                color: "#8492A8"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Text {
                                                width: 72
                                                height: parent.height
                                                text: size
                                                color: "#8492A8"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Row {
                                                width: 85
                                                height: parent.height
                                                spacing: 5
                                                anchors.verticalCenter: parent.verticalCenter
                                                Rectangle {
                                                    width: 6
                                                    height: 6
                                                    radius: 3
                                                    color: status === "已同步" ? root.successColor : (status === "同步中" ? root.warningColor : "#A7B2C2")
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: status
                                                    color: status === "已同步" ? "#42A985" : (status === "同步中" ? "#D79A43" : "#8996AA")
                                                    font.pixelSize: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                            Button {
                                                id: rowMenuButton
                                                width: 33
                                                height: 32
                                                anchors.verticalCenter: parent.verticalCenter
                                                hoverEnabled: true
                                                background: Rectangle {
                                                    radius: 6
                                                    color: rowMenuButton.down || rowMenu.opened ? "#E4EBFF"
                                                           : rowMenuButton.hovered ? "#EEF2FA" : "transparent"
                                                }
                                                contentItem: Text {
                                                    text: "⋯"
                                                    color: rowMenu.opened ? root.primaryColor : "#9AA6B8"
                                                    font.pixelSize: 18
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                onClicked: {
                                                    root.selectFile(name, kind, modified, size, status, ext)
                                                    rowMenu.fileName = name
                                                    rowMenu.fileKind = kind
                                                    rowMenu.filePath = root.cloudItemPath(fileRow.filePath, name)
                                                    rowMenu.popup(rowMenuButton,
                                                                  rowMenuButton.width - rowMenu.width,
                                                                  rowMenuButton.height + 6)
                                                }
                                            }
                                        }

                                        // 第二行：图片按原始比例显示，文本可阅读复制，仅二进制文件使用占位卡片。
                                        Item {
                                            id: previewRow
                                            anchors.top: informationRow.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 60
                                            anchors.rightMargin: 46
                                            height: fileRow.previewHeight
                                            visible: fileRow.hasPreview

                                            // 图片预览：高度随原始宽高比变化，不使用固定高度或裁切填充。
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: fileRow.isImage
                                                radius: 8
                                                color: root.selectedName === name ? "#EDF2FC" : "#F5F7FB"
                                                border.color: "#E4EAF3"
                                                border.width: 1
                                                clip: true

                                                Image {
                                                    id: previewImage
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: fileRow.imageContentWidth
                                                    height: fileRow.imageContentHeight
                                                    source: fileRow.imageSource
                                                    asynchronous: true
                                                    cache: true
                                                    autoTransform: true
                                                    fillMode: Image.PreserveAspectFit
                                                    horizontalAlignment: Image.AlignHCenter
                                                    verticalAlignment: Image.AlignVCenter
                                                    smooth: true
                                                    mipmap: true

                                                    // 不用显示尺寸覆盖 sourceSize，保留原始 implicit 尺寸及宽高比。
                                                }

                                                BusyIndicator {
                                                    anchors.centerIn: parent
                                                    width: 24
                                                    height: 24
                                                    running: previewImage.status === Image.Loading
                                                    visible: running
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: fileRow.imageSource.length === 0 || previewImage.status === Image.Error
                                                    text: fileRow.imageSource.length === 0 ? "暂无图片地址" : "图片加载失败"
                                                    color: "#98A5B9"
                                                    font.pixelSize: 10
                                                }
                                            }

                                            // 文本预览：最多读取前 64 KB，支持滚动、鼠标选择和复制。
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: fileRow.isText
                                                radius: 8
                                                color: root.selectedName === name ? "#F0F4FD" : "#F8FAFD"
                                                border.color: "#E3EAF4"
                                                border.width: 1
                                                clip: true

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 11
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 76
                                                    anchors.top: parent.top
                                                    height: 33
                                                    text: fileRow.textTruncated
                                                          ? "文本预览（前 " + Math.round(root.textPreviewByteLimit / 1024) + " KB）"
                                                          : "文本预览"
                                                    color: "#7D8BA1"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Medium
                                                    verticalAlignment: Text.AlignVCenter
                                                    elide: Text.ElideRight
                                                }

                                                Button {
                                                    id: copyTextButton
                                                    focusPolicy: Qt.NoFocus
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 4
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 7
                                                    width: 59
                                                    height: 25
                                                    enabled: !fileRow.textLoading && fileRow.textContent.length > 0
                                                    hoverEnabled: true
                                                    background: Rectangle {
                                                        radius: 6
                                                        color: !copyTextButton.enabled ? "#EDF1F6"
                                                               : copyTextButton.down ? "#E1E8FA"
                                                               : copyTextButton.hovered ? "#E8EEFF" : "#F0F4FF"
                                                        border.color: "#DCE5F5"
                                                    }
                                                    contentItem: Text {
                                                        text: fileRow.copySucceeded ? "已复制" : "复制"
                                                        color: copyTextButton.enabled ? root.primaryColor : "#A7B2C2"
                                                        font.pixelSize: 9
                                                        font.weight: Font.Medium
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    onClicked: fileRow.copyTextPreview()
                                                    ToolTip.visible: hovered
                                                    ToolTip.text: "复制选中文本；未选择时复制全部"
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 32
                                                    height: 1
                                                    color: "#E9EEF6"
                                                }

                                                Flickable {
                                                    id: textViewport
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.leftMargin: 9
                                                    anchors.rightMargin: 9
                                                    anchors.topMargin: 38
                                                    anchors.bottomMargin: 7
                                                    visible: !fileRow.textLoading && fileRow.textLoadError.length === 0
                                                             && fileRow.textContent.length > 0
                                                    clip: true
                                                    contentWidth: width
                                                    contentHeight: textPreviewEdit.contentHeight
                                                    boundsBehavior: Flickable.StopAtBounds
                                                    flickableDirection: Flickable.VerticalFlick

                                                    TextEdit {
                                                        id: textPreviewEdit
                                                        x: 2
                                                        width: Math.max(1, textViewport.width - 4)
                                                        height: contentHeight
                                                        text: fileRow.textContent

                                                        readOnly: true
                                                        selectByMouse: true
                                                        selectByKeyboard: true
                                                        cursorVisible: false

                                                        color: "#4C5C74"
                                                        selectionColor: root.primaryColor
                                                        selectedTextColor: "#FFFFFF"

                                                        font.family: "monospace"
                                                        font.pixelSize: 10
                                                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                                        textFormat: TextEdit.PlainText

                                                        // 阻止 TextEdit 提前执行默认的 Ctrl+C，
                                                        // 让下面的 Keys.onPressed 统一处理。
                                                        Keys.onShortcutOverride: function(event) {
                                                            if (event.key === Qt.Key_C
                                                                    && (event.modifiers & Qt.ControlModifier)) {
                                                                event.accepted = true
                                                            }
                                                        }

                                                        Keys.onPressed: function(event) {
                                                            if (event.key === Qt.Key_C
                                                                    && (event.modifiers & Qt.ControlModifier)) {
                                                                if (!event.isAutoRepeat)
                                                                    fileRow.copyTextPreview()

                                                                // 阻止事件继续传递，避免重复复制。
                                                                event.accepted = true
                                                            }
                                                        }
                                                    }

                                                    ScrollBar.vertical: ScrollBar {
                                                        policy: ScrollBar.AsNeeded
                                                    }
                                                }

                                                BusyIndicator {
                                                    anchors.centerIn: parent
                                                    width: 22
                                                    height: 22
                                                    running: fileRow.textLoading
                                                    visible: running
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    width: parent.width - 24
                                                    visible: !fileRow.textLoading && (fileRow.textLoadError.length > 0
                                                             || fileRow.textContent.length === 0)
                                                    text: fileRow.textLoadError.length > 0
                                                          ? fileRow.textLoadError : "文本内容为空"
                                                    color: fileRow.textLoadError.length > 0 ? "#C77B76" : "#98A5B9"
                                                    font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignHCenter
                                                    wrapMode: Text.WordWrap
                                                }
                                            }

                                            // 非图片、非文本文件按二进制文件处理。
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: !fileRow.isImage && !fileRow.isText
                                                radius: 8
                                                color: root.selectedName === name ? "#F0F4FD" : "#F8FAFD"
                                                border.color: "#EAF0F6"
                                                border.width: 1

                                                Rectangle {
                                                    id: previewTypeIcon
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 11
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 32
                                                    height: 32
                                                    radius: 7
                                                    color: iconBg

                                                    Text {
                                                        anchors.centerIn: parent
                                                        width: parent.width - 4
                                                        text: ext
                                                        color: iconColor
                                                        font.pixelSize: 8
                                                        font.weight: Font.DemiBold
                                                        horizontalAlignment: Text.AlignHCenter
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Column {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 54
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 3

                                                    Text {
                                                        width: parent.width
                                                        text: root.fileTypeDescription(ext)
                                                        color: "#596981"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: "二进制文件暂不支持内嵌预览，双击可打开"
                                                        color: "#A0ADBE"
                                                        font.pixelSize: 9
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            Timer {
                                                id: textLoadTimer
                                                interval: 0
                                                repeat: false
                                                onTriggered: fileRow.loadTextPreview()
                                            }
                                            Timer {
                                                id: copyFeedbackTimer
                                                interval: 1500
                                                repeat: false
                                                onTriggered: fileRow.copySucceeded = false
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 34
                                    color: "#FCFDFF"
                                    Rectangle {
                                        anchors.top: parent.top
                                        width: parent.width
                                        height: 1
                                        color: "#EEF1F6"
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 6
                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: uploadManager.webSocketConnected
                                                   ? root.successColor : root.warningColor
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: uploadManager.syncingFileCount > 0
                                                  ? uploadManager.syncingFileCount + " 个文件正在同步"
                                                  : (uploadManager.webSocketConnected
                                                     ? "实时同步已连接，当前目录文件均已安全保存至云端"
                                                     : uploadManager.webSocketStatus)
                                            color: "#9AA7B9"
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Item { width: 1; height: 1 }
                                        Text {
                                            text: uploadManager.webSocketConnected
                                                  ? "WebSocket 推送正常" : "手动刷新仍可使用"
                                            color: "#AAB4C3"
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                            // ============================================================
                            // 边框覆盖层：确保内部控件不会遮挡外边框
                            // ============================================================
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 1
                                border.color: "#E9EEF6"
                                antialiasing: true
                                z: 100
                            }
                        }
                    }
                }

                // ========================================================
                // 右侧详情面板（窄窗口自动隐藏）
                // ========================================================
                Rectangle {
                    id: detailsPanel
                    width: 270
                    height: parent.height
                    visible: root.detailsVisible && workspace.width >= 850
                    color: "#FFFFFF"
                    border.color: "#E9EEF6"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 0

                        Row {
                            width: parent.width
                            height: 35
                            Text {
                                text: "文件详情"
                                color: root.textDarkColor
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Button {
                                width: 27
                                height: 27
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 6
                                    color: parent.hovered ? "#F2F5FA" : "transparent"
                                }
                                contentItem: Text {
                                    text: "×"
                                    color: "#9AA6B8"
                                    font.pixelSize: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: root.detailsVisible = false
                            }
                        }

                        Item { width: 1; height: 19 }

                        Rectangle {
                            width: 64
                            height: 64
                            radius: 15
                            color: root.selectedKind === "folder" ? "#FFF5E3" : "#EEF2FF"
                            anchors.horizontalCenter: parent.horizontalCenter
                            Text {
                                anchors.centerIn: parent
                                text: root.selectedKind === "folder" ? "▰" : root.selectedExt
                                color: root.selectedKind === "folder" ? "#E9AD4E" : root.primaryColor
                                font.pixelSize: root.selectedKind === "folder" ? 30 : 15
                                font.weight: Font.DemiBold
                            }
                        }

                        Item { width: 1; height: 12 }
                        Text {
                            width: parent.width
                            text: root.selectedName
                            color: root.textDarkColor
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                        }
                        Text {
                            width: parent.width
                            text: root.selectedExt
                            color: "#A2AEC0"
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 5
                        }

                        Item { width: 1; height: 19 }
                        Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
                        Item { width: 1; height: 16 }

                        Text {
                            text: "基本信息"
                            color: "#8D9AB0"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 10 }

                        Repeater {
                            model: [
                                { key: "文件大小", value: root.selectedSize },
                                { key: "修改时间", value: root.selectedModified },
                                { key: "所在位置", value: root.currentLocationText }
                            ]
                            delegate: Row {
                                width: parent.width
                                height: 31
                                Text {
                                    id: infoKey
                                    text: modelData.key
                                    color: "#9AA6B8"
                                    font.pixelSize: 10
                                }
                                Item {
                                    width: Math.max(0, parent.width - infoKey.implicitWidth - infoValue.implicitWidth)
                                    height: 1
                                }
                                Text {
                                    id: infoValue
                                    text: modelData.value
                                    color: "#596981"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 32
                            Text {
                                text: "同步状态"
                                color: "#9AA6B8"
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Row {
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.selectedStatus === "已同步" ? root.successColor : root.warningColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.selectedStatus
                                    color: root.selectedStatus === "已同步" ? "#42A985" : "#D79A43"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Item { width: 1; height: 16 }
                        Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
                        Item { width: 1; height: 16 }
                        Text {
                            text: "快捷操作"
                            color: "#8D9AB0"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 10 }

                        Button {
                            width: parent.width
                            height: 37
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? "#F2F5FF" : "#FFFFFF"
                                border.color: "#E2E9F6"
                            }
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "↓"; color: root.primaryColor; font.pixelSize: 16 }
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "下载到本地"; color: "#53637D"; font.pixelSize: 11 }
                            }
                            onClicked: root.downloadRequested(root.selectedName)
                        }
                        Item { width: 1; height: 8 }
                        Button {
                            width: parent.width
                            height: 37
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? "#F2F5FF" : "#FFFFFF"
                                border.color: "#E2E9F6"
                            }
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "↗"; color: root.primaryColor; font.pixelSize: 15 }
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "分享"; color: "#53637D"; font.pixelSize: 11 }
                            }
                            onClicked: root.shareRequested(root.selectedName)
                        }
                        Item { width: 1; height: 8 }
                        Button {
                            width: parent.width
                            height: 37
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? "#FFF3F2" : "#FFFFFF"
                                border.color: "#F1E5E4"
                            }
                            contentItem: Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "⌫"; color: "#E47772"; font.pixelSize: 14 }
                                Text { anchors.verticalCenter:parent.verticalCenter;text: "删除"; color: "#D76D68"; font.pixelSize: 11 }
                            }
                            onClicked: root.deleteRequested(root.selectedName)
                        }

                        Item { width: 1; height: 8; }

                        Rectangle {
                            width: parent.width
                            height: 76
                            radius: 9
                            color: "#F8FAFF"
                            border.color: "#EBF0FA"
                            Column {
                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: 5
                                Text {
                                    text: "安全同步"
                                    color: root.textDarkColor
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: "文件在本地与云端之间加密传输，确保数据随时保持一致。"
                                    color: "#929FB3"
                                    font.pixelSize: 9
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.2
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // 文件行“更多操作”菜单：打开和下载直接使用当前行的云端相对路径。
    // ============================================================
    Menu {
        id: rowMenu

        property string fileName: ""
        property string fileKind: ""
        property string filePath: ""

        width: 220
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        transformOrigin: Item.TopRight

        background: Rectangle {
            color: "#FFFFFF"
            radius: 12
            border.width: 1
            border.color: "#E4EAF4"
            antialiasing: true
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 120
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "scale"
                from: 0.96
                to: 1.0
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
        exit: Transition {
            NumberAnimation {
                properties: "opacity"
                from: 1.0
                to: 0.0
                duration: 90
            }
        }

        // 菜单标题：显示当前行文件名，不响应点击。
        MenuItem {
            id: menuHeader
            enabled: false
            hoverEnabled: false
            implicitHeight: 51
            leftPadding: 10
            rightPadding: 10
            topPadding: 7
            bottomPadding: 7
            indicator: null
            background: Item {}

            contentItem: Column {
                spacing: 3

                Text {
                    text: "文件操作"
                    color: "#8B98AD"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: rowMenu.fileName.length > 0 ? rowMenu.fileName : "当前文件"
                    color: root.textDarkColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }
            }
        }

        MenuSeparator {
            topPadding: 2
            bottomPadding: 5
            contentItem: Rectangle {
                implicitHeight: 1
                color: "#EDF1F6"
            }
        }

        MenuItem {
            id: openMenuItem
            text: rowMenu.fileKind === "folder" ? "打开文件夹"
                  : (uploadManager.openingFile ? "正在打开…" : "打开文件")
            enabled: rowMenu.fileKind === "folder" || !uploadManager.openingFile
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: openMenuItem.down ? "#E5EBFF"
                       : openMenuItem.hovered ? "#F1F4FF" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: rowMenu.fileKind === "folder" ? "#FFF4E2" : "#EEF2FF"

                    Text {
                        anchors.centerIn: parent
                        text: rowMenu.fileKind === "folder" ? "▰" : "↗"
                        color: rowMenu.fileKind === "folder" ? "#E2A345" : root.primaryColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: openMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: openMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }

            onTriggered: {
                if (rowMenu.filePath.length === 0)
                    return
                if (rowMenu.fileKind === "folder")
                    root.openFolder(rowMenu.filePath)
                else
                    uploadManager.openFile(rowMenu.filePath)
            }
        }

        MenuItem {
            id: downloadMenuItem
            text: uploadManager.downloading ? "正在下载…" : "下载到本地"
            enabled: !uploadManager.downloading
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: downloadMenuItem.down ? "#E5EBFF"
                       : downloadMenuItem.hovered ? "#F1F4FF" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: "#EEF2FF"

                    Text {
                        anchors.centerIn: parent
                        text: "↓"
                        color: root.primaryColor
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: downloadMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: downloadMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }

            onTriggered: root.requestDownload(rowMenu.filePath, rowMenu.fileKind)
        }

        MenuItem {
            id: shareMenuItem
            text: "分享"
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: shareMenuItem.down ? "#E5EBFF"
                       : shareMenuItem.hovered ? "#F1F4FF" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: "#EEF2FF"

                    Text {
                        anchors.centerIn: parent
                        text: "↗"
                        color: root.primaryColor
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: shareMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: shareMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }

        MenuSeparator {
            topPadding: 5
            bottomPadding: 5
            contentItem: Rectangle {
                implicitHeight: 1
                color: "#EDF1F6"
            }
        }

        MenuItem {
            id: renameMenuItem
            text: uploadManager.renaming ? "正在重命名…" : "重命名"
            enabled: !uploadManager.renaming
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: renameMenuItem.down ? "#E9EEF7"
                       : renameMenuItem.hovered ? "#F5F7FB" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: "#F2F5F9"

                    Text {
                        anchors.centerIn: parent
                        text: "✎"
                        color: "#71809B"
                        font.pixelSize: 15
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: renameMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: renameMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }

            onTriggered: {
                if (rowMenu.filePath.length === 0)
                    return
                renameDialog.openFor(rowMenu.filePath, rowMenu.fileName, rowMenu.fileKind)
            }
        }

        MenuItem {
            id: moveMenuItem
            text: uploadManager.moving ? "正在移动…" : "移动到"
            enabled: !uploadManager.moving
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: moveMenuItem.down ? "#E9EEF7"
                       : moveMenuItem.hovered ? "#F5F7FB" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: "#F2F5F9"

                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        color: "#71809B"
                        font.pixelSize: 16
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: moveMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: moveMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }

            onTriggered: {
                if (rowMenu.filePath.length === 0)
                    return
                moveDialog.openFor(rowMenu.filePath, rowMenu.fileName, rowMenu.fileKind)
            }
        }

        MenuItem {
            id: favoriteMenuItem
            text: "添加到收藏"
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: favoriteMenuItem.down ? "#E9EEF7"
                       : favoriteMenuItem.hovered ? "#F5F7FB" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: "#F2F5F9"

                    Text {
                        anchors.centerIn: parent
                        text: "☆"
                        color: "#71809B"
                        font.pixelSize: 17
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: favoriteMenuItem.text
                    color: "#40516B"
                    font.pixelSize: 12
                    font.weight: favoriteMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }

        MenuSeparator {
            topPadding: 5
            bottomPadding: 5
            contentItem: Rectangle {
                implicitHeight: 1
                color: "#EDF1F6"
            }
        }

        MenuItem {
            id: deleteMenuItem
            text: "删除"
            implicitHeight: 40
            hoverEnabled: true
            leftPadding: 6
            rightPadding: 10
            topPadding: 4
            bottomPadding: 4
            indicator: null

            background: Rectangle {
                radius: 8
                color: deleteMenuItem.down ? "#FCE7E5"
                       : deleteMenuItem.hovered ? "#FFF3F2" : "transparent"
            }
            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 29
                    Layout.preferredHeight: 29
                    radius: 7
                    color: deleteMenuItem.hovered ? "#FCE6E4" : "#FFF1F0"

                    Text {
                        anchors.centerIn: parent
                        text: "⌫"
                        color: "#DC716C"
                        font.pixelSize: 15
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: deleteMenuItem.text
                    color: "#D76561"
                    font.pixelSize: 12
                    font.weight: deleteMenuItem.hovered ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }
    }

    // 示例文件数据：接入 C++ 后可替换为 QAbstractListModel
    ListModel {
        id: fileModel
        dynamicRoles: true
        /*
        ListElement {
            name: "项目资料"
            kind: "folder"
            ext: "文件夹"
            modified: "今天 14:28"
            size: "18 个文件"
            status: "已同步"
            iconBg: "#EEF2FF"
            iconColor: "#4B6EF5"
        }
        ListElement {
            name: "产品原型.fig"
            kind: "file"
            ext: "FIG"
            modified: "今天 13:52"
            size: "8.6 MB"
            status: "已同步"
            iconBg: "#F1ECFF"
            iconColor: "#8A6AE8"
        }
        ListElement {
            name: "客户需求文档.docx"
            kind: "file"
            ext: "DOCX"
            modified: "今天 11:20"
            size: "256 KB"
            status: "已同步"
            iconBg: "#EAF2FF"
            iconColor: "#4C83D9"
        }
        ListElement {
            name: "项目方案.pdf"
            kind: "file"
            ext: "PDF"
            modified: "昨天 17:46"
            size: "2.4 MB"
            status: "已同步"
            iconBg: "#FFF0EF"
            iconColor: "#E47772"
        }
        ListElement {
            name: "会议记录.xlsx"
            kind: "file"
            ext: "XLSX"
            modified: "昨天 16:08"
            size: "128 KB"
            status: "同步中"
            iconBg: "#EAF8F2"
            iconColor: "#28A879"
        }
        ListElement {
            name: "设计素材"
            kind: "folder"
            ext: "文件夹"
            modified: "11 月 03 日"
            size: "32 个文件"
            status: "已同步"
            iconBg: "#EEF2FF"
            iconColor: "#4B6EF5"
        }
        ListElement {
            name: "头像素材.zip"
            kind: "file"
            ext: "ZIP"
            modified: "11 月 02 日"
            size: "36.2 MB"
            status: "等待同步"
            iconBg: "#FFF5E8"
            iconColor: "#D99A42"
        }
        ListElement {
            name: "2026 年度计划.pptx"
            kind: "file"
            ext: "PPTX"
            modified: "10 月 30 日"
            size: "4.1 MB"
            status: "已同步"
            iconBg: "#FFF0E9"
            iconColor: "#E58A54"
        }
        */
    }


    // 新建文件夹弹窗：名称校验、异步状态和错误提示均在当前操作上下文中完成。
    Dialog {
        id: createFolderDialog
        anchors.centerIn: parent
        width: 400
        height: 282
        padding: 0
        modal: true
        focus: true
        closePolicy: uploadManager.creatingFolder ? Popup.NoAutoClose : Popup.CloseOnEscape

        property string errorText: ""

        function submit() {
            if (uploadManager.creatingFolder)
                return

            var folderName = folderNameField.text.trim()
            var validationError = root.validateFolderName(folderName)
            if (validationError.length > 0) {
                errorText = validationError
                folderNameField.forceActiveFocus()
                return
            }

            errorText = ""
            root.createFolderRequested(folderName)
        }

        onOpened: {
            folderNameField.text = "新建文件夹"
            errorText = ""
            folderNameField.forceActiveFocus()
            folderNameField.selectAll()
        }

        Overlay.modal: Rectangle {
            color: "#66000000"
        }

        background: Rectangle {
            color: "#FFFFFF"
            radius: 13
            border.width: 1
            border.color: "#E4EAF4"
            antialiasing: true
        }

        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 11

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: "新建文件夹"
                        color: root.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }

                    Button {
                        id: folderDialogCloseButton
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        enabled: !uploadManager.creatingFolder
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 6
                            color: folderDialogCloseButton.hovered ? "#F2F5FA" : "transparent"
                        }
                        contentItem: Text {
                            text: "×"
                            color: folderDialogCloseButton.enabled ? "#8D9AB0" : "#C8CFDA"
                            font.pixelSize: 19
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: createFolderDialog.close()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "将在“" + root.currentLocationText + "”中创建一个空文件夹。"
                    color: root.textMidColor
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 8
                    color: folderNameField.activeFocus ? "#FAFBFF" : "#FFFFFF"
                    border.width: 1
                    border.color: createFolderDialog.errorText.length > 0 ? "#DF827C"
                                  : (folderNameField.activeFocus ? root.primaryColor : "#DDE5F2")

                    TextField {
                        id: folderNameField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        color: root.textDarkColor
                        font.pixelSize: 12
                        selectByMouse: true
                        selectedTextColor: "#FFFFFF"
                        selectionColor: root.primaryColor
                        verticalAlignment: TextInput.AlignVCenter
                        background: Item {}
                        onTextChanged: createFolderDialog.errorText = ""
                        onAccepted: createFolderDialog.submit()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    text: createFolderDialog.errorText.length > 0
                          ? createFolderDialog.errorText
                          : "名称需符合系统文件命名规则，最多 100 个字符。"
                    color: createFolderDialog.errorText.length > 0 ? "#D76D68" : "#9AA6B8"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    spacing: 9

                    Item { Layout.fillWidth: true }

                    Button {
                        id: cancelCreateFolderButton
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.creatingFolder
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: cancelCreateFolderButton.hovered ? "#F4F6FA" : "#FFFFFF"
                            border.color: "#DFE6F1"
                        }
                        contentItem: Text {
                            text: "取消"
                            color: cancelCreateFolderButton.enabled ? "#596981" : "#A7B2C2"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: createFolderDialog.close()
                    }

                    Button {
                        id: confirmCreateFolderButton
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.creatingFolder
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: !confirmCreateFolderButton.enabled ? "#AAB8E8"
                                   : confirmCreateFolderButton.down ? root.primaryDarkColor
                                   : confirmCreateFolderButton.hovered ? "#5878F7" : root.primaryColor
                        }
                        contentItem: Item {
                            implicitWidth: createContentRow.implicitWidth
                            implicitHeight: createContentRow.implicitHeight

                            Row {
                                id: createContentRow
                                anchors.centerIn: parent
                                spacing: 6

                                BusyIndicator {
                                    width: 16
                                    height: 16
                                    running: uploadManager.creatingFolder
                                    visible: running
                                }

                                Text {
                                    text: uploadManager.creatingFolder ? "创建中…" : "创建"
                                    color: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold

                                    height: 16
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                        onClicked: createFolderDialog.submit()
                    }
                }
            }
        }
    }

    // 重命名弹窗：文件和文件夹共用，网络请求期间禁止重复提交或关闭。
    Dialog {
        id: renameDialog
        anchors.centerIn: parent
        width: 400
        height: 282
        padding: 0
        modal: true
        focus: true
        closePolicy: uploadManager.renaming ? Popup.NoAutoClose : Popup.CloseOnEscape

        property string originalPath: ""
        property string originalName: ""
        property string itemKind: "file"
        property string errorText: ""

        function openFor(path, name, kind) {
            originalPath = path === undefined || path === null ? "" : path.toString()
            originalName = name === undefined || name === null ? "" : name.toString()
            itemKind = kind === "folder" ? "folder" : "file"
            errorText = ""
            open()
        }

        function submit() {
            if (uploadManager.renaming || originalPath.length === 0)
                return

            var newName = renameNameField.text.trim()
            var validationError = root.validateItemName(newName, itemKind)
            if (validationError.length > 0) {
                errorText = validationError
                renameNameField.forceActiveFocus()
                return
            }

            if (newName === originalName) {
                close()
                return
            }

            errorText = ""
            uploadManager.renameItem(originalPath, newName)
        }

        onOpened: {
            renameNameField.text = originalName
            errorText = ""
            renameNameField.forceActiveFocus()

            // 文件仅选中主名称，保留扩展名；无扩展名、点开头文件和文件夹则全选。
            var dotIndex = itemKind === "file" ? originalName.lastIndexOf(".") : -1
            if (dotIndex > 0)
                renameNameField.select(0, dotIndex)
            else
                renameNameField.selectAll()
        }

        Overlay.modal: Rectangle {
            color: "#66000000"
        }

        background: Rectangle {
            color: "#FFFFFF"
            radius: 13
            border.width: 1
            border.color: "#E4EAF4"
            antialiasing: true
        }

        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 11

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: renameDialog.itemKind === "folder" ? "重命名文件夹" : "重命名文件"
                        color: root.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }

                    Button {
                        id: renameDialogCloseButton
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        enabled: !uploadManager.renaming
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 6
                            color: renameDialogCloseButton.hovered ? "#F2F5FA" : "transparent"
                        }
                        contentItem: Text {
                            text: "×"
                            color: renameDialogCloseButton.enabled ? "#8D9AB0" : "#C8CFDA"
                            font.pixelSize: 19
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: renameDialog.close()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "为“" + renameDialog.originalName + "”输入新名称。"
                    color: root.textMidColor
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 8
                    color: renameNameField.activeFocus ? "#FAFBFF" : "#FFFFFF"
                    border.width: 1
                    border.color: renameDialog.errorText.length > 0 ? "#DF827C"
                                  : (renameNameField.activeFocus ? root.primaryColor : "#DDE5F2")

                    TextField {
                        id: renameNameField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        color: root.textDarkColor
                        font.pixelSize: 12
                        selectByMouse: true
                        selectedTextColor: "#FFFFFF"
                        selectionColor: root.primaryColor
                        verticalAlignment: TextInput.AlignVCenter
                        background: Item {}
                        onTextChanged: renameDialog.errorText = ""
                        onAccepted: renameDialog.submit()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    text: renameDialog.errorText.length > 0
                          ? renameDialog.errorText
                          : "名称需符合系统文件命名规则，最多 100 个字符。"
                    color: renameDialog.errorText.length > 0 ? "#D76D68" : "#9AA6B8"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    spacing: 9

                    Item { Layout.fillWidth: true }

                    Button {
                        id: cancelRenameButton
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.renaming
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: cancelRenameButton.hovered ? "#F4F6FA" : "#FFFFFF"
                            border.color: "#DFE6F1"
                        }
                        contentItem: Text {
                            text: "取消"
                            color: cancelRenameButton.enabled ? "#596981" : "#A7B2C2"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: renameDialog.close()
                    }

                    Button {
                        id: confirmRenameButton
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.renaming
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: !confirmRenameButton.enabled ? "#AAB8E8"
                                   : confirmRenameButton.down ? root.primaryDarkColor
                                   : confirmRenameButton.hovered ? "#5878F7" : root.primaryColor
                        }
                        contentItem: Item {
                            implicitWidth: renameContentRow.implicitWidth
                            implicitHeight: renameContentRow.implicitHeight

                            Row {
                                id: renameContentRow
                                anchors.centerIn: parent
                                spacing: 6

                                BusyIndicator {
                                    width: 16
                                    height: 16
                                    running: uploadManager.renaming
                                    visible: running
                                }

                                Text {
                                    text: uploadManager.renaming ? "保存中…" : "保存"
                                    color: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    height: 16
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                        onClicked: renameDialog.submit()
                    }
                }
            }
        }
    }

    // 移动弹窗：独立浏览云端目录，不改变主界面的 currentPath。
    Dialog {
        id: moveDialog
        anchors.centerIn: parent
        width: 540
        height: 540
        padding: 0
        modal: true
        focus: true
        closePolicy: uploadManager.moving ? Popup.NoAutoClose : Popup.CloseOnEscape

        property string sourcePath: ""
        property string sourceName: ""
        property string itemKind: "file"
        property string currentFolderPath: ""
        property var folderItems: []
        property string errorText: ""
        property bool directoryLoaded: false

        function isSourceOrDescendant(path) {
            if (itemKind !== "folder" || sourcePath.length === 0)
                return false
            var value = path === undefined || path === null ? "" : path.toString()
            return value === sourcePath || value.indexOf(sourcePath + "/") === 0
        }

        function openFor(path, name, kind) {
            sourcePath = path === undefined || path === null ? "" : path.toString()
            sourceName = name === undefined || name === null ? "" : name.toString()
            itemKind = kind === "folder" ? "folder" : "file"
            var separator = sourcePath.lastIndexOf("/")
            currentFolderPath = separator >= 0 ? sourcePath.substring(0, separator) : ""
            folderItems = []
            errorText = ""
            directoryLoaded = false
            open()
        }

        function navigate(path) {
            if (uploadManager.moving)
                return

            var targetPath = path === undefined || path === null ? "" : path.toString()
            if (isSourceOrDescendant(targetPath)) {
                errorText = "不能将文件夹移动到自身或其子文件夹中"
                return
            }

            currentFolderPath = targetPath
            folderItems = []
            errorText = ""
            directoryLoaded = false
            uploadManager.loadFolderChoices(targetPath)
        }

        function submit() {
            if (uploadManager.moving || uploadManager.loadingFolderChoices
                    || !directoryLoaded || sourcePath.length === 0)
                return
            if (isSourceOrDescendant(currentFolderPath)) {
                errorText = "不能将文件夹移动到自身或其子文件夹中"
                return
            }

            errorText = ""
            uploadManager.moveItem(sourcePath, currentFolderPath)
        }

        onOpened: uploadManager.loadFolderChoices(currentFolderPath)

        Overlay.modal: Rectangle {
            color: "#66000000"
        }

        background: Rectangle {
            color: "#FFFFFF"
            radius: 13
            border.width: 1
            border.color: "#E4EAF4"
            antialiasing: true
        }

        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 11

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: moveDialog.itemKind === "folder" ? "移动文件夹" : "移动文件"
                        color: root.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }

                    Button {
                        id: moveDialogCloseButton
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        enabled: !uploadManager.moving
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 6
                            color: moveDialogCloseButton.hovered ? "#F2F5FA" : "transparent"
                        }
                        contentItem: Text {
                            text: "×"
                            color: moveDialogCloseButton.enabled ? "#8D9AB0" : "#C8CFDA"
                            font.pixelSize: 19
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: moveDialog.close()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "将“" + moveDialog.sourceName + "”移动到以下位置。原名称保持不变。"
                    color: root.textMidColor
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 8
                    color: "#F5F7FF"
                    border.color: "#E1E7F7"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 9

                        Text {
                            text: "▰"
                            color: "#E9AD4E"
                            font.pixelSize: 17
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            width: parent.width - 30
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: "目标位置"
                                color: "#8D99AE"
                                font.pixelSize: 9
                            }
                            Text {
                                width: parent.width
                                text: moveDialog.currentFolderPath.length === 0
                                      ? "我的文件" : moveDialog.currentFolderPath
                                color: root.textDarkColor
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    color: "transparent"

                    ListView {
                        id: moveBreadcrumbView
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        model: root.makeBreadcrumbs(moveDialog.currentFolderPath)
                        spacing: 4
                        clip: true
                        interactive: contentWidth > width
                        boundsBehavior: Flickable.StopAtBounds
                        highlight: null

                        function revealLast() {
                            Qt.callLater(function() {
                                if (count > 0 && contentWidth > width)
                                    positionViewAtIndex(count - 1, ListView.End)
                                else
                                    contentX = 0
                            })
                        }
                        onModelChanged: revealLast()

                        delegate: Item {
                            width: moveBreadcrumbRow.implicitWidth
                            height: moveBreadcrumbView.height

                            Row {
                                id: moveBreadcrumbRow
                                height: parent.height
                                spacing: 4
                                Text {
                                    visible: index > 0
                                    text: "›"
                                    color: "#B5BFD0"
                                    font.pixelSize: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.name
                                    color: moveBreadcrumbMouse.containsMouse
                                           ? root.primaryColor : "#64738B"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea {
                                id: moveBreadcrumbMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !uploadManager.moving
                                cursorShape: Qt.PointingHandCursor
                                onClicked: moveDialog.navigate(modelData.path)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 180
                    radius: 9
                    color: "#FBFCFE"
                    border.color: "#E4EAF3"
                    clip: true

                    ListView {
                        id: moveFolderView
                        anchors.fill: parent
                        anchors.margins: 5
                        model: moveDialog.folderItems
                        spacing: 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: moveFolderRow
                            width: moveFolderView.width
                            height: 46
                            radius: 7
                            property bool forbidden: moveDialog.isSourceOrDescendant(modelData.path)
                            color: forbidden ? "#FAFBFC"
                                 : moveFolderMouse.containsMouse ? "#EEF2FF" : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: 7
                                    color: moveFolderRow.forbidden ? "#F1F2F4" : "#FFF4E2"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: "▰"
                                        color: moveFolderRow.forbidden ? "#B8BEC8" : "#E2A345"
                                        font.pixelSize: 15
                                    }
                                }
                                Text {
                                    width: parent.width - 78
                                    text: modelData.name
                                    color: moveFolderRow.forbidden ? "#B1B8C4" : "#40516B"
                                    font.pixelSize: 11
                                    font.weight: moveFolderMouse.containsMouse
                                                 ? Font.Medium : Font.Normal
                                    elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: moveFolderRow.forbidden ? "不可选" : "›"
                                    color: moveFolderRow.forbidden ? "#C1C6CF" : "#9AA6B8"
                                    font.pixelSize: moveFolderRow.forbidden ? 9 : 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: moveFolderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !moveFolderRow.forbidden && !uploadManager.moving
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                onClicked: moveDialog.navigate(modelData.path)
                            }
                        }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        running: uploadManager.loadingFolderChoices && moveDialog.opened
                        visible: running
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        visible: !uploadManager.loadingFolderChoices
                                 && moveFolderView.count === 0
                                 && moveDialog.errorText.length === 0
                        text: "此文件夹没有子文件夹\n可直接选择“移动到此处”"
                        color: "#9AA6B8"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.4
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    text: moveDialog.errorText.length > 0
                          ? moveDialog.errorText
                          : "单击文件夹进入下一层；目标位置已存在同名项目时不会覆盖。"
                    color: moveDialog.errorText.length > 0 ? "#D76D68" : "#9AA6B8"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    spacing: 9

                    Item { Layout.fillWidth: true }

                    Button {
                        id: cancelMoveButton
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.moving
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: cancelMoveButton.hovered ? "#F4F6FA" : "#FFFFFF"
                            border.color: "#DFE6F1"
                        }
                        contentItem: Text {
                            text: "取消"
                            color: cancelMoveButton.enabled ? "#596981" : "#A7B2C2"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: moveDialog.close()
                    }

                    Button {
                        id: confirmMoveButton
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 36
                        enabled: !uploadManager.moving
                                 && !uploadManager.loadingFolderChoices
                                 && moveDialog.directoryLoaded
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: !confirmMoveButton.enabled ? "#AAB8E8"
                                   : confirmMoveButton.down ? root.primaryDarkColor
                                   : confirmMoveButton.hovered ? "#5878F7" : root.primaryColor
                        }
                        contentItem: Item {
                            implicitWidth: moveContentRow.implicitWidth
                            implicitHeight: moveContentRow.implicitHeight
                            Row {
                                id: moveContentRow
                                anchors.centerIn: parent
                                spacing: 6
                                BusyIndicator {
                                    width: 16
                                    height: 16
                                    running: uploadManager.moving
                                    visible: running
                                }
                                Text {
                                    text: uploadManager.moving ? "移动中…" : "移动到此处"
                                    color: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    height: 16
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                        onClicked: moveDialog.submit()
                    }
                }
            }
        }
    }

    // 下载结果提示：成功时展示最终保存路径，失败时展示具体原因。
    DownloadResultDialog {
        id: downloadResultDialog
    }

    // 文件夹下载选择目标父目录，实际保存目录由 UploadManager 新建并自动避免重名。
    FolderDialog {
        id: downloadFolderDialog
        title: "选择文件夹保存位置"

        property string cloudPath: ""

        onAccepted: {
            var sourcePath = cloudPath
            cloudPath = ""
            uploadManager.downloadFolder(sourcePath, selectedFolder)
        }
        onRejected: cloudPath = ""
    }

    // 单文件下载保存对话框：只在用户确认目标路径后启动网络请求。
    FileDialog {
        id: downloadFileDialog
        title: "下载到本地"
        fileMode: FileDialog.SaveFile
        nameFilters: ["所有文件 (*)"]

        property string cloudPath: ""

        onAccepted: {
            var sourcePath = cloudPath
            cloudPath = ""
            uploadManager.downloadFile(sourcePath, selectedFile)
        }
        onRejected: cloudPath = ""
    }

    // 上传交互独立封装，页面只负责打开弹窗和维护文件列表。
    UploadDialog {
        id: uploadDialog
        anchors.centerIn: root
        manager: uploadManager
    }

    Connections {
        target: uploadManager

        function onCurrentPathChanged() {
            fileModel.clear()
            root.pendingCreatedFolderName = ""
            root.pendingCreatedFolderPath = ""
            root.pendingRenamedPath = ""
            root.refreshAfterCurrentFileLoad = false
            root.currentFilter = "全部"
            root.searchKeyword = ""
            searchField.text = ""
            root.clearSelection()
            rowMenu.close()
            renameDialog.close()
            moveDialog.close()
        }

        // 服务器文件列表加载成功
        function onFilesLoaded(items) {
            fileModel.clear()

            for (var i = 0; i < items.length; ++i) {
                fileModel.append(items[i])
            }

            // 新建完成后以服务器列表为准，并选中新文件夹，保持上传后的交互反馈一致。
            var foundCreatedFolder = false
            var shouldReloadAfterCurrentLoad = root.refreshAfterCurrentFileLoad
            if (root.pendingCreatedFolderName.length > 0) {
                for (var j = 0; j < fileModel.count; ++j) {
                    var item = fileModel.get(j)
                    var itemPath = item.path === undefined || item.path === null ? "" : item.path.toString()
                    var pathMatches = root.pendingCreatedFolderPath.length > 0
                                      ? itemPath === root.pendingCreatedFolderPath
                                      : item.name === root.pendingCreatedFolderName
                    if (item.kind === "folder" && pathMatches) {
                        root.selectFile(item.name, item.kind, item.modified, item.size,
                                        item.status, item.ext)
                        foundCreatedFolder = true
                        break
                    }
                }

                // 如果当前响应可能创建于新文件夹之前，则保留选中信息，等待补发的新请求。
                if (foundCreatedFolder || !shouldReloadAfterCurrentLoad) {
                    root.pendingCreatedFolderName = ""
                    root.pendingCreatedFolderPath = ""
                }
            }

            // 重命名后以服务端返回的新路径重新选中对应项目。
            if (root.pendingRenamedPath.length > 0) {
                for (var k = 0; k < fileModel.count; ++k) {
                    var renamedItem = fileModel.get(k)
                    var renamedItemPath = renamedItem.path === undefined || renamedItem.path === null
                                          ? "" : renamedItem.path.toString()
                    if (renamedItemPath === root.pendingRenamedPath) {
                        root.selectFile(renamedItem.name, renamedItem.kind, renamedItem.modified,
                                        renamedItem.size, renamedItem.status, renamedItem.ext)
                        break
                    }
                }
                root.pendingRenamedPath = ""
            }

            // 若创建前已有列表请求，新请求已取代旧请求；未找到新文件夹时再补查一次。
            if (shouldReloadAfterCurrentLoad) {
                root.refreshAfterCurrentFileLoad = false
                if (!foundCreatedFolder)
                    uploadManager.loadFiles()
            }
        }

        function onFolderCreated(folderName, folderPath, modifiedText) {
            root.pendingCreatedFolderName = folderName
            root.pendingCreatedFolderPath = folderPath
            root.refreshAfterCurrentFileLoad = uploadManager.loadingFiles
            createFolderDialog.errorText = ""
            createFolderDialog.close()
            // 在线时由服务器 filesChanged 事件驱动刷新；离线时保留原 HTTP 兜底。
            if (!uploadManager.webSocketConnected)
                uploadManager.loadFiles()
        }

        function onFolderCreationFailed(folderName, reason) {
            createFolderDialog.errorText = reason
            folderNameField.forceActiveFocus()
            folderNameField.selectAll()
        }

        function onItemRenamed(oldPath, newPath, newName) {
            root.pendingRenamedPath = newPath
            root.clearSelection()
            renameDialog.errorText = ""
            renameDialog.close()

            // 主动刷新可取消改名前尚未完成的旧列表请求；WebSocket 事件仍用于同步其他客户端。
            uploadManager.loadFiles()
        }

        function onItemRenameFailed(oldPath, reason) {
            renameDialog.errorText = reason
            renameNameField.forceActiveFocus()
            renameNameField.selectAll()
        }

        function onFolderChoicesLoaded(folderPath, folders) {
            if (!moveDialog.opened || folderPath !== moveDialog.currentFolderPath)
                return
            moveDialog.folderItems = folders
            moveDialog.errorText = ""
            moveDialog.directoryLoaded = true
        }

        function onFolderChoicesLoadFailed(folderPath, reason) {
            if (!moveDialog.opened || folderPath !== moveDialog.currentFolderPath)
                return
            moveDialog.folderItems = []
            moveDialog.directoryLoaded = false
            moveDialog.errorText = reason
        }

        function onItemMoved(oldPath, newPath, destinationPath) {
            moveDialog.errorText = ""
            moveDialog.close()
            root.clearSelection()

            // 移动后原目录和目标目录都可能变化；当前若仍在原目录，立即移除旧项目。
            // WebSocket 事件会继续同步其他客户端，主动刷新则保证离线时也能更新。
            uploadManager.loadFiles()
        }

        function onItemMoveFailed(oldPath, reason) {
            if (!moveDialog.opened)
                return
            moveDialog.errorText = reason
        }

        // 所有上传任务完成。在线时等待服务器事件，避免每个文件都重复刷新。
        function onUploadFinished(successCount, failedCount) {
            if (successCount > 0 && !uploadManager.webSocketConnected)
                uploadManager.loadFiles()
        }

        function onFileDownloaded(path, localPath) {
            root.showDownloadResult(true, false, localPath, "")
        }

        function onFolderDownloaded(path, localPath) {
            root.showDownloadResult(true, true, localPath, "")
        }

        function onFileDownloadFailed(path, reason) {
            root.showDownloadResult(false, false, "", reason)
        }

        function onFolderDownloadFailed(path, reason) {
            root.showDownloadResult(false, true, "", reason)
        }

        function onFilesLoadFailed(reason) {
            console.warn("加载文件列表失败：" + reason)
            if (root.refreshAfterCurrentFileLoad) {
                root.refreshAfterCurrentFileLoad = false
                uploadManager.loadFiles()
            }
        }
    }


    Component.onCompleted: {
        uploadManager.loadFiles()
    }
}
