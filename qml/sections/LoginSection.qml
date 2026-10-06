import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FileSyncComponents 1.0

Item {
    id: root

    // ============================================================
    // 对外属性
    // ============================================================

    property color primaryColor: "#4B6EF5"
    property color primaryDarkColor: "#3558DD"

    property color textDarkColor: "#1E2A45"
    property color textMidColor: "#71809B"
    property color textLightColor: "#A9B5C9"

    property color panelColor: "#FFFFFF"
    property color pageColor: "#F7F9FD"
    property color lineColor: "#E8EDF6"

    // 当前窗口是否最大化
    property bool maximized: false

    // 非最大化时的圆角
    property real cornerRadius: 14

    // ============================================================
    // 对外信号
    // ============================================================

    signal loginRequested(int loginType, string account, string password)
    signal registerRequested(int registerType)

    signal forgotPasswordRequested
    signal verificationCodeRequested(string target)

    // ============================================================
    // 登录主体
    // ============================================================

    Row {
        id: content

        anchors.fill: parent

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
                    color: root.textDarkColor
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 4
                }

                Text {
                    text: "让文件同步更简单"
                    color: root.textMidColor
                    font.pixelSize: 17
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 6
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 34
                    spacing: 42

                    Feature {
                        icon: "✓"
                        text: "安全"
                    }

                    Feature {
                        icon: "↔"
                        text: "高效"
                    }

                    Feature {
                        icon: "◉"
                        text: "跨平台"
                    }
                }
            }
        }

        // Login panel
        Rectangle {
            width: parent.width * 0.50
            height: parent.height
            color: root.panelColor
            bottomRightRadius:  root.maximized ? 0 : root.cornerRadius
            antialiasing: true
            Column {
                id: login_panel_column

                width: Math.min(parent.width - 88, 405)
                height: authViewport.height
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.1
                spacing: 0

                // false = 登录界面，true = 注册界面
                property bool registerMode: false

                Item {
                    id: authViewport
                    width: parent.width
                    height: login_panel_column.registerMode ? registerPage.implicitHeight : loginPage.implicitHeight
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutCubic
                        }
                    }

                    // ============================================================
                    // 登录页面
                    // ============================================================
                    Column {
                        id: loginPage
                        width: authViewport.width
                        spacing: 0

                        x: login_panel_column.registerMode ? -authViewport.width : 0

                        opacity: login_panel_column.registerMode ? 0 : 1
                        scale: login_panel_column.registerMode ? 0.98 : 1

                        Behavior on x {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 260
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }
                        Item {
                            id: select_login
                            width: parent.width
                            height: 35
                            z: 1

                            property int currentIndex: 0

                            // 账号登录
                            Item {
                                id: accountTab

                                width: parent.width / 2
                                height: 35

                                Text {
                                    text: "账号登录"

                                    color: select_login.currentIndex === 0 ? root.primaryColor : "#69778E"

                                    font.pixelSize: select_login.currentIndex === 0 ? 17 : 16

                                    font.weight: select_login.currentIndex === 0 ? Font.DemiBold : Font.Normal

                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        select_login.currentIndex = 0;
                                    }
                                }
                            }

                            // 手机登录
                            Item {
                                id: phoneTab

                                width: parent.width / 2
                                height: 35

                                anchors.right: parent.right

                                Text {
                                    text: "手机登录"

                                    color: select_login.currentIndex === 1 ? root.primaryColor : "#69778E"

                                    font.pixelSize: select_login.currentIndex === 1 ? 17 : 16

                                    font.weight: select_login.currentIndex === 1 ? Font.DemiBold : Font.Normal

                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        select_login.currentIndex = 1;
                                    }
                                }
                            }

                            // 指示器
                            Rectangle {
                                id: indicator

                                width: 132
                                height: 3
                                radius: 2

                                color: root.primaryColor

                                y: parent.height - height

                                x: select_login.currentIndex === 0 ? accountTab.x + (accountTab.width - width) / 2 : phoneTab.x + (phoneTab.width - width) / 2

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 280
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                        Rectangle {
                            id: select_login_border_bottom
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
                        // ============================================================
                        // 登录内容区域
                        // ============================================================
                        Item {
                            id: login_content

                            width: parent.width
                            height: accountField.accountError || phoneField.accountError ? 218 : 190

                            Behavior on height {
                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                            }

                            clip: true

                            // ========================================================
                            // 账号登录面板
                            // ========================================================
                            Item {
                                id: accountLoginPanel

                                width: login_content.width
                                height: login_content.height

                                x: select_login.currentIndex === 0 ? 0 : -login_content.width

                                opacity: select_login.currentIndex === 0 ? 1 : 0

                                scale: select_login.currentIndex === 0 ? 1 : 0.98

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 14

                                    Item {
                                        width: parent.width
                                        height: accountField.accountError ? 82 : 54

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        LoginField {
                                            id: accountField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 54

                                            icon: "user"
                                            placeholder: "请输入邮箱/手机号"
                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Phone | LoginField.ValidateWhat.Email
                                        }
                                    }

                                    // -------------------------
                                    // 密码
                                    // -------------------------
                                    LoginField {
                                        id: passwordField

                                        width: parent.width
                                        height: 54

                                        icon: "lock"
                                        placeholder: "请输入密码"

                                        password: true
                                    }

                                    // -------------------------
                                    // 底部操作
                                    // -------------------------
                                    RowLayout {
                                        width: parent.width
                                        height: 44

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

                                                color: remember.checked ? root.primaryColor : "white"

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

                                            color: root.primaryColor
                                            font.pixelSize: 13

                                            verticalAlignment: Text.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent

                                                cursorShape: Qt.PointingHandCursor

                                                onClicked: {
                                                    console.log("忘记密码");
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ========================================================
                            // 手机登录面板
                            // ========================================================
                            Item {
                                id: phoneLoginPanel

                                width: login_content.width
                                height: login_content.height

                                x: select_login.currentIndex === 1 ? 0 : login_content.width

                                opacity: select_login.currentIndex === 1 ? 1 : 0

                                scale: select_login.currentIndex === 1 ? 1 : 0.98

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 14

                                    // ------------------------------------------------
                                    // 手机号
                                    // ------------------------------------------------
                                    Item {
                                        width: parent.width
                                        height: phoneField.accountError ? 82 : 54

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: phoneField

                                            width: parent.width
                                            height: 54

                                            icon: "smartphone"
                                            placeholder: "请输入手机号"
                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Phone
                                        }
                                    }

                                    // ------------------------------------------------
                                    // 验证码
                                    // ------------------------------------------------
                                    Row {
                                        width: parent.width
                                        height: 54

                                        spacing: 10

                                        LoginField {
                                            id: verifyCodeField

                                            width: parent.width - 114
                                            height: 54

                                            icon: "verification_code"
                                            placeholder: "请输入短信验证码"
                                        }

                                        Rectangle {
                                            id: sendCodeButton

                                            width: 104
                                            height: 54

                                            radius: 9

                                            color: sendCodeMouseArea.containsMouse ? root.primaryDarkColor : root.primaryColor

                                            Text {
                                                id: sendCodeText

                                                anchors.centerIn: parent

                                                text: phoneLoginPanel.countDown > 0 ? phoneLoginPanel.countDown + " 秒" : "获取验证码"

                                                color: "white"

                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: sendCodeMouseArea

                                                anchors.fill: parent

                                                hoverEnabled: true

                                                cursorShape: phoneLoginPanel.countDown > 0 ? Qt.ArrowCursor : Qt.PointingHandCursor

                                                onClicked: {
                                                    if (phoneLoginPanel.countDown > 0)
                                                        return;
                                                    var phone = phoneField.text;
                                                    var result = phoneField.validatePhone(phone);
                                                    if (!result.valid) {
                                                        phoneField.focus_error = true;
                                                        phoneField.error_text = result.message;
                                                        registerStatusMessage.text = result.message;
                                                        registerStatusMessage.visible = true;
                                                        return;
                                                    }

                                                    console.log("发送验证码");

                                                    phoneLoginPanel.countDown = 60;
                                                    codeTimer.start();
                                                }
                                            }

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 120
                                                }
                                            }
                                        }
                                    }

                                    // ------------------------------------------------
                                    // 底部操作
                                    // ------------------------------------------------
                                    RowLayout {
                                        width: parent.width
                                        height: 44

                                        CheckBox {
                                            id: rememberPhone

                                            text: "记住手机号"
                                            checked: true

                                            spacing: 8

                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18

                                                x: rememberPhone.leftPadding
                                                y: parent.height / 2 - height / 2

                                                radius: 4

                                                border.width: rememberPhone.checked ? 0 : 1
                                                border.color: "#B9C4D5"

                                                color: rememberPhone.checked ? root.primaryColor : "white"

                                                Text {
                                                    visible: rememberPhone.checked

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

                                                leftPadding: rememberPhone.indicator.width + rememberPhone.spacing
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: "收不到验证码？"

                                            color: root.primaryColor

                                            font.pixelSize: 13

                                            verticalAlignment: Text.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent

                                                cursorShape: Qt.PointingHandCursor

                                                onClicked: {
                                                    console.log("收不到验证码");
                                                }
                                            }
                                        }
                                    }
                                }

                                // ====================================================
                                // 验证码倒计时
                                // ====================================================
                                property int countDown: 0

                                Timer {
                                    id: codeTimer

                                    interval: 1000
                                    repeat: true

                                    onTriggered: {
                                        if (phoneLoginPanel.countDown > 0) {
                                            phoneLoginPanel.countDown--;
                                        }

                                        if (phoneLoginPanel.countDown <= 0) {
                                            stop();
                                        }
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
                                color: loginButton.down ? root.primaryDarkColor : loginButton.hovered ? "#5878F7" : root.primaryColor
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
                                loginStatusLabel.text = "登录功能已连接，可接入你的 C++ 网络层";
                            }
                        }

                        Item {
                            id: statusText
                            width: parent.width
                            height: 52

                            Row {
                                id: loginStatusRow
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 24
                                spacing: 3

                                Text {
                                    id: loginStatusLabel
                                    text: "还没有账号？"
                                    color: "#73819A"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    id: registerEntryText
                                    text: "立即注册"
                                    color: registerEntryMouse.containsMouse ? root.primaryDarkColor : root.primaryColor
                                    font.pixelSize: 13
                                    font.weight: registerEntryMouse.containsMouse ? Font.DemiBold : Font.Normal
                                    font.underline: registerEntryMouse.containsMouse
                                    verticalAlignment: Text.AlignVCenter

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }

                                    MouseArea {
                                        id: registerEntryMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            login_panel_column.registerMode = true;
                                        }
                                    }
                                }
                            }

                            Text {
                                id: loginStatusMessage
                                visible: false
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 24
                                color: "#73819A"
                                font.pixelSize: 13
                            }
                        }
                        Item {
                            width: 1
                            height: 28
                        }
                        Row {
                            width: parent.width
                            height: 38
                            Rectangle {
                                width: (parent.width - thirdParityLoginText.width) / 2
                                height: 1
                                color: "#E6EAF1"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: thirdParityLoginText
                                text: "第三方登录"
                                color: "#A0AABD"
                                font.pixelSize: 12
                                width: 88
                                horizontalAlignment: Text.AlignHCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: (parent.width - thirdParityLoginText.width) / 2
                                height: 1
                                color: "#E6EAF1"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 12
                            spacing: 36
                            ThirdParty {
                                source: "qrc:/qt/qml/FileSync/assets/icon-wechat.svg"
                                text: "微信"
                            }
                            ThirdParty {
                                source: "qrc:/qt/qml/FileSync/assets/icon-qq.svg"
                                text: "QQ"
                            }
                            ThirdParty {
                                source: "qrc:/qt/qml/FileSync/assets/icon-apple.svg"
                                text: "Apple"
                            }
                        }
                    }

                    // ============================================================
                    // 注册页面：账号注册 / 手机注册
                    // ============================================================
                    Column {
                        id: registerPage
                        width: authViewport.width
                        spacing: 0

                        property int currentIndex: 0
                        property int emailCodeCountDown: 0
                        property int phoneCodeCountDown: 0

                        x: login_panel_column.registerMode ? 0 : authViewport.width
                        opacity: login_panel_column.registerMode ? 1 : 0
                        scale: login_panel_column.registerMode ? 1 : 0.98

                        Behavior on x {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 260
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }

                        // 注册页 Tab
                        Item {
                            id: select_register
                            width: parent.width
                            height: 35
                            z: 1

                            Item {
                                id: accountRegisterTab
                                width: parent.width / 2
                                height: 35

                                Text {
                                    text: "账号注册"
                                    color: registerPage.currentIndex === 0 ? root.primaryColor : "#69778E"
                                    font.pixelSize: registerPage.currentIndex === 0 ? 17 : 16
                                    font.weight: registerPage.currentIndex === 0 ? Font.DemiBold : Font.Normal
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: registerPage.currentIndex = 0
                                }
                            }

                            Item {
                                id: phoneRegisterTab
                                width: parent.width / 2
                                height: 35
                                anchors.right: parent.right

                                Text {
                                    text: "手机注册"
                                    color: registerPage.currentIndex === 1 ? root.primaryColor : "#69778E"
                                    font.pixelSize: registerPage.currentIndex === 1 ? 17 : 16
                                    font.weight: registerPage.currentIndex === 1 ? Font.DemiBold : Font.Normal
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: registerPage.currentIndex = 1
                                }
                            }

                            Rectangle {
                                id: registerIndicator
                                width: 132
                                height: 3
                                radius: 2
                                color: root.primaryColor
                                y: parent.height - height

                                x: registerPage.currentIndex === 0 ? accountRegisterTab.x + (accountRegisterTab.width - width) / 2 : phoneRegisterTab.x + (phoneRegisterTab.width - width) / 2

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 280
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: "#EEF1F6"
                            transform: Translate {
                                y: -2
                            }
                        }

                        Item {
                            width: 1
                            height: 16
                        }

                        // 注册表单容器
                        Item {
                            id: registerFormViewport
                            width: parent.width
                            height: 364

                            Item {
                                id: accountRegisterPanel
                                width: registerFormViewport.width
                                height: registerFormViewport.height

                                x: registerPage.currentIndex === 0 ? 0 : -registerFormViewport.width
                                opacity: registerPage.currentIndex === 0 ? 1 : 0
                                scale: registerPage.currentIndex === 0 ? 1 : 0.98

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    Item {
                                        Layout.fillWidth: true

                                        height: registerUserNameField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerUserNameField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 50

                                            icon: "user"
                                            placeholder: "请输入用户名"

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.UserName
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }

                                    Item {
                                        Layout.fillWidth: true

                                        height: registerEmailField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        LoginField {
                                            id: registerEmailField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 50

                                            icon: "email"
                                            placeholder: "请输入邮箱"

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Email
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }

                                    Item {
                                        Layout.fillWidth: true

                                        height: registerEmailCodeField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        RowLayout {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 50

                                            spacing: 10

                                            LoginField {
                                                id: registerEmailCodeField

                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                icon: "email_code"
                                                placeholder: "请输入邮箱验证码"

                                                validateAccount: true
                                                validateWhat: LoginField.ValidateWhat.EmailCode
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 104
                                                Layout.minimumWidth: 104
                                                Layout.maximumWidth: 104

                                                Layout.fillHeight: true

                                                radius: 9

                                                color: emailCodeMouse.containsMouse ? root.primaryDarkColor : root.primaryColor

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: registerPage.emailCodeCountDown > 0 ? registerPage.emailCodeCountDown + " 秒" : "获取验证码"

                                                    color: "white"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }

                                                MouseArea {
                                                    id: emailCodeMouse
                                                    anchors.fill: parent

                                                    hoverEnabled: true

                                                    cursorShape: registerPage.emailCodeCountDown > 0 ? Qt.ArrowCursor : Qt.PointingHandCursor

                                                    onClicked: {
                                                        if (registerPage.emailCodeCountDown > 0)
                                                            return;
                                                        var email = registerEmailField.text;
                                                        var result = registerEmailField.validateEmail(email);
                                                        if (!result.valid) {
                                                            registerEmailField.focus_error = true;
                                                            registerEmailField.error_text = result.message;
                                                            registerStatusMessage.text = result.message;

                                                            registerStatusMessage.visible = true;

                                                            return;
                                                        }
                                                        registerStatusMessage.text = "邮箱验证码已发送";
                                                        registerStatusMessage.visible = true;

                                                        registerPage.emailCodeCountDown = 60;
                                                        emailCodeTimer.start();
                                                    }
                                                }

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 120
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }
                                    Item {
                                        Layout.fillWidth: true

                                        height: registerAccountPasswordField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerAccountPasswordField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 50

                                            icon: "lock"
                                            placeholder: "请设置8-20位密码"
                                            password: true

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Password
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }
                                    Item {
                                        Layout.fillWidth: true

                                        height: registerAccountConfirmPasswordField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerAccountConfirmPasswordField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top

                                            height: 50

                                            icon: "lock"
                                            placeholder: "请再次输入密码"
                                            password: true

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.RePassword
                                        }
                                    }
                                }
                            }

                            Item {
                                id: phoneRegisterPanel
                                width: registerFormViewport.width
                                height: registerFormViewport.height

                                x: registerPage.currentIndex === 1 ? 0 : registerFormViewport.width
                                opacity: registerPage.currentIndex === 1 ? 1 : 0
                                scale: registerPage.currentIndex === 1 ? 1 : 0.98

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 360
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    Item {
                                        Layout.fillWidth: true

                                        height: registerPhoneField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerPhoneField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 50
                                            icon: "smartphone"
                                            placeholder: "请输入手机号"

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Phone
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }
                                    Item {
                                        Layout.fillWidth: true

                                        height: registerSmsCodeField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        RowLayout {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 50

                                            spacing: 10
                                            LoginField {
                                                id: registerSmsCodeField

                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                icon: "verification_code"
                                                placeholder: "请输入短信验证码"

                                                validateAccount: true
                                                validateWhat: LoginField.ValidateWhat.PhoneCode
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 104
                                                Layout.minimumWidth: 104
                                                Layout.maximumWidth: 104

                                                Layout.fillHeight: true

                                                radius: 9

                                                color: smsCodeMouse.containsMouse ? root.primaryDarkColor : root.primaryColor

                                                Text {
                                                    anchors.centerIn: parent

                                                    text: registerPage.phoneCodeCountDown > 0 ? registerPage.phoneCodeCountDown + " 秒" : "获取验证码"

                                                    color: "white"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }

                                                MouseArea {
                                                    id: smsCodeMouse

                                                    anchors.fill: parent
                                                    hoverEnabled: true

                                                    cursorShape: registerPage.phoneCodeCountDown > 0 ? Qt.ArrowCursor : Qt.PointingHandCursor

                                                    onClicked: {
                                                        if (registerPage.phoneCodeCountDown > 0)
                                                            return;

                                                        var phone = registerPhoneField.text;
                                                        var result = registerPhoneField.validatePhone(phone);
                                                        if (!result.valid) {
                                                            registerPhoneField.focus_error = true;
                                                            registerPhoneField.error_text = result.message;
                                                            registerStatusMessage.text = result.message;
                                                            registerStatusMessage.visible = true;
                                                            return;
                                                        }

                                                        registerStatusMessage.text = "短信验证码已发送";
                                                        registerStatusMessage.visible = true;

                                                        registerPage.phoneCodeCountDown = 60;
                                                        phoneCodeTimer.start();
                                                    }
                                                }

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 120
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }
                                    Item {
                                        Layout.fillWidth: true

                                        height: registerPhonePasswordField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerPhonePasswordField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 50

                                            icon: "lock"
                                            placeholder: "请设置8-20位密码"
                                            password: true

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.Password
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }

                                    Item {
                                        Layout.fillWidth: true

                                        height: registerPhoneConfirmPasswordField.accountError ? 82 : 50
                                        Layout.preferredHeight: height

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        LoginField {
                                            id: registerPhoneConfirmPasswordField

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 50

                                            icon: "lock"
                                            placeholder: "请再次输入密码"
                                            password: true

                                            validateAccount: true
                                            validateWhat: LoginField.ValidateWhat.RePassword
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 50
                                        Layout.maximumHeight: 50
                                        opacity: 0.0 // 完全透明，占位保留
                                        // 如果不想被点击，加上这一行
                                        enabled: false
                                    }
                                }
                            }
                        }

                        Item {
                            width: 1
                            height: 18
                        }

                        Button {
                            id: registerButton
                            width: parent.width
                            height: 50
                            topPadding: 6

                            background: Rectangle {
                                radius: 8
                                color: registerButton.down ? root.primaryDarkColor : registerButton.hovered ? "#5878F7" : root.primaryColor
                            }

                            contentItem: Text {
                                text: "注册"
                                color: "white"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                registerStatusMessage.visible = true;

                                if (registerPage.currentIndex === 0) {
                                    var username = registerUserNameField.text;
                                    var result = registerUserNameField.validateUsername(username);
                                    if (!result.valid) {
                                        registerUserNameField.focus_error = true;
                                        registerUserNameField.error_text = result.message;
                                        registerStatusMessage.text = result.message;
                                        return;
                                    }

                                    var email = registerEmailField.text;
                                    result = registerEmailField.validateEmail(email);
                                    if (!result.valid) {
                                        registerEmailField.focus_error = true;
                                        registerEmailField.error_text = result.message;
                                        registerStatusMessage.text = result.message;
                                        return;
                                    }

                                    if (!registerEmailCodeField.text || registerEmailCodeField.text.length === 0) {
                                        var error_message = "请输入邮箱验证码";
                                        registerEmailCodeField.focus_error = true;
                                        registerEmailCodeField.error_text = error_message;
                                        registerStatusMessage.text = error_message;
                                        return;
                                    }
                                    var password = registerAccountPasswordField.text;
                                    result = registerAccountPasswordField.validatePassword(password);
                                    if (!result.valid) {
                                        registerAccountPasswordField.focus_error = true;
                                        registerAccountPasswordField.error_text = result.message;
                                        registerStatusMessage.text = result.message;
                                        return;
                                    }

                                    if (password !== registerAccountConfirmPasswordField.text) {
                                        error_message = "两次输入的密码不一致";
                                        registerAccountConfirmPasswordField.focus_error = true;
                                        registerAccountConfirmPasswordField.error_text = error_message;
                                        registerStatusMessage.text = error_message;
                                        return;
                                    }

                                    registerStatusMessage.text = "注册信息校验通过，可接入你的 C++ 网络层";
                                } else {
                                    var phone = registerPhoneField.text;
                                    result = registerPhoneField.validatePhone(phone);
                                    if (!result.valid) {
                                        registerPhoneField.focus_error = true;
                                        registerPhoneField.error_text = result.message;
                                        registerStatusMessage.text = result.message;
                                        return;
                                    }
                                    var phone_code = registerSmsCodeField.text;
                                    if (!phone_code || phone_code.length === 0) {
                                        error_message = "请输入短信验证码";
                                        registerSmsCodeField.focus_error = true;
                                        registerSmsCodeField.error_text = error_message;
                                        registerStatusMessage.text = error_message;
                                        return;
                                    }

                                    password = registerPhonePasswordField.text;
                                    result = registerPhonePasswordField.validatePassword(password);
                                    if (!result.valid) {
                                        registerPhonePasswordField.focus_error = true;
                                        registerPhonePasswordField.error_text = result.message;
                                        registerStatusMessage.text = result.message;
                                        return;
                                    }
                                    if (password !== registerPhoneConfirmPasswordField.text) {
                                        error_message = "两次输入的密码不一致";
                                        registerPhoneConfirmPasswordField.focus_error = true;
                                        registerPhoneConfirmPasswordField.error_text = error_message;
                                        registerStatusMessage.text = error_message;
                                        return;
                                    }
                                    registerStatusMessage.text = "注册信息校验通过，可接入你的 C++ 网络层";
                                }
                            }
                        }

                        Text {
                            id: registerStatusMessage
                            width: parent.width
                            height: 38
                            topPadding: 10
                            color: "#73819A"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Item {
                            width: parent.width
                            height: 46

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    text: "已有账号？"
                                    color: "#73819A"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    text: "返回登录"
                                    color: backLoginMouse.containsMouse ? root.primaryDarkColor : root.primaryColor
                                    font.pixelSize: 13
                                    font.weight: backLoginMouse.containsMouse ? Font.DemiBold : Font.Normal
                                    font.underline: backLoginMouse.containsMouse
                                    verticalAlignment: Text.AlignVCenter

                                    MouseArea {
                                        id: backLoginMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            login_panel_column.registerMode = false;
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }
                                }
                            }
                        }

                        Timer {
                            id: emailCodeTimer
                            interval: 1000
                            repeat: true

                            onTriggered: {
                                if (registerPage.emailCodeCountDown > 0)
                                    registerPage.emailCodeCountDown--;

                                if (registerPage.emailCodeCountDown <= 0)
                                    stop();
                            }
                        }

                        Timer {
                            id: phoneCodeTimer
                            interval: 1000
                            repeat: true

                            onTriggered: {
                                if (registerPage.phoneCodeCountDown > 0)
                                    registerPage.phoneCodeCountDown--;

                                if (registerPage.phoneCodeCountDown <= 0)
                                    stop();
                            }
                        }
                    }
                }
            }
        }
    }
}
