import QtQuick

Item {
        property string label: ""
        property string icon: ""
        property bool selected: false
        height: 48

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 42
            radius: 8
            color: selected ? "#243452" : (navMouse.containsMouse ? "#1A2940" : "transparent")
        }

        Image {
            width: 20
            height: 20
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/qt/qml/FileSync/assets/icon-" + icon + ".svg"
        }

        Text {
            text: label
            color: selected ? "#FFFFFF" : "#AEBBD0"
            font.pixelSize: 14
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
        }
    }