import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: deleteConfirmDialog
    required property Item host
    anchors.centerIn: host
    width: 430
    height: 250
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string fileName: ""
    property string filePath: ""
    property string fileKind: "file"

    function openFor(path, name, kind) {
        filePath = path
        fileName = name
        fileKind = kind
        open()
    }

    function confirmDelete() {
        if (uploadManager.deleting || filePath.length === 0)
            return
        var path = filePath
        close()
        uploadManager.deleteItem(path)
    }

    Overlay.modal: Rectangle { color: "#66000000" }
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
            spacing: 14

            Row {
                Layout.fillWidth: true
                spacing: 11
                Rectangle {
                    width: 38
                    height: 38
                    radius: 11
                    color: "#FFF1F0"
                    Text {
                        anchors.centerIn: parent
                        text: "⌫"
                        color: "#D76561"
                        font.pixelSize: 18
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        text: deleteConfirmDialog.fileKind === "folder" ? "删除文件夹" : "删除文件"
                        color: host.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "可在回收站中查看已删除内容"
                        color: "#A2AEC0"
                        font.pixelSize: 10
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: deleteConfirmDialog.fileKind === "folder"
                      ? "确定将文件夹“" + deleteConfirmDialog.fileName
                        + "”移入回收站吗？文件夹内的全部文件、子文件夹和空目录都会一起移动。"
                      : "确定将文件“" + deleteConfirmDialog.fileName + "”移入回收站吗？"
                color: host.textMidColor
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 35
                spacing: 9
                Item { Layout.fillWidth: true }
                Button {
                    id: cancelDeleteButton
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 34
                    hoverEnabled: true
                    background: Rectangle {
                        radius: 8
                        color: cancelDeleteButton.hovered ? "#F3F5F9" : "#FFFFFF"
                        border.color: "#DFE5EF"
                    }
                    contentItem: Text {
                        text: "取消"
                        color: "#68778E"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: deleteConfirmDialog.close()
                }
                Button {
                    id: confirmDeleteButton
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 34
                    hoverEnabled: true
                    enabled: !uploadManager.deleting
                    background: Rectangle {
                        radius: 8
                        color: !confirmDeleteButton.enabled ? "#E6B1AE"
                               : confirmDeleteButton.down ? "#BD514D"
                               : confirmDeleteButton.hovered ? "#E47772" : "#D76561"
                    }
                    contentItem: Text {
                        text: uploadManager.deleting ? "正在删除…" : "移入回收站"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: deleteConfirmDialog.confirmDelete()
                }
            }
        }
    }
}

// 彻底删除与清空回收站共用确认弹窗，确认后仅发送请求，不在本地伪造成功结果。
