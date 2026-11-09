import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: moveDialog
    required property Item host
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
                    color: host.textDarkColor
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
                color: host.textMidColor
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
                            color: host.textDarkColor
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
                    model: host.makeBreadcrumbs(moveDialog.currentFolderPath)
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
                                       ? host.primaryColor : "#64738B"
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
                verticalAlignment: Text.AlignVCenter
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
                               : confirmMoveButton.down ? host.primaryDarkColor
                               : confirmMoveButton.hovered ? "#5878F7" : host.primaryColor
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


// 清空最近记录只影响快捷入口，确认文案明确保证不删除原文件。
