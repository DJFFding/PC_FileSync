import QtQuick
import QtQuick.Controls

Item {
    id: root



    property string icon: ""
    property string placeholder: ""
    property bool password: false
    property bool password_can_see: false
    property string error_text: ""
    property bool focus_error: false

    // 外部可以正常读取和设置
    property alias text: field.text

    // 是否启用账号格式校验
    property bool validateAccount: false
    enum ValidateWhat {
        None = 0,
        Phone = 0b1,
        Email = 0b10,
        UserName = 0b100,
        Password = 0b1000,
        EmailCode= 0b10000,
        PhoneCode =0b100000,
        RePassword=0b1000000
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
        return focus_error || (validateAccount &&
               hasInput &&
               !accountValid)
    }

    readonly property bool accountSuccess: {
        return validateAccount &&
               hasInput &&
               accountValid
    }

    // ============================================================
    // 校验
    // ============================================================

    function validateEmail(email){
         if (!email || email.length === 0)
             return {
                 valid: false,
                 message: "请输入邮箱"
             }
        // 常用邮箱
        var emailReg = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return {
            valid:emailReg.test(email),
            message:"请输入正确的邮箱"
         }
    }
    function validatePhone(phone){
        if (!phone || phone.length === 0)
            return {
                valid: false,
                message: "请输入手机号"
            }
        // 手机号
        var phoneReg = /^1[3-9][0-9]{9}$/
        return {
            valid:phoneReg.test(phone),
            message:"请输入正确的手机号"
        }
    }



    function isValidAccount(value) {
        focus_error = false;

        // 不进行任何校验
        if (validateWhat === LoginField.ValidateWhat.None
        ||  validateWhat === LoginField.ValidateWhat.EmailCode
        ||  validateWhat === LoginField.ValidateWhat.PhoneCode
        ||  validateWhat === LoginField.ValidateWhat.RePassword) {
            return true
        }
        else if (validateWhat === LoginField.ValidateWhat.UserName){
            var username = value
            if (!username || username.length === 0) {
                return true
            }
            return root.validateUsername(username).valid;
        }
        else if (validateWhat === LoginField.ValidateWhat.Password){
            var password = value
            if (!password || password.length === 0) {
                return true
            }
            return root.validatePassword(password).valid;
        }

        var valid = false

        // 需要检查手机号
        if ((validateWhat & LoginField.ValidateWhat.Phone) !== 0) {
            valid = valid ||validatePhone(value).valid
        }

        // 需要检查邮箱
        if ((validateWhat & LoginField.ValidateWhat.Email) !== 0) {
            valid = valid || validateEmail(value).valid
        }

        return valid
    }

    function validatePassword(password) {
        // 1. 是否为空
        if (!password || password.length === 0) {
            return {
                valid: false,
                message: "请输入密码"
            }
        }

        // 2. 长度必须在 8~20 位（包含）
        if (password.length < 8 || password.length > 20) {
            return {
                valid: false,
                message: "密码长度必须为 8-20 位"
            }
        }

        // 3. 不允许空格
        if (/\s/.test(password)) {
            return {
                valid: false,
                message: "密码不能包含空格"
            }
        }

        // 4. 至少包含一个字母
        if (!/[A-Za-z]/.test(password)) {
            return {
                valid: false,
                message: "密码至少需要包含一个字母"
            }
        }

        // 5. 至少包含一个数字
        if (!/[0-9]/.test(password)) {
            return {
                valid: false,
                message: "密码至少需要包含一个数字"
            }
        }

        // 6. 拒绝全部由同一个字符组成
        // 例如：aaaaaaaa、11111111、!!!!!!!!
        if (/^(.)\1+$/.test(password)) {
            return {
                valid: false,
                message: "密码不能全部使用相同字符"
            }
        }

        // 7. 拒绝连续重复字符过多
        // 例如：aaaa1234、1111abcd
        if (/(.)\1{3,}/.test(password)) {
            return {
                valid: false,
                message: "密码中不能包含连续重复的 4 个及以上字符"
            }
        }

        // 8. 常见弱密码
        var weakPasswords = [
            "12345678",
            "123456789",
            "1234567890",
            "password",
            "password1",
            "password123",
            "qwerty123",
            "qwertyui",
            "qwertyuiop",
            "abcdefgh",
            "abcdefgh1",
            "abc123456",
            "11111111",
            "00000000",
            "88888888",
            "66666666",
            "87654321"
        ]

        var lowerPassword = password.toLowerCase()

        for (var i = 0; i < weakPasswords.length; ++i) {
            if (lowerPassword === weakPasswords[i]) {
                return {
                    valid: false,
                    message: "该密码过于常见，请更换一个更安全的密码"
                }
            }
        }

        // 9. 拒绝纯数字连续序列
        if (/^(0123456789|1234567890|9876543210|0987654321)$/.test(password)) {
            return {
                valid: false,
                message: "密码不能使用连续数字"
            }
        }

        // 全部通过
        return {
            valid: true,
            message: ""
        }
    }



    // 校验用户名
    // 返回：
    // {
    //     valid: true / false,
    //     message: "错误原因"
    // }

    function validateUsername(username) {
        // 1. 必须填写
        if (!username || username.length === 0) {
            return {
                valid: false,
                message: "请输入用户名"
            }
        }

        // 2. 不允许首尾存在空白
        if (username !== username.trim()) {
            return {
                valid: false,
                message: "用户名首尾不能有空格"
            }
        }

        // 3. 长度限制：3~20 个字符
        if (username.length < 3) {
            return {
                valid: false,
                message: "用户名至少需要 3 个字符"
            }
        }

        if (username.length > 20) {
            return {
                valid: false,
                message: "用户名最多 20 个字符"
            }
        }

        // 4. 只允许：
        // 中文、英文字母、数字、下划线、短横线
        var allowedPattern = /^[\u4e00-\u9fa5A-Za-z0-9_-]+$/

        if (!allowedPattern.test(username)) {
            return {
                valid: false,
                message: "用户名只能包含中文、字母、数字、下划线或短横线"
            }
        }

        // 5. 第一位必须是中文或英文字母
        if (!/^[\u4e00-\u9fa5A-Za-z]/.test(username)) {
            return {
                valid: false,
                message: "用户名必须以中文或英文字母开头"
            }
        }

        // 6. 不能全部是数字
        if (/^[0-9]+$/.test(username)) {
            return {
                valid: false,
                message: "用户名不能全部由数字组成"
            }
        }

        // 7. 不允许连续两个下划线
        if (/__/.test(username)) {
            return {
                valid: false,
                message: "用户名不能包含连续的下划线"
            }
        }

        // 8. 不允许连续两个短横线
        if (/--/.test(username)) {
            return {
                valid: false,
                message: "用户名不能包含连续的短横线"
            }
        }

        // 9. 不能以下划线或短横线结尾
        if (/[_-]$/.test(username)) {
            return {
                valid: false,
                message: "用户名不能以下划线或短横线结尾"
            }
        }

        // 10. 常见保留用户名
        var reservedUsernames = [
            "admin",
            "administrator",
            "root",
            "system",
            "operator",
            "support",
            "service",
            "guest",
            "user",
            "null",
            "undefined",
            "test",
            "demo"
        ]

        var lowerUsername = username.toLowerCase()

        if (reservedUsernames.indexOf(lowerUsername) !== -1) {
            return {
                valid: false,
                message: "该用户名不可使用，请更换其他用户名"
            }
        }

        // 11. 校验通过
        return {
            valid: true,
            message: ""
        }
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
                var email = root.text
                var result = root.validateEmail(email)
                return result.message
            }else if(root.validateWhat & LoginField.ValidateWhat.Phone){
                var phone = root.text
                result = root.validatePhone(phone)
                return result.message
            }else if(root.validateWhat === LoginField.ValidateWhat.UserName){
                var username = root.text
                result = root.validateUsername(username)
                return result.message
            }else if(root.validateWhat === LoginField.ValidateWhat.Password){
                var password = root.text
                result = root.validatePassword(password)
                return result.message
            }else{
                return error_text
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
