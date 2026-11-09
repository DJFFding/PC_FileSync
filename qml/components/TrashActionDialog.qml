import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: trashActionDialog
    required property Item host
    anchors.centerIn: host
    width: 420
    height: 236
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string actionType: "delete"
    property string fileName: ""
    property string filePath: ""

    function openForDelete(name, path) {
        actionType = "delete"
        fileName = name
        filePath = path
        open()
    }

    function openForEmpty() {
        actionType = "empty"
        fileName = ""
        filePath = ""
        open()
    }

    function confirmAction() {
        var type = actionType
        var name = fileName
        var path = filePath
        close()
        if (type === "empty")
            host.trashEmptyRequested()
        else
            host.trashPermanentDeleteRequested(name, path)
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
                        text: "!"
                        color: "#D76561"
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        text: trashActionDialog.actionType === "empty" ? "清空回收站" : "彻底删除"
                        color: host.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "此操作无法撤销"
                        color: "#A2AEC0"
                        font.pixelSize: 10
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: trashActionDialog.actionType === "empty"
                      ? "回收站中的全部内容将被永久删除，且无法还原。确定继续吗？"
                      : "“" + trashActionDialog.fileName + "”将被永久删除，且无法还原。确定继续吗？"
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
                    id: cancelTrashActionButton
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 34
                    hoverEnabled: true
                    background: Rectangle {
                        radius: 8
                        color: cancelTrashActionButton.hovered ? "#F3F5F9" : "#FFFFFF"
                        border.color: "#DFE5EF"
                    }
                    contentItem: Text {
                        text: "取消"
                        color: "#68778E"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: trashActionDialog.close()
                }
                Button {
                    id: confirmTrashActionButton
                    Layout.preferredWidth: 94
                    Layout.preferredHeight: 34
                    hoverEnabled: true
                    enabled: !host.trashLoading
                    background: Rectangle {
                        radius: 8
                        color: confirmTrashActionButton.down ? "#BD514D"
                               : confirmTrashActionButton.hovered ? "#E47772" : "#D76561"
                    }
                    contentItem: Text {
                        text: trashActionDialog.actionType === "empty" ? "确认清空" : "彻底删除"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: trashActionDialog.confirmAction()
                }
            }
        }
    }
}

// 新建文件夹弹窗：名称校验、异步状态和错误提示均在当前操作上下文中完成。
