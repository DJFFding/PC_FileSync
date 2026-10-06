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
        Item {
            id: contentContainer
            anchors.fill: parent
            clip: false

            // Left navigation 侧边栏
            Rectangle {
                id: sidebar
                width: 202
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
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
                        NavItem {
                            width: sidebar.width
                            label: "首页"
                            icon: "home"
                            selected: true
                        }
                        NavItem {
                            width: sidebar.width
                            label: "文件"
                            icon: "file"
                        }
                        NavItem {
                            width: sidebar.width
                            label: "同步"
                            icon: "sync"
                        }
                        NavItem {
                            width: sidebar.width
                            label: "任务"
                            icon: "task"
                        }
                        NavItem {
                            width: sidebar.width
                            label: "历史"
                            icon: "history"
                        }
                        NavItem {
                            width: sidebar.width
                            label: "设置"
                            icon: "settings"
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
                anchors.left: sidebar.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
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
                                function show_from_spacing(spacing) {
                                    login_panel_column.spacing = spacing;
                                    select_login.transform = [Qt.createQmlObject("import QtQuick 2.15; Translate{}", select_login)];
                                    select_login.transform[0].y = login_panel_column.spacing * 2;
                                    select_login_border_bottom.transform = [Qt.createQmlObject("import QtQuick 2.15; Translate{}", select_login_border_bottom)];
                                    select_login_border_bottom.transform[0].y = login_panel_column.spacing - 2;
                                }
                                onClicked: {
                                    if (window.visibility === Window.Maximized) {
                                        window.showNormal();
                                    } else {
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
                    LoginSection {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: titleBar.bottom
                        anchors.bottom: parent.bottom

                        primaryColor: window.primary
                        primaryDarkColor: window.primaryDark

                        maximized: window.visibility === Window.Maximized
                        cornerRadius: window.windowCornerRadius
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
