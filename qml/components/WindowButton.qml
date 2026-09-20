import QtQuick

Rectangle {
        id: root

        property url iconSource
        property bool danger: false

        width: 40
        height: 32

        color: mouseArea.containsMouse
               ? (danger ? "#E81123" : "#E8EAED")
               : "transparent"

        Image {
            anchors.centerIn: parent

            width: 14
            height: 14

            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        MouseArea {
            id: mouseArea

            anchors.fill: parent
            hoverEnabled: true

            onClicked: root.clicked()
        }

        signal clicked()
    }