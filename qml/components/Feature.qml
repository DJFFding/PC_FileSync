import QtQuick

Column {
        property string icon: ""
        property string text: ""

        spacing: 7

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Rectangle {
                width: 20
                height: 20
                radius: 10
                color: "#DCE9FF"
                Text {
                    text: icon
                    color: window.primary
                    font.pixelSize: 12
                    font.bold: true
                    anchors.centerIn: parent
                }
            }
        }

        Text {
            text: parent.text
            color: "#6C7B93"
            font.pixelSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }