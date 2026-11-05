import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import FileSyncComponents 1.0

ApplicationWindow {
    id: window
    width: 1120
    height: 750
    minimumWidth: 980
    minimumHeight: 680
    visible: true
    title: "FileSync"
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.Window | Qt.NoDropShadowWindowHint

    // 主题色
    property color primary: "#4B6EF5"
    property color primaryDark: "#3558DD"
    property color primarySuccess: "#34C759"
    property color textDark: "#1E2A45"
    property color textMid: "#71809B"
    property color textLight: "#A9B5C9"
    property color panel: "#FFFFFF"
    property color page: "#F7F9FD"
    property color line: "#E8EDF6"
    property bool isMaximized: window.visibility === Window.Maximized

    // ========== 统一窗口圆角变量，改这里就能同步所有外层圆角 ==========
    property int windowCornerRadius: 8

    // 窗口背景+边框层
    Rectangle {
        id: windowFrame
        anchors.fill: parent
        radius: window.isMaximized ? 0 : window.windowCornerRadius // 替换为变量
        color: "transparent"
        border.width: 0
        antialiasing: true

        // 所有页面内容容器
        RowLayout {
            id: contentContainer
            anchors.fill: parent
            spacing: 0
            // Left navigation 侧边栏
            Rectangle {
                id: sidebar
                Layout.preferredWidth: 202
                Layout.fillHeight: true
                color: "#111C2C"
                // 只圆左边两个角
                topLeftRadius: window.isMaximized ? 0 : window.windowCornerRadius    // 替换为变量
                bottomLeftRadius: window.isMaximized ? 0 : window.windowCornerRadius // 替换为变量
                // 右边保持直角
                topRightRadius: 0
                bottomRightRadius: 0
                antialiasing: true
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ============================================================
                    // Logo
                    // ============================================================
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 78

                        Image {
                            source: "qrc:/qt/qml/FileSync/assets/logo.svg"
                            width: 36
                            height: 36
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "FileSync"
                            color: "#F6F9FF"
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.leftMargin: 70
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // ============================================================
                    // 导航
                    // ============================================================
                    Column {
                        Layout.fillWidth: true
                        spacing: 5
                        topPadding: 8
                        property int currentIndex: 0

                        NavItem {
                            width: sidebar.width
                            label: "首页"
                            icon: "home"
                            selected: parent.currentIndex === 0
                            onClicked: main_area_stack.currentIndex = parent.currentIndex = 0
                        }
                        NavItem {
                            width: sidebar.width
                            label: "文件"
                            icon: "file"
                            selected: parent.currentIndex === 1
                            onClicked:main_area_stack.currentIndex = parent.currentIndex = 1
                        }
                        NavItem {
                            width: sidebar.width
                            label: "同步"
                            icon: "sync"
                            selected: parent.currentIndex === 2
                            onClicked: parent.currentIndex = 2
                        }
                        NavItem {
                            width: sidebar.width
                            label: "任务"
                            icon: "task"
                            selected: parent.currentIndex === 3
                            onClicked: parent.currentIndex = 3
                        }
                        NavItem {
                            width: sidebar.width
                            label: "历史"
                            icon: "history"
                            selected: parent.currentIndex === 4
                            onClicked: parent.currentIndex = 4
                        }
                        NavItem {
                            width: sidebar.width
                            label: "设置"
                            icon: "settings"
                            selected: parent.currentIndex === 4
                            onClicked: parent.currentIndex = 4
                        }
                    }

                    // ============================================================
                    // 分隔线
                    // ============================================================
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: sidebar.width - 32
                        Layout.preferredHeight: 1

                        color: "#273449"

                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.topMargin: 8
                    }

                    // ============================================================
                    // 撑开剩余空间，把底部内容推到底部
                    // ============================================================
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    // ============================================================
                    // 用户信息
                    // ============================================================
                    Item {
                        id:user_info
                        property bool isLogin: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        Layout.bottomMargin: 10
                        Image {
                            source: "qrc:/qt/qml/FileSync/assets/avatar.svg"
                            width: 42
                            height: 42
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.top: parent.top
                            anchors.topMargin: 8
                        }
                        Text {
                            text: "未登录"
                            color: "#EAF0FF"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.leftMargin: 72
                            anchors.top: parent.top
                            anchors.topMargin: 11
                        }
                        Text {
                            text: "登录后同步您的文件"
                            color: "#7F8DA5"
                            font.pixelSize: 10
                            anchors.left: parent.left
                            anchors.leftMargin: 72
                            anchors.top: parent.top
                            anchors.topMargin: 34
                        }
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: user_info.isLogin ? "#45D483" : "#9CA3AF"
                            anchors.left: parent.left
                            anchors.leftMargin: 23
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                        }
                        Text {
                            text: user_info.isLogin? "已连接" : "未连接"
                            color: "#AFC2D9"
                            font.pixelSize: 11
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                        }
                    }
                }
            }

            // Main login area 主区域
            Rectangle {
                id: mainArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: window.page
                // 只圆右边两个角
                topRightRadius: window.isMaximized ? 0 : window.windowCornerRadius    // 替换为变量
                bottomRightRadius: window.isMaximized ? 0 : window.windowCornerRadius // 替换为变量
                // 左边保持直角
                topLeftRadius: 0
                bottomLeftRadius: 0
                antialiasing: true

                Item {
                    anchors.fill: parent

                    // Custom title bar
                    Item {
                        id: titleBar
                        width: parent.width
                        height: 42
                        MouseArea {
                            anchors.fill: parent
                            onPressed: window.startSystemMove()
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            WindowButton {
                                iconSource: "qrc:/qt/qml/FileSync/assets/window-minimize.svg"
                                onClicked: window.showMinimized()
                            }
                            WindowButton {
                                iconSource: window.visibility === Window.Maximized ? "qrc:/qt/qml/FileSync/assets/window-restore.svg" : "qrc:/qt/qml/FileSync/assets/window-maximize.svg"
                                onClicked: {
                                    if (window.visibility === Window.Maximized) {
                                        sidebar.Layout.preferredWidth = 202
                                        window.showNormal();
                                    } else {
                                        sidebar.Layout.preferredWidth = 302
                                        window.showMaximized();
                                    }
                                }
                            }
                            WindowButton {
                                iconSource: "qrc:/qt/qml/FileSync/assets/window-close.svg"
                                danger: true
                                onClicked: window.close()
                            }
                        }
                    }
                    StackLayout
                    {
                        id: main_area_stack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: titleBar.bottom
                        anchors.bottom: parent.bottom
                        currentIndex: 0
                        LoginSection {
                            primaryColor: window.primary
                            primaryDarkColor: window.primaryDark

                            maximized: window.visibility === Window.Maximized
                            cornerRadius: window.windowCornerRadius
                        }

                        FileSection{
                        }
                    }


                }
            }
        }

        // 最上层圆角边框
        Rectangle {
            id: windowBorder
            anchors.fill: parent
            color: "transparent"
            radius: window.isMaximized ? 0 : window.windowCornerRadius // 替换为变量
            border.color: "#DCE3F0"
            border.width: window.isMaximized ? 0 : 1
            antialiasing: true
            z: 9999
            enabled: false
        }
    }
}
