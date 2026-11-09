import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: renameDialog
    required property Item host

    function focusNameField() {
        renameNameField.forceActiveFocus()
        renameNameField.selectAll()
    }
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
        var validationError = host.validateItemName(newName, itemKind)
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
                    color: host.textDarkColor
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
                color: host.textMidColor
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
                              : (renameNameField.activeFocus ? host.primaryColor : "#DDE5F2")

                TextField {
                    id: renameNameField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    color: host.textDarkColor
                    font.pixelSize: 12
                    selectByMouse: true
                    selectedTextColor: "#FFFFFF"
                    selectionColor: host.primaryColor
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
                verticalAlignment: Text.AlignVCenter
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
                               : confirmRenameButton.down ? host.primaryDarkColor
                               : confirmRenameButton.hovered ? "#5878F7" : host.primaryColor
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
