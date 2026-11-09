import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: sidebar
    required property Item host
    width: 218
    height: parent.height
    color: "#FFFFFF"
    border.color: "#EDF1F7"
    border.width: 1

    Column {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        // Logo 与产品名称
        Item {
            width: parent.width
            height: 76

            Rectangle {
                x: 3
                y: 19
                width: 38
                height: 38
                radius: 11
                color: host.primaryColor

                Text {
                    anchors.centerIn: parent
                    text: "↔"
                    color: "white"
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                }
            }

            Text {
                x: 51
                y: 19
                text: "FileSync"
                color: host.textDarkColor
                font.pixelSize: 19
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                x: 52
                y: 43
                text: "云端文件空间"
                color: host.textLightColor
                font.pixelSize: 10
            }
        }

        // 上传入口
        Button {
            id: sidebarUploadButton
            width: parent.width
            height: 42
            hoverEnabled: true
            enabled: !uploadManager.uploading
            background: Rectangle {
                radius: 8
                color: !sidebarUploadButton.enabled ? "#AAB8E8"
                       : sidebarUploadButton.down ? host.primaryDarkColor
                       : sidebarUploadButton.hovered ? "#5878F7" : host.primaryColor
            }
            contentItem: Row {
                spacing: 8
                anchors.centerIn: parent
                Text {
                    text: "+"
                    color: "white"
                    font.pixelSize: 21
                    font.weight: Font.Light
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "上传文件"
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            onClicked: host.uploadRequested()
        }

        Item { width: 1; height: 22 }

        Text {
            text: "文件空间"
            color: "#A3AEC1"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            leftPadding: 10
            height: 22
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: [
                { title: "我的文件", icon: "▣" },
                { title: "最近使用", icon: "◷" },
                { title: "收藏夹", icon: "☆" },
                { title: "共享给我", icon: "♧" },
                { title: "回收站", icon: "⌫" }
            ]

            delegate: Item {
                width: sidebar.width - 32
                height: 43
                property bool active: host.currentNav === modelData.title

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: parent.active ? "#EEF2FF" : (navMouse.containsMouse ? "#F7F9FE" : "transparent")
                }
                Rectangle {
                    width: 3
                    height: 20
                    radius: 2
                    color: host.primaryColor
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.active
                }
                Text {
                    x: 15
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.icon
                    color: parent.active ? host.primaryColor : "#8794AA"
                    font.pixelSize: 17
                    width: 23
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    x: 49
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    color: parent.active ? host.primaryColor : "#596981"
                    font.pixelSize: 13
                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        host.currentNav = modelData.title
                        host.clearSelection()
                        host.navigationChanged(modelData.title)
                    }
                }
            }
        }

        Item { width: 1; height: 18 }
        Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
        Item { width: 1; height: 15 }

        Text {
            text: "同步管理"
            color: "#A3AEC1"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            leftPadding: 10
            height: 22
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            width: parent.width
            height: 43
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: syncNavMouse.containsMouse ? "#F7F9FE" : "transparent"
            }
            Text {
                x: 15
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                color: "#8794AA"
                font.pixelSize: 18
                width: 23
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                x: 49
                anchors.verticalCenter: parent.verticalCenter
                text: "同步任务"
                color: "#596981"
                font.pixelSize: 13
            }
            Rectangle {
                width: 22
                height: 19
                radius: 9
                color: "#EEF2FF"
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    text: uploadManager.syncingFileCount
                    color: host.primaryColor
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: syncNavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: host.syncNowRequested()
            }
        }

        Item { Layout.fillHeight: true; width: 1; height: 1 }

        // 存储空间卡片
        Rectangle {
            width: parent.width
            height: 128
            radius: 10
            color: "#F8FAFF"
            border.color: "#EAF0FC"

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 7
                    Text { text: "☁"; color: host.primaryColor; font.pixelSize: 17 }
                    Text {
                        text: "云端存储"
                        color: host.textDarkColor
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "68%"
                        color: host.primaryColor
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    text: "6.8 GB  /  10 GB"
                    color: host.textMidColor
                    font.pixelSize: 11
                }
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: "#E7ECF6"
                    Rectangle {
                        width: parent.width * 0.68
                        height: parent.height
                        radius: 3
                        color: host.primaryColor
                    }
                }
                Text {
                    text: "空间使用情况良好"
                    color: "#98A5B9"
                    font.pixelSize: 10
                }
            }
        }

        Item { width: 1; height: 12 }

        // 用户信息
        Row {
            width: parent.width
            height: 52
            spacing: 9
            Rectangle {
                width: 33
                height: 33
                radius: 17
                color: "#EAF0FF"
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    text: "U"
                    color: host.primaryColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: "我的账号"
                    color: host.textDarkColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "个人免费版"
                    color: host.textLightColor
                    font.pixelSize: 10
                }
            }
            Item { width: 1; height: 1 }
            Text {
                text: "⋯"
                color: "#9AA6B8"
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
