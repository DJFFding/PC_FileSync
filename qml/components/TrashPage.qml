import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ====================================================
ColumnLayout {
    id: trashPage
    required property Item host
    required property var actionDialog
    anchors.fill: parent
    anchors.margins: 22
    spacing: 14
    visible: host.currentNav === "回收站"

    // 标题、搜索与刷新
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        spacing: 12

        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "回收站"
                color: host.textDarkColor
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                text: "管理已删除的内容，还原文件或释放存储空间"
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
            border.color: trashSearchField.activeFocus
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
                    id: trashSearchField
                    width: parent.width - 34
                    height: parent.height
                    placeholderText: "搜索已删除的内容"
                    color: host.textDarkColor
                    font.pixelSize: 11
                    selectByMouse: true
                    background: Item {}
                    onTextChanged: host.trashSearchKeyword = text.trim()
                }
            }
        }

        Button {
            id: trashRefreshButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            hoverEnabled: true
            enabled: !host.trashLoading
            background: Rectangle {
                radius: 8
                color: trashRefreshButton.hovered ? "#EEF2FF" : "#FFFFFF"
                border.color: "#E7ECF4"
            }
            contentItem: Text {
                text: "↻"
                color: trashRefreshButton.enabled ? "#8290A8" : "#B9C3D2"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: host.trashRefreshRequested()
            ToolTip.visible: hovered
            ToolTip.text: "刷新回收站"
        }
    }
    // 保留规则与清空入口
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
                    text: "⌫"
                    color: host.primaryColor
                    font.pixelSize: 23
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    text: "已删除的内容将保留 " + host.trashRetentionDays + " 天"
                    color: host.textDarkColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "到期后自动彻底清除；还原后，文件和文件夹将返回原位置"
                    color: host.textMidColor
                    font.pixelSize: 10
                }
            }

            Button {
                id: emptyTrashButton
                Layout.preferredWidth: 104
                Layout.preferredHeight: 34
                hoverEnabled: true
                enabled: !host.trashLoading && trashListView.count > 0
                background: Rectangle {
                    radius: 8
                    color: !emptyTrashButton.enabled ? "#F5F6FA"
                           : emptyTrashButton.down ? "#FCE7E5"
                           : emptyTrashButton.hovered ? "#FFF3F2" : "#FFFFFF"
                    border.color: emptyTrashButton.enabled ? "#EFD6D4" : "#E3E7EF"
                }
                contentItem: Text {
                    text: "清空回收站"
                    color: emptyTrashButton.enabled ? "#D76D68" : "#ABB4C2"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: actionDialog.openForEmpty()
            }
        }
    }
    // 已删除内容列表
    Rectangle {
        id: trashListCard
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
                    text: "已删除内容"
                    color: host.textDarkColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: trashListView.count + " 个项目"
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
                            color: host.trashFilter === modelData ? "#EEF2FF"
                                   : (trashFilterMouse.containsMouse ? "#F7F9FD" : "transparent")
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: host.trashFilter === modelData
                                   ? host.primaryColor : "#8592A8"
                            font.pixelSize: 10
                            font.weight: host.trashFilter === modelData
                                         ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: trashFilterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.trashFilter = modelData
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#EEF1F6"
            }

            // 表头与数据行使用相同的固定列宽。
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
                        width: Math.max(0, parent.width - 455)
                        text: "名称"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 140
                        text: "原位置"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 120
                        text: "删除时间"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 70
                        text: "大小"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 125
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
                    id: trashListView
                    anchors.fill: parent
                    clip: true
                    model: host.trashModelSource
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: trashRow
                        width: trashListView.width

                        property string filePath: host.trashItemPath(
                            typeof path === "undefined" ? "" : path, name)
                        property string sourceLocation: {
                            if (typeof location !== "undefined" && location !== null
                                    && location.toString().length > 0)
                                return location.toString()
                            if (typeof originalPath !== "undefined" && originalPath !== null
                                    && originalPath.toString().length > 0)
                                return originalPath.toString()
                            return "我的文件"
                        }
                        property string deletedAt: typeof deletedTime !== "undefined"
                                                   && deletedTime !== null
                                                   ? deletedTime.toString()
                                                   : (typeof modified !== "undefined" && modified !== null
                                                      ? modified.toString() : "未知")
                        property bool rowVisible: host.matchesTrashFilter(kind)
                                                  && host.matchesTrashSearch(name)
                        height: rowVisible ? 68 : 0
                        visible: rowVisible

                        Rectangle {
                            anchors.fill: parent
                            color: host.selectedTrashPath === trashRow.filePath ? "#F4F7FF"
                                   : (trashRowMouse.containsMouse ? "#FAFBFE" : "#FFFFFF")
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: "#F3F5F9"
                        }

                        MouseArea {
                            id: trashRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.selectedTrashPath = trashRow.filePath
                        }

                        ItemNameToolTip {

                            pageHost: host
                            mouseArea: trashRowMouse
                            text: name
                            hoverAllowed: !restoreTrashButton.hovered
                                          && !permanentDeleteButton.hovered
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 13

                            Row {
                                width: Math.max(0, parent.width - 455)
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
                                        text: kind === "folder" ? "▰" : ext
                                        color: kind === "folder" ? "#E9AD4E" : iconColor
                                        font.pixelSize: kind === "folder" ? 19 : 9
                                        font.weight: Font.DemiBold
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
                                        text: kind === "folder" ? "文件夹" : host.fileTypeDescription(ext)
                                        color: "#AAB4C3"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Text {
                                width: 140
                                height: 68
                                text: trashRow.sourceLocation
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: 120
                                height: 68
                                text: trashRow.deletedAt
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            Text {
                                width: 70
                                height: 68
                                text: size
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            Row {
                                width: 125
                                height: 68
                                spacing: 6

                                Button {
                                    id: restoreTrashButton
                                    width: 58
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    hoverEnabled: true
                                    enabled: !host.trashLoading
                                    background: Rectangle {
                                        radius: 7
                                        color: restoreTrashButton.down ? "#E2E9FF"
                                               : restoreTrashButton.hovered ? "#EEF2FF" : "#F5F7FF"
                                        border.color: "#DFE6FA"
                                    }
                                    contentItem: Text {
                                        text: "还原"
                                        color: restoreTrashButton.enabled ? host.primaryColor : "#AAB4C3"
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        host.selectedTrashPath = trashRow.filePath
                                        host.trashRestoreRequested(name, trashRow.filePath)
                                    }
                                    ToolTip.visible: hovered && enabled
                                    ToolTip.text: "还原到原位置"
                                }

                                Button {
                                    id: permanentDeleteButton
                                    width: 58
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    hoverEnabled: true
                                    enabled: !host.trashLoading
                                    background: Rectangle {
                                        radius: 7
                                        color: permanentDeleteButton.down ? "#FCE7E5"
                                               : permanentDeleteButton.hovered ? "#FFF3F2" : "transparent"
                                        border.color: permanentDeleteButton.hovered ? "#F0D8D5" : "transparent"
                                    }
                                    contentItem: Text {
                                        text: "删除"
                                        color: permanentDeleteButton.enabled ? "#D76D68" : "#B8C0CC"
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        host.selectedTrashPath = trashRow.filePath
                                        actionDialog.openForDelete(name, trashRow.filePath)
                                    }
                                    ToolTip.visible: hovered && enabled
                                    ToolTip.text: "彻底删除，无法还原"
                                }
                            }
                        }
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    running: host.trashLoading
                    visible: running
                }

                // 回收站为空时提供明确的返回入口。
                Column {
                    anchors.centerIn: parent
                    width: Math.min(340, parent.width - 40)
                    spacing: 9
                    visible: !host.trashLoading && trashListView.count === 0

                    Rectangle {
                        width: 64
                        height: 64
                        radius: 18
                        color: "#EEF2FF"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "⌫"
                            color: host.primaryColor
                            font.pixelSize: 30
                        }
                    }
                    Text {
                        width: parent.width
                        text: "回收站是空的"
                        color: host.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "删除的文件和文件夹会暂时保存在这里，你可以随时还原。"
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
                        color: host.warningColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "回收站中的内容不会参与文件同步"
                        color: "#9AA7B9"
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "彻底删除后无法恢复"
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
