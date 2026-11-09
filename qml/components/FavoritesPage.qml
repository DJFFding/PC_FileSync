import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: favoritesPage
    required property Item host
    anchors.fill: parent
    anchors.margins: 22
    spacing: 14
    visible: host.currentNav === "收藏夹"

    // 标题与收藏搜索
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        spacing: 12

        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "收藏夹"
                color: host.textDarkColor
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                text: "快速访问你标记的重要文件和文件夹"
                color: host.textLightColor
                font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.preferredWidth: 230
            Layout.minimumWidth: 150
            Layout.preferredHeight: 36
            radius: 8
            color: "#FFFFFF"
            border.color: favoriteSearchField.activeFocus
                          ? host.primaryColor : "#E7ECF4"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 9
                spacing: 7
                Text {
                    text: "⌕"
                    color: "#98A5B9"
                    font.pixelSize: 21
                    anchors.verticalCenter: parent.verticalCenter
                }
                TextField {
                    id: favoriteSearchField
                    width: parent.width - 34
                    height: parent.height
                    placeholderText: "搜索收藏内容"
                    color: host.textDarkColor
                    font.pixelSize: 11
                    selectByMouse: true
                    background: Item {}
                    onTextChanged: host.favoriteSearchKeyword = text.trim()
                }
            }
        }
    }

    // 收藏说明横幅
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 88
        radius: 11
        color: "#F0F3FF"
        border.color: "#E3E9FC"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 13

            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 13
                color: "#E2E9FF"
                Text {
                    anchors.centerIn: parent
                    text: "★"
                    color: host.primaryColor
                    font.pixelSize: 23
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    text: "重要内容，随时找到"
                    color: host.textDarkColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "收藏只创建快捷入口，不会复制或移动原文件"
                    color: host.textMidColor
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.preferredWidth: 86
                Layout.preferredHeight: 30
                radius: 15
                color: "#FFFFFF"
                border.color: "#DFE7FA"
                Text {
                    anchors.centerIn: parent
                    text: "☆  " + favoriteListView.count + " 项收藏"
                    color: host.primaryColor
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // 收藏内容列表
    Rectangle {
        id: favoriteListCard
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 11
        color: "#FFFFFF"
        border.color: "#E9EEF6"
        border.width: 0   // 取消底层边框
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.leftMargin: 16
                Layout.rightMargin: 14
                spacing: 10

                Text {
                    text: "收藏内容"
                    color: host.textDarkColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: favoriteListView.count + " 个项目"
                    color: "#A7B2C2"
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }

                Repeater {
                    model: ["全部", "文件", "文件夹"]
                    delegate: Item {
                        width: 43
                        height: 28
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: host.favoriteFilter === modelData ? "#EEF2FF"
                                   : (favoriteFilterMouse.containsMouse ? "#F7F9FD" : "transparent")
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: host.favoriteFilter === modelData
                                   ? host.primaryColor : "#8592A8"
                            font.pixelSize: 10
                            font.weight: host.favoriteFilter === modelData
                                         ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: favoriteFilterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.favoriteFilter = modelData
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#EEF1F6"
            }

            Item {
                Layout.fillWidth: true
                height: 37
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 13
                    Text {
                        width: Math.max(140, parent.width - 260)
                        text: "名称"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 125
                        text: "收藏时间"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text {
                        width: 80
                        text: "大小"
                        color: "#9AA6B8"
                        font.pixelSize: 10
                    }
                    Text { width: 55; text: "" }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#F1F3F8"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: favoriteListView
                    anchors.fill: parent
                    clip: true
                    model: host.favoritesModelSource
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        id: favoriteListScrollBar
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: favoriteRow
                        width: favoriteListView.width
                        property string filePath: typeof path === "undefined" || path === null
                                                  ? "" : path.toString()
                        property string collectedAt: typeof favoriteTime === "undefined"
                                                     || favoriteTime === null
                                                     ? modified : favoriteTime.toString()
                        property string favoriteLocation: typeof location === "undefined"
                                                          || location === null
                                                          ? "我的文件" : location.toString()
                        property string serverPreviewType: typeof previewType === "undefined"
                                                           || previewType === null
                                                           ? "" : previewType.toString()
                        property string serverMimeType: typeof mimeType === "undefined"
                                                        || mimeType === null ? "" : mimeType.toString()
                        property bool rowVisible: host.matchesFavoriteFilter(kind)
                                                  && host.matchesFavoriteSearch(name)
                        height: rowVisible ? 68 : 0
                        visible: rowVisible

                        Rectangle {
                            anchors.fill: parent
                            color: host.selectedName === name ? "#F4F7FF"
                                   : (favoriteRowMouse.containsMouse ? "#FAFBFE" : "#FFFFFF")
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: "#F3F5F9"
                        }

                        MouseArea {
                            id: favoriteRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.selectFile(name, kind, modified, size, status, ext,
                                                       favoriteRow.filePath)
                            onDoubleClicked: {
                                if (kind === "folder") {
                                    host.openFavoriteFolder(favoriteRow.filePath)
                                    return
                                }
                                host.previewRequested(name, favoriteRow.filePath,
                                                      favoriteRow.serverPreviewType,
                                                      ext, favoriteRow.serverMimeType)
                            }
                        }

                        ItemNameToolTip {

                            pageHost: host
                            mouseArea: favoriteRowMouse
                            text: name
                            hoverAllowed: !removeFavoriteButton.hovered
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 13

                            Row {
                                // 窄窗口下允许名称列继续收缩，不能反向撑宽整行。
                                width: Math.max(0, parent.width - 260)
                                height: 68
                                spacing: 10
                                clip: true
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 9
                                    color: kind === "folder" ? "#FFF5E3" : iconBg
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: kind === "folder" ? "▰" : ext
                                        color: kind === "folder" ? "#E9AD4E" : iconColor
                                        font.pixelSize: kind === "folder" ? 19 : 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Column {
                                    width: Math.max(0, parent.width - 48)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text {
                                        width: parent.width
                                        text: name
                                        color: host.textDarkColor
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: favoriteRow.favoriteLocation
                                        color: "#AAB4C3"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Text {
                                width: 125
                                height: 68
                                text: favoriteRow.collectedAt
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                width: 80
                                height: 68
                                text: size
                                color: "#8492A8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                            }
                            Button {
                                id: removeFavoriteButton
                                width: 36
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: !uploadManager.updatingFavorite
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 7
                                    color: removeFavoriteButton.hovered ? "#FFF4DF" : "transparent"
                                }
                                contentItem: Text {
                                    text: "★"
                                    color: removeFavoriteButton.hovered ? "#E8A044" : "#F0B756"
                                    font.pixelSize: 17
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: host.removeFavorite(index, name, favoriteRow.filePath)
                                ToolTip.visible: hovered && enabled
                                ToolTip.text: kind === "folder" ? "取消收藏该文件夹及其全部后代" : "取消收藏"
                            }
                        }
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    running: uploadManager.loadingFavorites
                    visible: running
                }

                // 无收藏时显示引导，并提供返回文件空间的入口。
                Column {
                    anchors.centerIn: parent
                    width: Math.min(330, parent.width - 40)
                    spacing: 9
                    visible: !uploadManager.loadingFavorites && favoriteListView.count === 0

                    Rectangle {
                        width: 64
                        height: 64
                        radius: 18
                        color: "#EEF2FF"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "☆"
                            color: host.primaryColor
                            font.pixelSize: 32
                        }
                    }
                    Text {
                        width: parent.width
                        text: "还没有收藏内容"
                        color: host.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        width: parent.width
                        text: "在文件的更多操作中选择“添加到收藏”，重要内容就会集中显示在这里。"
                        color: host.textMidColor
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Button {
                        width: 112
                        height: 34
                        anchors.horizontalCenter: parent.horizontalCenter
                        hoverEnabled: true
                        background: Rectangle {
                            radius: 8
                            color: parent.down ? host.primaryDarkColor
                                   : parent.hovered ? "#5878F7" : host.primaryColor
                        }
                        contentItem: Text {
                            text: "浏览我的文件"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            host.currentNav = "我的文件"
                            host.navigationChanged("我的文件")
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 34
                color: "#FCFDFF"
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: "#EEF1F6"
                }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 6
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: host.primaryColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "收藏内容与原文件保持关联"
                        color: "#9AA7B9"
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }
                    Text {
                        text: "双击可打开"
                        color: "#AAB4C3"
                        font.pixelSize: 9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
        // 最上层边框，防止 ListView 的 delegate 覆盖边框
         Rectangle {
             anchors.fill: parent
             radius: parent.radius
             color: "transparent"
             border.color: "#E9EEF6"
             border.width: 1
             antialiasing: true
             z: 100
         }
    }
}
