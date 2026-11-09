import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: recentClearDialog
    required property Item host
    anchors.centerIn: parent
    width: 410
    height: 224
    padding: 0
    modal: true
    focus: true
    closePolicy: uploadManager.updatingRecent ? Popup.NoAutoClose : Popup.CloseOnEscape

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
            spacing: 13

            Row {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 34
                    height: 34
                    radius: 9
                    color: "#EEF2FF"
                    Text {
                        anchors.centerIn: parent
                        text: "◷"
                        color: host.primaryColor
                        font.pixelSize: 19
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "清空最近使用记录？"
                    color: host.textDarkColor
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "将移除全部 " + host.recentModelSource.count
                      + " 条最近使用快捷入口。此操作不会删除或移动任何原文件，后续使用仍会重新生成记录。"
                color: host.textMidColor
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                lineHeight: 1.25
                verticalAlignment: Text.AlignVCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 9
                Item { Layout.fillWidth: true }
                Button {
                    id: cancelClearRecentButton
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 36
                    enabled: !uploadManager.updatingRecent
                    hoverEnabled: true
                    background: Rectangle {
                        radius: 8
                        color: cancelClearRecentButton.hovered ? "#F4F6FA" : "#FFFFFF"
                        border.color: "#DFE6F1"
                    }
                    contentItem: Text {
                        text: "取消"
                        color: cancelClearRecentButton.enabled ? "#596981" : "#A7B2C2"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: recentClearDialog.close()
                }
                Button {
                    id: confirmClearRecentButton
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 36
                    enabled: !uploadManager.updatingRecent
                    hoverEnabled: true
                    background: Rectangle {
                        radius: 8
                        color: !confirmClearRecentButton.enabled ? "#AAB8E8"
                               : confirmClearRecentButton.down ? host.primaryDarkColor
                               : confirmClearRecentButton.hovered ? "#5878F7" : host.primaryColor
                    }
                    contentItem: Text {
                        text: uploadManager.updatingRecent ? "正在清空…" : "确认清空"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: host.recentClearRequested()
                }
            }
        }
    }
}

// 收藏操作结果：成功时显示实际新增/移除数量，失败时保留原列表并提示原因。
