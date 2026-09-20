import QtQuick

Column {
        property string source: ""
        property string text: ""

        spacing: 6

        Rectangle {
            width: 54
            height: 54
            radius: 12
            color: "#FAFBFD"
            border.color: "#EEF1F6"
            border.width: 1

            Image {
                width: 29
                height: 29
                source: parent.parent.source
                anchors.centerIn: parent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
            }
        }

        Text {
            text: parent.text
            color: "#7C889C"
            font.pixelSize: 11
            anchors.horizontalCenter: parent.horizontalCenter
        }
}