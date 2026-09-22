import QtQuick
import QtQuick.Controls

Item {
    id: root



    property string icon: ""
    property string placeholder: ""
    property bool password: false
    property bool password_can_see: false

    // 外部可以正常读取和设置
    property alias text: field.text

    // 是否启用账号格式校验
    property bool validateAccount: false
    enum ValidateWhat {
        None = 0,
        Phone = 0b1,
        Email = 0b10
    }
    property int validateWhat: LoginField.ValidateWhat.None

    // ============================================================
    // 主题色
    // ============================================================

    property color normalBorderColor: "#E5EAF2"
    property color focusBorderColor: window.primary
    property color errorBorderColor: "#E96A6A"

    property color normalBackgroundColor: "#FFFFFF"
    property color errorBackgroundColor: "#FFF7F7"

    property color textColor: "#35425A"
    property color placeholderColor: "#B0B9C8"

    // 文本选中颜色
    property color selectionColor: "#DCE6FF"
    property color selectedTextColor: "#1E2A45"

    // ============================================================
    // 校验状态
    // ============================================================

    readonly property bool hasInput: field.text.length > 0

    readonly property bool accountValid: {
        if (!validateAccount)
            return true

        var value = field.text.trim()

        if (value.length === 0)
            return false

        return isValidAccount(value)
    }

    readonly property bool accountError: {
        return validateAccount &&
               hasInput &&
               !accountValid
    }

    readonly property bool accountSuccess: {
        return validateAccount &&
               hasInput &&
               accountValid
    }

    // ============================================================
    // 邮箱 / 手机号校验
    // ============================================================

    function isValidAccount(value) {
        // 手机号
        var phoneReg = /^1[3-9][0-9]{9}$/

        // 常用邮箱
        var emailReg = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/

        // 不进行任何校验
        if (validateWhat === LoginField.ValidateWhat.None) {
            return true
        }

        var valid = false

        // 需要检查手机号
        if ((validateWhat & LoginField.ValidateWhat.Phone) !== 0) {
            valid = valid || phoneReg.test(value)
        }

        // 需要检查邮箱
        if ((validateWhat & LoginField.ValidateWhat.Email) !== 0) {
            valid = valid || emailReg.test(value)
        }

        return valid
    }
    // ============================================================
    // 外框
    // ============================================================

    Rectangle {
        id: fieldFrame

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: 54

        radius: 10

        // 直接修改外层背景，不再使用铺满整个外框的子 Rectangle，
        // 这样可以保证 border 始终完整显示
        color: root.accountError
               ? root.errorBackgroundColor
               : root.normalBackgroundColor

        border.width: 1

        border.color: {
            // 错误状态优先级最高
            if (root.accountError)
                return root.errorBorderColor

            // 正确输入
            if (root.accountSuccess)
                return root.focusBorderColor

            // 获得焦点
            if (field.activeFocus)
                return root.focusBorderColor

            return root.normalBorderColor
        }

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        // ========================================================
        // 左侧图标
        // ========================================================

        Image {
            id: iconImage

            width: 21
            height: 21

            source:
                "qrc:/qt/qml/FileSync/assets/icon-"
                + root.icon
                + ".svg"

            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter

            opacity: root.accountError ? 0.85 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
        }

        // ========================================================
        // 右侧操作区
        // ========================================================

        Item {
            id: rightActions

            width: {
                var w = 0

                if (statusIcon.visible)
                    w += 20

                if (passwordIcon.visible)
                    w += 20

                if (statusIcon.visible && passwordIcon.visible)
                    w += 8

                return w
            }

            height: 28

            anchors.right: parent.right
            anchors.rightMargin: 13
            anchors.verticalCenter: parent.verticalCenter

            visible: statusIcon.visible || passwordIcon.visible

            // 状态图标
            Text {
                id: statusIcon

                visible: root.validateAccount &&
                         root.hasInput

                width: 20
                height: 24

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                text: root.accountError ? "!" : "✓"

                font.pixelSize: root.accountError ? 13 : 15
                font.bold: true

                color: root.accountError
                       ? root.errorBorderColor
                       : window.primary

                scale: visible ? 1.0 : 0.75
                opacity: visible ? 1.0 : 0.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }

            // 密码查看按钮
            Image {
                id: passwordIcon

                visible: root.password

                width: 19
                height: 19

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                source: root.password_can_see
                        ? "qrc:/qt/qml/FileSyncComponents/assets/eye.svg"
                        : "qrc:/qt/qml/FileSyncComponents/assets/eye-off.svg"

                fillMode: Image.PreserveAspectFit
                opacity: 0.75
            }
        }

        // ========================================================
        // 输入框
        // ========================================================

        TextField {
            id: field

            anchors.left: parent.left
            anchors.leftMargin: 52

            anchors.right: rightActions.visible
                           ? rightActions.left
                           : parent.right

            anchors.rightMargin: rightActions.visible
                                 ? 10
                                 : 18

            anchors.top: parent.top
            anchors.bottom: parent.bottom

            placeholderText: root.placeholder

            echoMode: root.password
                      ? TextInput.Password
                      : TextInput.Normal

            color: root.textColor
            placeholderTextColor: root.placeholderColor

            font.pixelSize: 14

            selectByMouse: true

            selectionColor: root.selectionColor
            selectedTextColor: root.selectedTextColor

            cursorDelegate: Rectangle {
                width: 1.5
                height: 18
                color: window.primary
                visible: field.activeFocus
            }

            background: Item {}

            onTextChanged: {
                if (root.validateAccount) {
                    root.accountValid
                }
            }
        }

    }

    // ============================================================
    // 错误提示
    // ============================================================

    Text {
        id: errorMessage

        visible: root.accountError

        anchors.left: parent.left
        anchors.leftMargin: 4

        anchors.top: fieldFrame.bottom
        anchors.topMargin: 6

        text: {
            if(root.validateWhat & LoginField.ValidateWhat.Email && root.validateWhat & LoginField.ValidateWhat.Phone){
                return "请输入正确的邮箱或手机号"
            }else if(root.validateWhat & LoginField.ValidateWhat.Email){
                return "请输入正确的邮箱"
            }else if( root.validateWhat & LoginField.ValidateWhat.Phone){
                 return "请输入正确的手机号"
            }else{
                return ""
            }
        }
        color: root.errorBorderColor

        font.pixelSize: 12
        font.weight: Font.Normal

        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
    }
}
