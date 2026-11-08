import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/*
 * FileSync 下载结果弹窗。
 *
 * 用法：
 * DownloadResultDialog {
 *     id: downloadResultDialog
 * }
 *
 * downloadResultDialog.showResult(true, false, localFilePath, "")
 */
Dialog {
    id: root

    // 下载结果
    property bool succeeded: true
    property bool isFolder: false
    property string localPath: ""
    property string reason: ""

    // 与 FileSection.qml 保持一致的主题色
    readonly property color primaryColor: "#4B6EF5"
    readonly property color primaryDarkColor: "#3558DD"
    readonly property color textDarkColor: "#1E2A45"
    readonly property color textMidColor: "#71809B"
    readonly property color textLightColor: "#A9B5C9"
    readonly property color lineColor: "#E8EDF6"
    readonly property color successColor: "#28B985"
    readonly property color failureColor: "#E16F6A"

    anchors.centerIn: Overlay.overlay
    width: 440
    height: 322
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function showResult(ok, folder, path, errorMessage) {
        root.succeeded = !!ok
        root.isFolder = !!folder
        root.localPath = path === undefined || path === null ? "" : path.toString()
        root.reason = errorMessage === undefined || errorMessage === null
                ? "" : errorMessage.toString()
        root.open()
    }

    Overlay.modal: Rectangle {
        color: "#66000000"
    }

    background: Rectangle {
        color: "#FFFFFF"
        radius: 13
        border.width: 1
        border.color: "#E4EAF4"
        antialiasing: true
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 140
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.96
            to: 1.0
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    contentItem: Item {
        implicitWidth: 440
        implicitHeight: 322

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 0

            // 标题栏
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "下载结果"
                    color: root.textDarkColor
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }

                Button {
                    id: closeButton
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    background: Rectangle {
                        radius: 6
                        color: closeButton.hovered ? "#F2F5FA" : "transparent"
                    }
                    contentItem: Text {
                        text: "×"
                        color: closeButton.hovered ? "#53637D" : "#8D9AB0"
                        font.pixelSize: 19
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.close()
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 15 }

            // 状态图标与说明
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                spacing: 13

                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: root.succeeded ? "#EAF8F2" : "#FFF0EF"
                    border.width: 1
                    border.color: root.succeeded ? "#D7F1E6" : "#F9DEDC"

                    Text {
                        anchors.centerIn: parent
                        text: root.succeeded ? "✓" : "!"
                        color: root.succeeded ? root.successColor : root.failureColor
                        font.pixelSize: root.succeeded ? 25 : 23
                        font.weight: Font.DemiBold
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        text: root.succeeded ? "下载成功" : "下载失败"
                        color: root.textDarkColor
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.succeeded
                              ? (root.isFolder ? "文件夹及其内容已成功保存到本地。"
                                               : "文件已成功保存到本地。")
                              : (root.isFolder ? "文件夹下载过程中出现问题。"
                                               : "文件下载过程中出现问题。")
                        color: root.textMidColor
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 17 }

            // 保存路径 / 失败原因信息卡片
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 116
                radius: 9
                color: "#F8FAFD"
                border.width: 1
                border.color: "#E7EDF6"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    Text {
                        Layout.fillWidth: true
                        text: root.succeeded ? "本地保存位置" : "失败原因"
                        color: "#8492A8"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    ScrollView {
                        id: resultScrollView

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        ScrollBar.horizontal: ScrollBar {
                            policy: ScrollBar.AlwaysOff
                        }

                        TextArea {
                            id: resultTextArea
                            width: resultScrollView.availableWidth

                            text: root.succeeded
                                  ? (root.localPath.length > 0 ? root.localPath : "未返回本地保存路径")
                                  : (root.reason.length > 0 ? root.reason : "未知错误，请检查网络连接后重试。")
                            color: root.succeeded ? "#53637D" : "#C56F69"
                            font.pixelSize: 11
                            wrapMode: TextEdit.WrapAnywhere
                            readOnly: true
                            selectByMouse: true
                            selectByKeyboard: true
                            selectionColor: root.primaryColor
                            selectedTextColor: "#FFFFFF"
                            padding: 0
                            background: Item {}
                            persistentSelection: true
                        }
                    }}
            }

            Item { Layout.fillWidth: true; Layout.fillHeight: true }

            // 底部操作
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 9

                Item { Layout.fillWidth: true }

                Button {
                    id: confirmButton
                    Layout.preferredWidth: 86
                    Layout.preferredHeight: 36
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    background: Rectangle {
                        radius: 8
                        color: confirmButton.down ? root.primaryDarkColor
                               : confirmButton.hovered ? "#5878F7" : root.primaryColor
                    }
                    contentItem: Text {
                        text: "知道了"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.close()
                }
            }
        }
    }
}
