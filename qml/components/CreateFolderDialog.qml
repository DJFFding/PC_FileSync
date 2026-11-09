import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: createFolderDialog
    required property Item host

    function focusNameField() {
        folderNameField.forceActiveFocus()
        folderNameField.selectAll()
    }
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
        var validationError = host.validateFolderName(folderName)
        if (validationError.length > 0) {
            errorText = validationError
            folderNameField.forceActiveFocus()
            return
        }

        errorText = ""
        host.createFolderRequested(folderName)
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
                    color: host.textDarkColor
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
                text: "将在“" + host.currentLocationText + "”中创建一个空文件夹。"
                color: host.textMidColor
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
                              : (folderNameField.activeFocus ? host.primaryColor : "#DDE5F2")

                TextField {
                    id: folderNameField
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
                verticalAlignment: Text.AlignVCenter
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
                               : confirmCreateFolderButton.down ? host.primaryDarkColor
                               : confirmCreateFolderButton.hovered ? "#5878F7" : host.primaryColor
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
