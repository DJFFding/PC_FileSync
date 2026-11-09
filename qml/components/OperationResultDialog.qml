import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: favoriteResultDialog
    required property Item host
    anchors.centerIn: parent
    width: 400
    height: 206
    padding: 0
    modal: true
    focus: true

    property bool succeeded: true
    property string message: ""
    property string operationName: "收藏"
    property string operationIcon: "★"

    function showResult(success, text, operation, icon) {
        succeeded = success
        message = text
        operationName = operation === undefined ? "收藏" : operation
        operationIcon = icon === undefined ? (success ? "★" : "!") : icon
        open()
    }

    Overlay.modal: Rectangle { color: "#66000000" }
    background: Rectangle {
        color: "#FFFFFF"
        radius: 13
        border.width: 1
        border.color: "#E4EAF4"
    }

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            Row {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 32
                    height: 32
                    radius: 9
                    color: favoriteResultDialog.succeeded ? "#FFF4DF" : "#FCE7E5"
                    Text {
                        anchors.centerIn: parent
                        text: favoriteResultDialog.succeeded
                              ? favoriteResultDialog.operationIcon : "!"
                        color: favoriteResultDialog.succeeded ? "#E8A044" : "#D76561"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: favoriteResultDialog.operationName
                          + (favoriteResultDialog.succeeded ? "操作完成" : "操作失败")
                    color: host.textDarkColor
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: favoriteResultDialog.message
                color: host.textMidColor
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }

            Button {
                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: 76
                Layout.preferredHeight: 34
                background: Rectangle {
                    radius: 8
                    color: parent.down ? host.primaryDarkColor
                           : parent.hovered ? "#5878F7" : host.primaryColor
                }
                contentItem: Text {
                    text: "确定"
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: favoriteResultDialog.close()
            }
        }
    }
}

// 下载结果提示：成功时展示最终保存路径，失败时展示具体原因。
