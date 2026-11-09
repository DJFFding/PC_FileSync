import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Menu {
    id: rowMenu
    required property Item host
    required property var renameController
    required property var moveController

    property string fileName: ""
    property string fileKind: ""
    property string filePath: ""

    width: 220
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    transformOrigin: Item.TopRight

    background: Rectangle {
        color: "#FFFFFF"
        radius: 12
        border.width: 1
        border.color: "#E4EAF4"
        antialiasing: true
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.96
            to: 1.0
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            properties: "opacity"
            from: 1.0
            to: 0.0
            duration: 90
        }
    }

    // 菜单标题：显示当前行文件名，不响应点击。
    MenuItem {
        id: menuHeader
        enabled: false
        hoverEnabled: false
        implicitHeight: 51
        leftPadding: 10
        rightPadding: 10
        topPadding: 7
        bottomPadding: 7
        indicator: null
        background: Item {}

        contentItem: Column {
            spacing: 3

            Text {
                text: "文件操作"
                color: "#8B98AD"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: rowMenu.fileName.length > 0 ? rowMenu.fileName : "当前文件"
                color: host.textDarkColor
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideMiddle
            }
        }
    }

    MenuSeparator {
        topPadding: 2
        bottomPadding: 5
        contentItem: Rectangle {
            implicitHeight: 1
            color: "#EDF1F6"
        }
    }

    MenuItem {
        id: openMenuItem
        text: rowMenu.fileKind === "folder" ? "打开文件夹"
              : (uploadManager.openingFile ? "正在打开…" : "打开文件")
        enabled: rowMenu.fileKind === "folder" || !uploadManager.openingFile
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: openMenuItem.down ? "#E5EBFF"
                   : openMenuItem.hovered ? "#F1F4FF" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: rowMenu.fileKind === "folder" ? "#FFF4E2" : "#EEF2FF"

                Text {
                    anchors.centerIn: parent
                    text: rowMenu.fileKind === "folder" ? "▰" : "↗"
                    color: rowMenu.fileKind === "folder" ? "#E2A345" : host.primaryColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                text: openMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: openMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: {
            if (rowMenu.filePath.length === 0)
                return
            if (rowMenu.fileKind === "folder")
                host.openFolder(rowMenu.filePath)
            else
                uploadManager.openFile(rowMenu.filePath)
        }
    }

    MenuItem {
        id: downloadMenuItem
        text: uploadManager.downloading ? "正在下载…" : "下载到本地"
        enabled: !uploadManager.downloading
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: downloadMenuItem.down ? "#E5EBFF"
                   : downloadMenuItem.hovered ? "#F1F4FF" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: "#EEF2FF"

                Text {
                    anchors.centerIn: parent
                    text: "↓"
                    color: host.primaryColor
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                text: downloadMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: downloadMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: host.requestDownload(rowMenu.filePath, rowMenu.fileKind)
    }

    MenuItem {
        id: shareMenuItem
        text: "分享"
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: shareMenuItem.down ? "#E5EBFF"
                   : shareMenuItem.hovered ? "#F1F4FF" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: "#EEF2FF"

                Text {
                    anchors.centerIn: parent
                    text: "↗"
                    color: host.primaryColor
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                text: shareMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: shareMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }
    }

    MenuSeparator {
        topPadding: 5
        bottomPadding: 5
        contentItem: Rectangle {
            implicitHeight: 1
            color: "#EDF1F6"
        }
    }

    MenuItem {
        id: renameMenuItem
        text: uploadManager.renaming ? "正在重命名…" : "重命名"
        enabled: !uploadManager.renaming
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: renameMenuItem.down ? "#E9EEF7"
                   : renameMenuItem.hovered ? "#F5F7FB" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: "#F2F5F9"

                Text {
                    anchors.centerIn: parent
                    text: "✎"
                    color: "#71809B"
                    font.pixelSize: 15
                }
            }
            Text {
                Layout.fillWidth: true
                text: renameMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: renameMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: {
            if (rowMenu.filePath.length === 0)
                return
            renameController.openFor(rowMenu.filePath, rowMenu.fileName, rowMenu.fileKind)
        }
    }

    MenuItem {
        id: moveMenuItem
        text: uploadManager.moving ? "正在移动…" : "移动到"
        enabled: !uploadManager.moving
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: moveMenuItem.down ? "#E9EEF7"
                   : moveMenuItem.hovered ? "#F5F7FB" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: "#F2F5F9"

                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: "#71809B"
                    font.pixelSize: 16
                }
            }
            Text {
                Layout.fillWidth: true
                text: moveMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: moveMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: {
            if (rowMenu.filePath.length === 0)
                return
            moveController.openFor(rowMenu.filePath, rowMenu.fileName, rowMenu.fileKind)
        }
    }

    MenuItem {
        id: favoriteMenuItem
        text: uploadManager.updatingFavorite ? "正在添加…" : "添加到收藏"
        enabled: !uploadManager.updatingFavorite
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: favoriteMenuItem.down ? "#E9EEF7"
                   : favoriteMenuItem.hovered ? "#F5F7FB" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: "#F2F5F9"

                Text {
                    anchors.centerIn: parent
                    text: "☆"
                    color: "#71809B"
                    font.pixelSize: 17
                }
            }
            Text {
                Layout.fillWidth: true
                text: favoriteMenuItem.text
                color: "#40516B"
                font.pixelSize: 12
                font.weight: favoriteMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: {
            if (rowMenu.filePath.length === 0 || uploadManager.updatingFavorite)
                return
            // 文件夹递归由服务端完成，避免客户端逐项请求造成部分成功。
            uploadManager.addFavorite(rowMenu.filePath)
        }
    }

    MenuSeparator {
        topPadding: 5
        bottomPadding: 5
        contentItem: Rectangle {
            implicitHeight: 1
            color: "#EDF1F6"
        }
    }

    MenuItem {
        id: deleteMenuItem
        text: uploadManager.deleting ? "正在移入回收站…" : "删除"
        enabled: !uploadManager.deleting && rowMenu.filePath.length > 0
        implicitHeight: 40
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        indicator: null

        background: Rectangle {
            radius: 8
            color: deleteMenuItem.down ? "#FCE7E5"
                   : deleteMenuItem.hovered ? "#FFF3F2" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 29
                Layout.preferredHeight: 29
                radius: 7
                color: deleteMenuItem.hovered ? "#FCE6E4" : "#FFF1F0"

                Text {
                    anchors.centerIn: parent
                    text: "⌫"
                    color: "#DC716C"
                    font.pixelSize: 15
                }
            }
            Text {
                Layout.fillWidth: true
                text: deleteMenuItem.text
                color: "#D76561"
                font.pixelSize: 12
                font.weight: deleteMenuItem.hovered ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
        }

        onTriggered: host.requestDelete(rowMenu.filePath, rowMenu.fileName, rowMenu.fileKind)
    }
}
