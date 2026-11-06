import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FileSyncComponents 1.0

/*
 * FileSync - 文件工作台
 *
 * 用法：
 *   FileManagerPage { anchors.fill: parent }
 *
 * 文件列表使用本地 ListModel；上传已通过 C++ UploadManager 接入本地 HTTP 测试服务。
 * 下载、分享、删除、新建文件夹、刷新和立即同步仍通过 signals 暴露给业务层。
 */
Item {
    id: root
    objectName: "fileManagerPage"

    // 可由 C++ 设置为 QAbstractListModel；模型角色需包含 name/kind/ext/modified/size/status/iconBg/iconColor。
    property var fileModelSource: fileModel

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
    property string selectedName: "项目资料"
    property string selectedKind: "folder"
    property string selectedModified: "今天 14:28"
    property string selectedSize: "18 个文件"
    property string selectedStatus: "已同步"
    property string selectedExt: "文件夹"

    // 供 C++ 业务层连接的接口
    signal uploadRequested()
    signal createFolderRequested(string folderName)
    signal downloadRequested(string fileName)
    signal shareRequested(string fileName)
    signal deleteRequested(string fileName)
    signal openFileRequested(string fileName)
    signal refreshRequested()
    signal syncNowRequested()
    signal navigationChanged(string navigation)
    signal fileSelected(string fileName, string fileKind)

    // 两个上传按钮共用独立的上传面板。
    onUploadRequested: uploadDialog.open()

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
                            text: "2"
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

                            Row {
                                Layout.fillWidth: true
                                spacing: 7
                                Text {
                                    text: "我的文件"
                                    color: "#8794AA"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "›"
                                    color: "#C0C9D7"
                                    font.pixelSize: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "全部文件"
                                    color: root.textDarkColor
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
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
                                    { label: "文件总数", value: "128", note: "较上周 +12", icon: "▤", tint: "#EEF2FF", ink: "#4B6EF5" },
                                    { label: "已完成同步", value: "124", note: "云端状态正常", icon: "✓", tint: "#EAF8F2", ink: "#28B985" },
                                    { label: "正在同步", value: "2", note: "任务进行中", icon: "↻", tint: "#FFF5E8", ink: "#E8A044" }
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
                                        text: "8 个项目"
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
                                        property bool rowVisible: root.matchesFilter(kind) && root.matchesSearch(name)
                                        height: rowVisible ? 56 : 0
                                        visible: rowVisible

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
                                            onDoubleClicked: root.openFileRequested(name)
                                        }

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 16
                                            anchors.rightMargin: 13
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
                                                width: 33
                                                height: 32
                                                anchors.verticalCenter: parent.verticalCenter
                                                hoverEnabled: true
                                                background: Rectangle {
                                                    radius: 6
                                                    color: parent.hovered ? "#EEF2FA" : "transparent"
                                                }
                                                contentItem: Text {
                                                    text: "⋯"
                                                    color: "#9AA6B8"
                                                    font.pixelSize: 18
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                onClicked: {
                                                    root.selectFile(name, kind, modified, size, status, ext)
                                                    rowMenu.fileName = name
                                                    rowMenu.open()
                                                }
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
                                            color: root.successColor
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "所有文件均已安全保存至云端"
                                            color: "#9AA7B9"
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Item { width: 1; height: 1 }
                                        Text {
                                            text: "最后同步：刚刚"
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
                                { key: "所在位置", value: "我的文件" }
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
    // 文件右键/更多操作菜单
    // ============================================================
    Menu {
        id: rowMenu
        property string fileName: ""
        MenuItem {
            text: "下载"
            onTriggered: root.downloadRequested(rowMenu.fileName)
        }
        MenuItem {
            text: "分享"
            onTriggered: root.shareRequested(rowMenu.fileName)
        }
        MenuItem {
            text: "删除"
            onTriggered: root.deleteRequested(rowMenu.fileName)
        }
    }

    // 新建文件夹对话框
    Dialog {
        id: createFolderDialog
        title: "新建文件夹"
        modal: true
        width: 340
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        standardButtons: Dialog.Ok | Dialog.Cancel

        contentItem: Column {
            spacing: 9
            Text {
                text: "请输入文件夹名称"
                color: root.textMidColor
                font.pixelSize: 11
            }
            TextField {
                id: folderNameField
                width: 292
                height: 39
                placeholderText: "例如：产品设计资料"
                selectByMouse: true
                background: Rectangle {
                    radius: 7
                    color: "#FFFFFF"
                    border.color: folderNameField.activeFocus ? root.primaryColor : "#DCE4F0"
                }
            }
        }

        onAccepted: {
            var folderName = folderNameField.text.trim()
            if (folderName.length > 0)
                root.createFolderRequested(folderName)
            folderNameField.clear()
        }
        onRejected: folderNameField.clear()
    }

    // 示例文件数据：接入 C++ 后可替换为 QAbstractListModel
    ListModel {
        id: fileModel
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
    }


    // 上传交互独立封装，页面只负责打开弹窗和维护文件列表。
    UploadDialog {
        id: uploadDialog
        anchors.centerIn: root
        manager: uploadManager
    }

    Connections {
        target: uploadManager

        function onFileUploaded(fileName, displaySize, modifiedText) {
            var dot = fileName.lastIndexOf(".")
            var ext = dot >= 0 ? fileName.substring(dot + 1).toUpperCase() : "FILE"
            fileModel.insert(0, {
                name: fileName,
                kind: "file",
                ext: ext,
                modified: modifiedText,
                size: displaySize,
                status: "已同步",
                iconBg: "#EEF2FF",
                iconColor: "#4B6EF5"
            })
        }
    }

}
