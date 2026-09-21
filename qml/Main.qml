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
    property color textDark: "#1E2A45"
    property color textMid: "#71809B"
    property color textLight: "#A9B5C9"
    property color panel: "#FFFFFF"
    property color page: "#F7F9FD"
    property color line: "#E8EDF6"
    property bool  isMaximized: window.visibility === Window.Maximized

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

                Column {
                    anchors.fill: parent
                    anchors.margins: 0
                    spacing: 0

                    Item {
                        width: sidebar.width
                        height: 78
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

                    Column {
                        width: parent.width
                        spacing: 5
                        topPadding: 8
                        NavItem { width: sidebar.width;label: "首页"; icon: "home"; selected: true }
                        NavItem { width: sidebar.width;label: "文件"; icon: "file" }
                        NavItem { width: sidebar.width;label: "同步"; icon: "sync" }
                        NavItem { width: sidebar.width;label: "任务"; icon: "task" }
                        NavItem { width: sidebar.width;label: "历史"; icon: "history" }
                        NavItem { width: sidebar.width;label: "设置"; icon: "settings" }
                    }

                    Item { width: 1; height: 1; Layout.fillHeight: true }

                    Rectangle {
                        width: sidebar.width - 32
                        height: 1
                        color: "#273449"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 16
                    }

                    Item {
                        width: sidebar.width
                        height: 92
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
                            text: "张三"
                            color: "#EAF0FF"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.leftMargin: 72
                            anchors.top: parent.top
                            anchors.topMargin: 11
                        }
                        Text {
                            text: "zhangsan@example.com"
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
                            color: "#45D483"
                            anchors.left: parent.left
                            anchors.leftMargin: 23
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                        }
                        Text {
                            text: "已连接"
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

                Column{
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
                                iconSource: window.visibility === Window.Maximized
                                            ? "qrc:/qt/qml/FileSync/assets/window-restore.svg"
                                            : "qrc:/qt/qml/FileSync/assets/window-maximize.svg"
                                function show_from_spacing(spacing){
                                    login_panel_column.spacing=spacing
                                    select_login.transform = [ Qt.createQmlObject("import QtQuick 2.15; Translate{}", select_login) ]
                                    select_login.transform[0].y= login_panel_column.spacing * 2
                                    select_login_border_bottom.transform = [ Qt.createQmlObject("import QtQuick 2.15; Translate{}", select_login_border_bottom) ]
                                    select_login_border_bottom.transform[0].y= login_panel_column.spacing-2
                                }
                                onClicked: {
                                    if (window.visibility === Window.Maximized){
                                        show_from_spacing(0)
                                        window.showNormal()
                                    }
                                    else{
                                        show_from_spacing(15)
                                        window.showMaximized()
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

                    Row {
                        width: parent.width
                        height: parent.height - titleBar.height

                        // Branding / illustration panel
                        Rectangle {
                            width: parent.width * 0.50
                            height: parent.height
                            color: "#F8FBFF"

                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Image {
                                    width: 410
                                    height: 320
                                    source: "qrc:/qt/qml/FileSync/assets/hero-sync.svg"
                                    fillMode: Image.PreserveAspectFit
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: "FileSync"
                                    color: "#172B57"
                                    font.pixelSize: 34
                                    font.weight: Font.DemiBold
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: 4
                                }
                                Text {
                                    text: "让文件同步更简单"
                                    color: "#8190A8"
                                    font.pixelSize: 17
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: 6
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: 34
                                    spacing: 42
                                    Feature { icon: "✓"; text: "安全" }
                                    Feature { icon: "↔"; text: "高效" }
                                    Feature { icon: "◉"; text: "跨平台" }
                                }
                            }
                        }

                        // Login panel
                        Rectangle {
                            width: parent.width * 0.50
                            height: parent.height
                            color: "#FFFFFF"
                            bottomRightRadius: window.isMaximized ? 0 : window.windowCornerRadius // 替换为变量
                            antialiasing: true

                            Column {
                                id: login_panel_column
                                width: Math.min(parent.width - 88, 405)
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: parent.height*0.1
                                spacing: 0

                                Row {
                                    id: select_login
                                    width: parent.width
                                    height: 35
                                    z:1
                                    Item {
                                        width: parent.width / 2
                                        height: 35
                                        Text {
                                            text: "账号登录"
                                            color: window.primary
                                            font.pixelSize: 17
                                            font.weight: Font.DemiBold
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 2
                                        }
                                        Rectangle {
                                            width: 132
                                            height: 3
                                            radius: 2
                                            color: window.primary
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                        }
                                    }
                                    Item {
                                        width: parent.width / 2
                                        height: 35
                                        Text {
                                            text: "手机登录"
                                            color: "#69778E"
                                            font.pixelSize: 16
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 3
                                        }
                                    }
                                }

                                Rectangle {
                                    id:select_login_border_bottom
                                    transform: Translate {
                                        y: -2
                                    }
                                    width: parent.width
                                    height: 1
                                    color: "#EEF1F6"
                                }

                                Item {
                                   width: 1
                                   height: 32
                                }

                                LoginField {
                                    id: accountField
                                    width: parent.width
                                    height: 54
                                    icon: "user"
                                    placeholder: "请输入邮箱/手机号"
                                }

                                Item {
                                   width: 1
                                   height: 14
                                }

                                LoginField {
                                    id: passwordField
                                    width: parent.width
                                    height: 54
                                    icon: "lock"
                                    placeholder: "请输入密码"
                                    password: true
                                }

                                RowLayout {
                                    width: parent.width
                                    height: 44
                                    anchors.topMargin: 14

                                    CheckBox {
                                        id: remember
                                        text: "记住账号"
                                        checked: true
                                        spacing: 8
                                        indicator: Rectangle {
                                            implicitWidth: 18
                                            implicitHeight: 18
                                            x: remember.leftPadding
                                            y: parent.height / 2 - height / 2
                                            radius: 4
                                            border.width: remember.checked ? 0 : 1
                                            border.color: "#B9C4D5"
                                            color: remember.checked ? window.primary : "white"
                                            Text {
                                                visible: remember.checked
                                                text: "✓"
                                                color: "white"
                                                font.pixelSize: 13
                                                font.bold: true
                                                anchors.centerIn: parent
                                            }
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: "#6D7B92"
                                            font.pixelSize: 13
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: remember.indicator.width + remember.spacing
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: "忘记密码？"
                                        color: window.primary
                                        font.pixelSize: 13
                                        verticalAlignment: Text.AlignVCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                console.log("忘记密码")
                                            }
                                        }
                                    }
                                }

                                Button {
                                    id: loginButton
                                    width: parent.width
                                    height: 50
                                    topPadding: 6
                                    background: Rectangle {
                                        radius: 8
                                        color: loginButton.down ? window.primaryDark :
                                               loginButton.hovered ? "#5878F7" : window.primary
                                    }
                                    contentItem: Text {
                                        text: "登录"
                                        color: "white"
                                        font.pixelSize: 16
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        statusText.text = "登录功能已连接，可接入你的 C++ 网络层"
                                    }
                                }

                                Text {
                                    id: statusText
                                    width: parent.width
                                    text: "还没有账号？ 立即注册"
                                    color: "#73819A"
                                    font.pixelSize: 13
                                    horizontalAlignment: Text.AlignHCenter
                                    topPadding: 24
                                    Text {
                                        text: "立即注册"
                                        color: window.primary
                                        font.pixelSize: 13
                                        anchors.right: parent.right
                                        anchors.rightMargin: 88
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: false
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: 38
                                    topPadding: 28
                                    Rectangle { width: 130; height: 1; color: "#E6EAF1"; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "第三方登录"
                                        color: "#A0AABD"
                                        font.pixelSize: 12
                                        width: 88
                                        horizontalAlignment: Text.AlignHCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Rectangle { width: 130; height: 1; color: "#E6EAF1"; anchors.verticalCenter: parent.verticalCenter }
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: 12
                                    spacing: 36
                                    ThirdParty { source: "qrc:/qt/qml/FileSync/assets/icon-wechat.svg"; text: "微信" }
                                    ThirdParty { source: "qrc:/qt/qml/FileSync/assets/icon-qq.svg"; text: "QQ" }
                                    ThirdParty { source: "qrc:/qt/qml/FileSync/assets/icon-apple.svg"; text: "Apple" }
                                }
                            }
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
