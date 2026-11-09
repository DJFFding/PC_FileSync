import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: recentPage
    required property Item host
    required property var clearDialog
    readonly property int itemCount: recentListView.count
    anchors.fill: parent
    anchors.margins: 22
    spacing: 14
    visible: host.currentNav === "最近使用"

    // 标题、搜索与刷新
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        spacing: 12

        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "最近使用"
                color: host.textDarkColor
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                text: "按最后使用时间排序，快速继续刚才的工作"
                color: host.textLightColor
                font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.preferredWidth: 230
            Layout.minimumWidth: 150
            Layout.preferredHeight: 36
            radius: 8
            color: "#FFFFFF"
            border.color: recentSearchField.activeFocus
                          ? host.primaryColor : "#E7ECF4"
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
                    id: recentSearchField
                    width: parent.width - 34
                    height: parent.height
                    placeholderText: "搜索最近使用的文件"
                    color: host.textDarkColor
                    font.pixelSize: 11
                    selectByMouse: true
                    background: Item {}
                    onTextChanged: host.recentSearchKeyword = text.trim()
                }
            }
        }

        Button {
            id: recentRefreshButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            hoverEnabled: true
            enabled: !host.recentLoading
            background: Rectangle {
                radius: 8
                color: recentRefreshButton.hovered ? "#EEF2FF" : "#FFFFFF"
                border.color: "#E7ECF4"
            }
            contentItem: Text {
                text: "↻"
                color: recentRefreshButton.enabled ? "#8290A8" : "#B9C3D2"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: host.recentRefreshRequested()
            ToolTip.visible: hovered
            ToolTip.text: "刷新最近使用"
        }
    }

    // 功能说明与清空入口
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 82
        radius: 11
        color: "#F0F3FF"
        border.color: "#E3E9FC"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 13

            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 13
                color: "#E2E9FF"
                Text {
                    anchors.centerIn: parent
                    text: "◷"
                    color: host.primaryColor
                    font.pixelSize: 25
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    text: "继续你刚才的工作"
                    color: host.textDarkColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "预览、打开、下载和进入文件夹会自动记录，最多保留最近 200 条"
                    color: host.textMidColor
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 76
                Layout.preferredHeight: 28
                radius: 14
                color: "#FFFFFF"
                border.color: "#DFE7FA"
                Text {
                    anchors.centerIn: parent
                    text: host.recentModelSource.count + " 条记录"
                    color: host.primaryColor
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            Button {
                id: clearRecentButton
                Layout.preferredWidth: 92
                Layout.preferredHeight: 34
                hoverEnabled: true
                enabled: !host.recentLoading && host.recentModelSource.count > 0
                background: Rectangle {
                    radius: 8
                    color: !clearRecentButton.enabled ? "#F5F6FA"
                           : clearRecentButton.down ? "#E2E9FF"
                           : clearRecentButton.hovered ? "#F5F7FF" : "#FFFFFF"
                    border.color: clearRecentButton.enabled ? "#D9E2F8" : "#E3E7EF"
                }
                contentItem: Text {
                    text: "清空记录"
                    color: clearRecentButton.enabled ? "#6375B8" : "#ABB4C2"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: clearDialog.open()
                ToolTip.visible: hovered && enabled
                ToolTip.text: "只清空最近记录，不删除原文件"
            }
        }
    }

    // 最近使用列表
    Rectangle {
        id: recentListCard
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 11
        color: "#FFFFFF"
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.leftMargin: 16
                Layout.rightMargin: 14
                spacing: 10

                Text {
                    text: "使用记录"
                    color: host.textDarkColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: host.recentVisibleCount + " 个项目"
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
                            color: host.recentFilter === modelData ? "#EEF2FF"
                                   : (recentFilterMouse.containsMouse ? "#F7F9FD" : "transparent")
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: host.recentFilter === modelData
                                   ? host.primaryColor : "#8592A8"
                            font.pixelSize: 10
                            font.weight: host.recentFilter === modelData
                                         ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: recentFilterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.recentFilter = modelData
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#EEF1F6"
            }

            // 表头与数据行使用相同列宽。
            Item {
                Layout.fillWidth: true
                height: 37
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 13
                    Text {
                        width: Math.max(0, parent.width - 450)
                        text: "名称"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 130
                        text: "所在位置"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 115
                        text: "最近使用"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 65
                        text: "大小"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 140
                        text: "操作"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#F1F3F8"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: recentListView
                    anchors.fill: parent
                    clip: true
                    model: host.recentModelSource
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: Qt.callLater(host.updateRecentVisibleCount)

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: recentRow
                        width: recentListView.width

                        property string filePath: typeof path === "undefined" || path === null
                                                  ? "" : path.toString()
                        property string accessedAt: typeof lastAccessed === "undefined"
                                                    || lastAccessed === null
                                                    ? "" : lastAccessed.toString()
                        property string fallbackTime: typeof recentTime === "undefined"
                                                      || recentTime === null
                                                      ? "" : recentTime.toString()
                        property string displayTime: host.formatRecentTime(
                            accessedAt, fallbackTime, modified)
                        property string locationText: typeof location === "undefined"
                                                      || location === null
                                                      ? "我的文件" : location.toString()
                        property string actionType: typeof recentAction === "undefined"
                                                    || recentAction === null
                                                    ? "open" : recentAction.toString()
                        property int useCount: typeof accessCount === "undefined"
                                               || accessCount === null ? 0 : accessCount
                        property string serverPreviewType: typeof previewType === "undefined"
                                                           || previewType === null
                                                           ? "" : previewType.toString()
                        property string serverMimeType: typeof mimeType === "undefined"
                                                        || mimeType === null ? "" : mimeType.toString()
                        property bool rowVisible: host.matchesRecentFilter(kind)
                                                  && host.matchesRecentSearch(name)
                        height: rowVisible ? 68 : 0
                        visible: rowVisible

                        Rectangle {
                            anchors.fill: parent
                            color: host.selectedRecentPath === recentRow.filePath ? "#F4F7FF"
                                   : (recentRowMouse.containsMouse ? "#FAFBFE" : "#FFFFFF")
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: "#F3F5F9"
                        }

                        MouseArea {
                            id: recentRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.selectedRecentPath = recentRow.filePath
                            onDoubleClicked: host.openRecentItem(
                                recentRow.filePath, kind, name,
                                recentRow.serverPreviewType, ext,
                                recentRow.serverMimeType)
                        }

                        ItemNameToolTip {

                            pageHost: host
                            mouseArea: recentRowMouse
                            text: name + "\n" + recentRow.locationText
                            hoverAllowed: !openRecentButton.hovered
                                          && !locateRecentButton.hovered
                                          && !removeRecentButton.hovered
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 13

                            Row {
                                width: Math.max(0, parent.width - 450)
                                height: 68
                                spacing: 10
                                clip: true
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 9
                                    color: kind === "folder" ? "#FFF5E3" : iconBg
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 4
                                        text: kind === "folder" ? "▰" : ext
                                        color: kind === "folder" ? "#E9AD4E" : iconColor
                                        font.pixelSize: kind === "folder" ? 19 : 9
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                                Column {
                                    width: Math.max(0, parent.width - 48)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
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
                                        text: host.recentActionText(
                                            recentRow.actionType, kind, recentRow.useCount)
                                        color: "#AAB4C3"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Text {
                                width: 130
                                height: 68
                                text: recentRow.locationText
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: 115
                                height: 68
                                text: recentRow.displayTime
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            Text {
                                width: 65
                                height: 68
                                text: size
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            Row {
                                width: 140
                                height: 68
                                spacing: 6

                                Button {
                                    id: openRecentButton
                                    width: 46
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    hoverEnabled: true
                                    background: Rectangle {
                                        radius: 7
                                        color: openRecentButton.down ? "#E2E9FF"
                                               : openRecentButton.hovered ? "#EEF2FF" : "#F5F7FF"
                                        border.color: "#DFE6FA"
                                    }
                                    contentItem: Text {
                                        text: kind === "folder" ? "进入" : "预览"
                                        color: host.primaryColor
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: host.openRecentItem(
                                        recentRow.filePath, kind, name,
                                        recentRow.serverPreviewType, ext,
                                        recentRow.serverMimeType)
                                    ToolTip.visible: hovered
                                    ToolTip.text: kind === "folder" ? "进入此文件夹" : "预览此文件"
                                }

                                Button {
                                    id: locateRecentButton
                                    width: 46
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    hoverEnabled: true
                                    background: Rectangle {
                                        radius: 7
                                        color: locateRecentButton.hovered ? "#F0F3F8" : "transparent"
                                        border.color: locateRecentButton.hovered ? "#E1E7F0" : "transparent"
                                    }
                                    contentItem: Text {
                                        text: "定位"
                                        color: "#738199"
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: host.openRecentLocation(recentRow.filePath)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "在“我的文件”中打开所在目录"
                                }

                                Button {
                                    id: removeRecentButton
                                    width: 28
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: !uploadManager.updatingRecent
                                    hoverEnabled: true
                                    background: Rectangle {
                                        radius: 7
                                        color: removeRecentButton.hovered ? "#FFF3F2" : "transparent"
                                    }
                                    contentItem: Text {
                                        text: "×"
                                        color: removeRecentButton.enabled ? "#B08786" : "#C8CFDA"
                                        font.pixelSize: 17
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: host.removeRecentRecord(name, recentRow.filePath)
                                    ToolTip.visible: hovered && enabled
                                    ToolTip.text: "从最近使用移除，不删除原文件"
                                }
                            }
                        }
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    running: host.recentLoading && host.recentModelSource.count === 0
                    visible: running
                }

                // 首次加载失败时提供明确原因和重试入口。
                Column {
                    anchors.centerIn: parent
                    width: Math.min(360, parent.width - 40)
                    spacing: 9
                    visible: !host.recentLoading && host.recentError.length > 0
                             && host.recentModelSource.count === 0
                    Rectangle {
                        width: 64
                        height: 64
                        radius: 18
                        color: "#FFF3F2"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: "#D76D68"
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        width: parent.width
                        text: "最近使用加载失败"
                        color: host.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: host.recentError
                        color: host.textMidColor
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Button {
                        width: 96
                        height: 34
                        anchors.horizontalCenter: parent.horizontalCenter
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: parent.down ? host.primaryDarkColor
                                   : parent.hovered ? "#5878F7" : host.primaryColor
                        }
                        contentItem: Text {
                            text: "重新加载"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: host.recentRefreshRequested()
                    }
                }

                // 真正的空记录状态。
                Column {
                    anchors.centerIn: parent
                    width: Math.min(350, parent.width - 40)
                    spacing: 9
                    visible: !host.recentLoading && host.recentError.length === 0
                             && host.recentModelSource.count === 0
                    Rectangle {
                        width: 64
                        height: 64
                        radius: 18
                        color: "#EEF2FF"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "◷"
                            color: host.primaryColor
                            font.pixelSize: 32
                        }
                    }
                    Text {
                        width: parent.width
                        text: "还没有最近使用记录"
                        color: host.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "在“我的文件”中预览、打开、下载文件或进入文件夹后，相关内容会自动出现在这里。"
                        color: host.textMidColor
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Button {
                        width: 112
                        height: 34
                        anchors.horizontalCenter: parent.horizontalCenter
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: parent.down ? host.primaryDarkColor
                                   : parent.hovered ? "#5878F7" : host.primaryColor
                        }
                        contentItem: Text {
                            text: "浏览我的文件"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            host.currentNav = "我的文件"
                            host.clearSelection()
                            host.navigationChanged("我的文件")
                        }
                    }
                }

                // 搜索或筛选无结果时保留原始记录，并提供一键重置。
                Column {
                    anchors.centerIn: parent
                    width: Math.min(320, parent.width - 40)
                    spacing: 9
                    visible: !host.recentLoading && host.recentError.length === 0
                             && host.recentModelSource.count > 0
                             && host.recentVisibleCount === 0
                    Text {
                        width: parent.width
                        text: "⌕"
                        color: "#A5B2CA"
                        font.pixelSize: 34
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "没有匹配的使用记录"
                        color: host.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "尝试更换关键词，或查看全部文件类型。"
                        color: host.textMidColor
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Button {
                        width: 112
                        height: 34
                        anchors.horizontalCenter: parent.horizontalCenter
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#EEF2FF" : "#F5F7FF"
                            border.color: "#DFE6FA"
                        }
                        contentItem: Text {
                            text: "清除筛选"
                            color: host.primaryColor
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            host.recentFilter = "全部"
                            host.recentSearchKeyword = ""
                            recentSearchField.text = ""
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
                        color: host.recentError.length > 0
                               ? host.warningColor : host.primaryColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: host.recentLoading ? "正在更新最近使用记录…"
                              : host.recentError.length > 0 ? "显示上次成功加载的记录"
                              : "记录与原文件保持关联，移除记录不会删除文件"
                        color: "#9AA7B9"
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "双击打开 · 自动保存"
                        color: "#AAB4C3"
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: "#E9EEF6"
            border.width: 1
            antialiasing: true
            z: 100
        }
    }
}

