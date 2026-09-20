import QtQuick
import QtQuick.Controls

Item {
        property string icon: ""
        property string placeholder: ""
        property bool password: false
        property bool password_can_see: false

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "#FFFFFF"
            border.width: 1
            border.color: field.activeFocus ? window.primary : "#E5EAF2"

            Behavior on border.color { ColorAnimation { duration: 120 } }

            Image {
                width: 21
                height: 21
                source: "qrc:/qt/qml/FileSync/assets/icon-" + icon + ".svg"
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
            }

            TextField {
                id: field
                anchors.left: parent.left
                anchors.leftMargin: 52
                anchors.right: parent.right
                anchors.rightMargin: 42
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                placeholderText: placeholder
                echoMode: password ? TextInput.Password : TextInput.Normal
                color: "#35425A"
                placeholderTextColor: "#B0B9C8"
                font.pixelSize: 14
                selectByMouse: true

                background: Item {}
            }

            Image {
                visible: password
                source: password_can_see? "qrc:/qt/qml/FileSyncComponents/assets/eye.svg":"qrc:/qt/qml/FileSyncComponents/assets/eye-off.svg"
                height: 18
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
            }
        }
    }