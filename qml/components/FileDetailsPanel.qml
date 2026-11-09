import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailsPanel
    required property Item host
    property real availableWidth: 0
    width: 270
    height: parent.height
    visible: host.currentNav !== "收藏夹" && host.currentNav !== "最近使用"
             && host.currentNav !== "回收站"
             && host.detailsVisible && availableWidth >= 850
    color: "#FFFFFF"
    border.color: "#E9EEF6"
    border.width: 1
    bottomRightRadius: host.maximized ? 0 : host.cornerRadius
    antialiasing: true

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 0

        Row {
            width: parent.width
            height: 35
            Text {
                text: "文件详情"
                color: host.textDarkColor
                font.pixelSize: 14
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: 1; height: 1 }
            Button {
                width: 27
                height: 27
                hoverEnabled: true
                background: Rectangle {
                    radius: 6
                    color: parent.hovered ? "#F2F5FA" : "transparent"
                }
                contentItem: Text {
                    text: "×"
                    color: "#9AA6B8"
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: host.detailsVisible = false
            }
        }

        Item { width: 1; height: 19 }

        Rectangle {
            width: 64
            height: 64
            radius: 15
            color: host.selectedKind === "folder" ? "#FFF5E3" : "#EEF2FF"
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                anchors.centerIn: parent
                text: host.selectedKind === "folder" ? "▰" : host.selectedExt
                color: host.selectedKind === "folder" ? "#E9AD4E" : host.primaryColor
                font.pixelSize: host.selectedKind === "folder" ? 30 : 15
                font.weight: Font.DemiBold
            }
        }

        Item { width: 1; height: 12 }
        Text {
            width: parent.width
            text: host.selectedName
            color: host.textDarkColor
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
        }
        Text {
            width: parent.width
            text: host.selectedExt
            color: "#A2AEC0"
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            topPadding: 5
        }

        Item { width: 1; height: 19 }
        Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
        Item { width: 1; height: 16 }

        Text {
            text: "基本信息"
            color: "#8D9AB0"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
        Item { width: 1; height: 10 }

        Repeater {
            model: [
                { key: "文件大小", value: host.selectedSize },
                { key: "修改时间", value: host.selectedModified },
                { key: "所在位置", value: host.currentLocationText }
            ]
            delegate: Row {
                width: parent.width
                height: 31
                Text {
                    id: infoKey
                    text: modelData.key
                    color: "#9AA6B8"
                    font.pixelSize: 10
                }
                Item {
                    width: Math.max(0, parent.width - infoKey.implicitWidth - infoValue.implicitWidth)
                    height: 1
                }
                Text {
                    id: infoValue
                    text: modelData.value
                    color: "#596981"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Row {
            width: parent.width
            height: 32
            Text {
                text: "同步状态"
                color: "#9AA6B8"
                font.pixelSize: 10
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: 1; height: 1 }
            Row {
                spacing: 5
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: host.selectedStatus === "已同步" ? host.successColor : host.warningColor
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: host.selectedStatus
                    color: host.selectedStatus === "已同步" ? "#42A985" : "#D79A43"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item { width: 1; height: 16 }
        Rectangle { width: parent.width; height: 1; color: "#EEF1F6" }
        Item { width: 1; height: 16 }
        Text {
            text: "快捷操作"
            color: "#8D9AB0"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
        Item { width: 1; height: 10 }

        Button {
            width: parent.width
            height: 37
            hoverEnabled: true
            background: Rectangle {
                radius: 8
                color: parent.hovered ? "#F2F5FF" : "#FFFFFF"
                border.color: "#E2E9F6"
            }
            contentItem: Row {
                anchors.centerIn: parent
                spacing: 8
                Text { anchors.verticalCenter:parent.verticalCenter;text: "↓"; color: host.primaryColor; font.pixelSize: 16 }
                Text { anchors.verticalCenter:parent.verticalCenter;text: "下载到本地"; color: "#53637D"; font.pixelSize: 11 }
            }
            onClicked: host.downloadRequested(host.selectedName)
        }
        Item { width: 1; height: 8 }
        Button {
            width: parent.width
            height: 37
            hoverEnabled: true
            background: Rectangle {
                radius: 8
                color: parent.hovered ? "#F2F5FF" : "#FFFFFF"
                border.color: "#E2E9F6"
            }
            contentItem: Row {
                anchors.centerIn: parent
                spacing: 8
                Text { anchors.verticalCenter:parent.verticalCenter;text: "↗"; color: host.primaryColor; font.pixelSize: 15 }
                Text { anchors.verticalCenter:parent.verticalCenter;text: "分享"; color: "#53637D"; font.pixelSize: 11 }
            }
            onClicked: host.shareRequested(host.selectedName)
        }
        Item { width: 1; height: 8 }
        Button {
            width: parent.width
            height: 37
            hoverEnabled: true
            background: Rectangle {
                radius: 8
                color: parent.hovered ? "#FFF3F2" : "#FFFFFF"
                border.color: "#F1E5E4"
            }
            contentItem: Row {
                anchors.centerIn: parent
                spacing: 8
                Text { anchors.verticalCenter:parent.verticalCenter;text: "⌫"; color: "#E47772"; font.pixelSize: 14 }
                Text { anchors.verticalCenter:parent.verticalCenter;text: "删除"; color: "#D76D68"; font.pixelSize: 11 }
            }
            onClicked: host.deleteRequested(host.selectedName)
        }

        Item { width: 1; height: 8; }

        Rectangle {
            width: parent.width
            height: 76
            radius: 9
            color: "#F8FAFF"
            border.color: "#EBF0FA"
            Column {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 5
                Text {
                    text: "安全同步"
                    color: host.textDarkColor
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: "文件在本地与云端之间加密传输，确保数据随时保持一致。"
                    color: "#929FB3"
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                }
            }
        }
    }
}
