import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

/*
 * FileSync 上传面板
 *
 * 用法：
 * UploadDialog {
 *     id: uploadDialog
 *     manager: uploadManager
 * }
 *
 * 组件负责选择文件、上传队列展示和进度反馈；真正的 HTTP 上传由 C++ UploadManager 完成。
 */
Dialog {
    id: root

    // 注入 C++ UploadManager QObject。
    property var manager: null
    property bool uploadStarted: false
    property bool uploadFinished: false
    property string resultText: ""
    property string resultColor: "#71809B"

    signal filesSelected(int count)

    title: "上传文件"
    modal: true
    focus: true
    width: 570
    height: 590
    padding: 0
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function fileNameFromUrl(fileUrl) {
        var value = fileUrl.toString()
        var slash = value.lastIndexOf("/")
        var name = slash >= 0 ? value.substring(slash + 1) : value
        try {
            name = decodeURIComponent(name)
        } catch (error) {
            // 文件名无法解码时保留 URL 中的原始字符串。
        }
        return name.length > 0 ? name : "未命名文件"
    }

    function extensionOf(fileName) {
        var dot = fileName.lastIndexOf(".")
        return dot >= 0 ? fileName.substring(dot + 1).toUpperCase() : "FILE"
    }

    function addSelectedFiles(urls) {
        if (!urls || urls.length === 0)
            return

        // 上一轮任务完成后，重新选择文件即开始一份新的上传清单。
        if (uploadFinished)
            fileQueue.clear()

        for (var i = 0; i < urls.length; ++i) {
            var url = urls[i]
            var name = fileNameFromUrl(url)
            fileQueue.append({
                fileUrl: url.toString(),
                fileName: name,
                fileExt: extensionOf(name),
                status: "待上传",
                reason: ""
            })
        }

        uploadStarted = false
        uploadFinished = false
        resultText = ""
        filesSelected(fileQueue.count)
    }

    function updateFileStatus(fileName, status, reason) {
        // C++ 信号当前以文件名作为标识；相同文件名时按队列顺序更新。
        for (var i = 0; i < fileQueue.count; ++i) {
            var row = fileQueue.get(i)
            if (row.fileName === fileName
                    && (row.status === "正在上传" || row.status === "排队中" || row.status === "待上传")) {
                fileQueue.setProperty(i, "status", status)
                fileQueue.setProperty(i, "reason", reason || "")
                return
            }
        }
    }

    function markCurrentFile() {
        if (!manager || !manager.currentFile)
            return

        var current = manager.currentFile
        for (var i = 0; i < fileQueue.count; ++i) {
            var row = fileQueue.get(i)
            if (row.fileName === current && row.status === "排队中") {
                fileQueue.setProperty(i, "status", "正在上传")
                return
            }
        }
    }

    function startUpload() {
        if (!manager || manager.uploading || fileQueue.count === 0)
            return

        var localFiles = []
        for (var i = 0; i < fileQueue.count; ++i) {
            localFiles.push(fileQueue.get(i).fileUrl)
            fileQueue.setProperty(i, "status", "排队中")
            fileQueue.setProperty(i, "reason", "")
        }

        uploadStarted = true
        uploadFinished = false
        resultText = "正在准备上传文件…"
        resultColor = "#71809B"
        manager.uploadFiles(localFiles)
        markCurrentFile()
    }

    onOpened: {
        // 上一次任务已经结束时，重新打开弹窗即开始一轮新的选择。
        if (!manager || !manager.uploading) {
            if (uploadFinished) {
                fileQueue.clear()
                uploadStarted = false
                uploadFinished = false
                resultText = ""
            }
        }
    }

    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.width: 1
        border.color: "#E5EAF4"
    }

    header: Item {
        implicitHeight: 76

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 20
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 12
                color: "#EEF2FF"

                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: "#4B6EF5"
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "上传文件"
                    color: "#1E2A45"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Label {
                    text: "将本地文件添加到你的云端空间"
                    color: "#9AA7BA"
                    font.pixelSize: 11
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
            }

            Button {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                hoverEnabled: true
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#F1F4F9" : "transparent"
                }
                contentItem: Text {
                    text: "×"
                    color: "#8D9AB0"
                    font.pixelSize: 21
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.close()
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        // 选择文件区域
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 145
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            radius: 12
            color: "#F8FAFF"
            border.width: 1
            border.color: "#DCE5FA"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 42
                    height: 42
                    radius: 21
                    color: "#EAF0FF"
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        color: "#4B6EF5"
                        font.pixelSize: 25
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    text: "选择需要上传的文件"
                    color: "#35425A"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "支持同时选择多个文件"
                    color: "#9AA7BA"
                    font.pixelSize: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    width: 104
                    height: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                    hoverEnabled: true
                    background: Rectangle {
                        radius: 7
                        color: parent.down ? "#3558DD" : (parent.hovered ? "#5878F7" : "#4B6EF5")
                    }
                    contentItem: Text {
                        text: "选择本地文件"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    enabled: !root.manager || !root.manager.uploading
                    onClicked: filePicker.open()
                }
            }
        }

        // 文件队列
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 145
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            radius: 11
            color: "#FFFFFF"
            border.width: 1
            border.color: "#E9EEF6"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 13
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "上传列表"
                        color: "#35425A"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: fileQueue.count + " 个文件"
                        color: "#A3AEC1"
                        font.pixelSize: 10
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "清空"
                        visible: fileQueue.count > 0 && (!root.manager || !root.manager.uploading)
                        enabled: !root.uploadStarted || root.uploadFinished
                        flat: true
                        font.pixelSize: 10
                        onClicked: {
                            fileQueue.clear()
                            uploadStarted = false
                            uploadFinished = false
                            resultText = ""
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#EFF2F7"
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: fileQueue.count === 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            text: "▤"
                            color: "#C5CEDD"
                            font.pixelSize: 26
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "还没有选择文件"
                            color: "#A5B0C1"
                            font.pixelSize: 11
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                ListView {
                    id: queueListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: fileQueue.count > 0
                    clip: true
                    model: fileQueue
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: queueListView.width
                        height: 53
                        radius: 7
                        color: index % 2 === 0 ? "#FBFCFF" : "#FFFFFF"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 6
                            spacing: 9

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 8
                                color: "#EEF2FF"
                                Text {
                                    anchors.centerIn: parent
                                    text: fileExt.length > 5 ? fileExt.substring(0, 4) : fileExt
                                    color: "#5875D9"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: fileName
                                    color: "#35425A"
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: reason.length > 0 ? reason : status
                                    color: status === "上传成功" ? "#28A879"
                                           : status === "上传失败" ? "#DF7772"
                                           : status === "正在上传" ? "#4B6EF5" : "#9AA7BA"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                text: status === "上传成功" ? "✓"
                                      : status === "上传失败" ? "!"
                                      : status === "正在上传" ? "↑" : ""
                                color: status === "上传成功" ? "#28A879"
                                       : status === "上传失败" ? "#DF7772" : "#4B6EF5"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Button {
                                Layout.preferredWidth: 25
                                Layout.preferredHeight: 25
                                visible: !root.uploadStarted || root.uploadFinished
                                enabled: !root.manager || !root.manager.uploading
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 6
                                    color: parent.hovered ? "#FFF0EF" : "transparent"
                                }
                                contentItem: Text {
                                    text: "×"
                                    color: "#A5B0C1"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: fileQueue.remove(index)
                            }
                        }
                    }
                }
            }
        }

        // 总体进度区域
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: uploadStarted ? 91 : 48
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            radius: 10
            color: uploadFinished ? "#F1FAF6" : "#F7F9FD"
            border.width: 1
            border.color: uploadFinished ? "#E0F2E9" : "#EDF1F7"
            visible: uploadStarted

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: root.resultText.length > 0 ? root.resultText
                              : (root.manager ? root.manager.statusText : "准备上传")
                        color: root.resultColor
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }

                    Label {
                        text: root.manager
                              ? root.manager.completedCount + "/" + root.manager.totalCount
                              : "0/0"
                        color: "#71809B"
                        font.pixelSize: 10
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 7
                    from: 0
                    to: 100
                    value: root.manager ? root.manager.progress : 0
                    visible: !root.uploadFinished

                    background: Rectangle {
                        radius: 4
                        color: "#E4EAF5"
                    }
                    contentItem: Item {
                        Rectangle {
                            width: parent.width * (parent.parent.value / 100)
                            height: parent.height
                            radius: 4
                            color: "#4B6EF5"
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.uploadFinished
                    Label {
                        text: root.manager
                              ? "成功 " + root.manager.successCount + " 个 · 失败 " + root.manager.failedCount + " 个"
                              : "上传已结束"
                        color: "#71809B"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "100%"
                        color: "#28A879"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    footer: Item {
        implicitHeight: 70

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.bottomMargin: 16
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: "文件仅会上传到当前配置的服务器"
                color: "#A3AEC1"
                font.pixelSize: 9
                verticalAlignment: Text.AlignVCenter
            }

            Button {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 36
                text: "取消"
                hoverEnabled: true
                enabled: !root.manager || !root.manager.uploading
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#F3F5F9" : "#FFFFFF"
                    border.color: "#E2E8F2"
                }
                contentItem: Text {
                    text: parent.text
                    color: "#687891"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.close()
            }

            Button {
                Layout.preferredWidth: 112
                Layout.preferredHeight: 36
                text: root.uploadFinished ? "完成并关闭"
                      : (root.manager && root.manager.uploading ? "正在上传…" : "开始上传")
                enabled: root.uploadFinished
                         || (root.manager !== null && !root.uploadStarted
                             && fileQueue.count > 0 && !root.manager.uploading)
                hoverEnabled: true
                background: Rectangle {
                    radius: 8
                    color: !parent.enabled ? "#B9C7F3"
                          : parent.down ? "#3558DD"
                          : parent.hovered ? "#5878F7" : "#4B6EF5"
                }
                contentItem: Text {
                    text: parent.text
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (root.uploadFinished) {
                        root.close()
                    } else {
                        root.startUpload()
                    }
                }
            }
        }
    }

    ListModel {
        id: fileQueue
    }

    FileDialog {
        id: filePicker
        title: "选择要上传的文件"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["所有文件 (*)"]
        acceptLabel: "上传"
        onAccepted: root.addSelectedFiles(selectedFiles)
    }

    Connections {
        target: root.manager
        enabled: root.manager !== null

        function onCurrentFileChanged() {
            root.markCurrentFile()
        }

        function onFileUploaded(fileName, displaySize, modifiedText) {
            root.updateFileStatus(fileName, "上传成功", "")
        }

        function onFileUploadFailed(fileName, reason) {
            if (fileName)
                root.updateFileStatus(fileName, "上传失败", reason)
            else {
                root.resultText = reason
                root.resultColor = "#DF7772"
            }
        }

        function onUploadFinished(successCount, failedCount) {
            root.uploadFinished = true
            root.resultText = "上传任务已完成"
            root.resultColor = failedCount > 0 ? "#D88B45" : "#28A879"

            for (var i = 0; i < fileQueue.count; ++i) {
                var row = fileQueue.get(i)
                if (row.status === "排队中" || row.status === "正在上传")
                    fileQueue.setProperty(i, "status", "上传失败")
            }
        }
    }
}
