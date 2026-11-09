import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: myFilesPage
    required property Item host
    required property var contextMenu
    required property var folderDialog

    function clearSearch() {
        searchField.text = ""
    }
    anchors.fill: parent
    anchors.margins: 22
    spacing: 13
    visible: host.currentNav !== "收藏夹" && host.currentNav !== "最近使用"
             && host.currentNav !== "回收站"

    // 顶部标题、搜索和快捷操作
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        spacing: 12

        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: host.currentNav
                color: host.textDarkColor
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                text: "管理和同步你的所有文件"
                color: host.textLightColor
                font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.preferredWidth: 225
            Layout.minimumWidth: 150
            Layout.preferredHeight: 36
            radius: 8
            color: "#FFFFFF"
            border.color: searchField.activeFocus ? host.primaryColor : "#E7ECF4"
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
                    color: host.textDarkColor
                    font.pixelSize: 11
                    selectByMouse: true
                    background: Item {}
                    onTextChanged: host.searchKeyword = text.trim()
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
            onClicked: host.refreshRequested()
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
            model: host.breadcrumbItems
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
                        color: breadcrumbDelegate.isCurrent ? host.textDarkColor
                               : (breadcrumbMouse.containsMouse ? host.primaryColor : "#8794AA")
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
                    onClicked: host.openFolder(modelData.path)
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
                    color: host.primaryColor
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
            onClicked: folderDialog.open()
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
                       : uploadButton.down ? host.primaryDarkColor
                       : uploadButton.hovered ? "#5878F7" : host.primaryColor
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
            onClicked: host.uploadRequested()
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
                            color: host.textMidColor
                            font.pixelSize: 10
                        }
                        Row {
                            spacing: 7
                            Text {
                                text: modelData.value
                                color: host.textDarkColor
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
                    color: host.textDarkColor
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
                            color: host.currentFilter === modelData ? "#EEF2FF" : (filterMouse.containsMouse ? "#F7F9FD" : "transparent")
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: host.currentFilter === modelData ? host.primaryColor : "#8592A8"
                            font.pixelSize: 10
                            font.weight: host.currentFilter === modelData ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: filterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.currentFilter = modelData
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
                    onClicked: host.refreshRequested()
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
                model: host.fileModelSource
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
                                           || (serverPreviewType.length === 0 && host.isImageExtension(ext)))
                    property bool isText: hasPreview && !isImage && (serverPreviewType === "text"
                                          || (serverPreviewType.length === 0 && host.isTextExtension(ext)))
                    property string contentSource: (isImage || isText) && filePath.length > 0
                                                   ? uploadManager.fileContentUrl(filePath) : ""
                    property string imageSource: isImage ? contentSource : ""
                    property string textSource: {
                        if (!isText || contentSource.length === 0)
                            return ""
                        if (contentSource.indexOf("http://") !== 0 && contentSource.indexOf("https://") !== 0)
                            return contentSource
                        return contentSource + (contentSource.indexOf("?") >= 0 ? "&" : "?")
                               + "maxBytes=" + host.textPreviewByteLimit
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
                                        Math.max(1, host.maxImagePreviewHeight) / previewImage.implicitHeight)
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
                    property bool rowVisible: host.matchesFilter(kind) && host.matchesSearch(name)

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
                        color: host.selectedName === name ? "#F4F7FF" : (rowMouse.containsMouse ? "#FAFBFE" : "#FFFFFF")
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
                        onClicked: host.selectFile(name, kind, modified, size, status, ext,
                                                   fileRow.filePath)
                        onDoubleClicked: {
                            if (kind === "folder") {
                                host.openFolder(fileRow.filePath)
                                return
                            }

                            // 文件预览由 Main.qml 的全屏对话框统一处理；
                            // 不支持的二进制类型会在 openPreview() 中直接忽略。
                            host.previewRequested(name, fileRow.filePath,
                                                  fileRow.serverPreviewType,
                                                  ext, fileRow.serverMimeType)
                        }
                    }

                    ItemNameToolTip {

                        pageHost: host
                        mouseArea: rowMouse
                        text: name
                        hoverAllowed: !rowMenuButton.hovered && !copyTextButton.hovered
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
                                    color: host.textDarkColor
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
                                color: status === "已同步" ? host.successColor : (status === "同步中" ? host.warningColor : "#A7B2C2")
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
                                color: rowMenuButton.down || contextMenu.opened ? "#E4EBFF"
                                       : rowMenuButton.hovered ? "#EEF2FA" : "transparent"
                            }
                            contentItem: Text {
                                text: "⋯"
                                color: contextMenu.opened ? host.primaryColor : "#9AA6B8"
                                font.pixelSize: 18
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                host.selectFile(name, kind, modified, size, status, ext,
                                                fileRow.filePath)
                                contextMenu.fileName = name
                                contextMenu.fileKind = kind
                                contextMenu.filePath = host.cloudItemPath(fileRow.filePath, name)
                                contextMenu.popup(rowMenuButton,
                                              rowMenuButton.width - contextMenu.width,
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
                            color: host.selectedName === name ? "#EDF2FC" : "#F5F7FB"
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
                            color: host.selectedName === name ? "#F0F4FD" : "#F8FAFD"
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
                                      ? "文本预览（前 " + Math.round(host.textPreviewByteLimit / 1024) + " KB）"
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
                                    color: copyTextButton.enabled ? host.primaryColor : "#A7B2C2"
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
                                    selectionColor: host.primaryColor
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
                            color: host.selectedName === name ? "#F0F4FD" : "#F8FAFD"
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
                                    text: host.fileTypeDescription(ext)
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
                               ? host.successColor : host.warningColor
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
