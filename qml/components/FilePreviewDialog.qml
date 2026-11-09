import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

/*
 * 覆盖 Main.qml 整个窗口的全屏文件预览。
 * supported: 图片、分块文本、PDF、DOCX（转换为 PDF 后保留版面预览）。
 * 不支持的二进制类型由 openPreview() 直接忽略。
 */
Dialog {
    id: dialog

    required property var manager

    // 与登录页面、文件工作台保持一致的主题色
    property color primaryColor: "#4B6EF5"
    property color primaryDarkColor: "#3558DD"
    property color textDarkColor: "#1E2A45"
    property color textMidColor: "#71809B"
    property color textLightColor: "#A9B5C9"
    property color panelColor: "#FFFFFF"
    property color pageColor: "#F7F9FD"
    property color lineColor: "#E8EDF6"

    property string fileName: ""
    property string filePath: ""
    property string sourceUrl: ""
    property string previewKind: ""
    readonly property bool pagedDocument: previewKind === "pdf"
                                          || previewKind === "docx"

    property string imageSource: ""
    property real imageScale: 1.0
    readonly property real imageMinScale: 0.1
    readonly property real imageMaxScale: 8.0
    property string pdfSource: ""
    property int pdfPageCount: 0
    property int pdfCurrentPage: 0
    property int pdfRenderWidth: 1280
    property string documentError: ""
    property bool documentLoading: false
    property int documentRequestId: 0

    readonly property int textChunkSize: 65536
    property string textContent: ""
    property string textLoadError: ""
    property bool textLoading: false
    property bool textLoadedOnce: false
    property bool textHasMore: false
    property double textOffset: 0
    property double textTotalBytes: 0
    property int textSession: 0
    property var activeTextRequest: null

    // file/qrc 地址不能通过本地 HTTP 分块，因此先读取，再按同样节奏逐步显示。
    property bool localTextLoaded: false
    property string localFullText: ""
    property int localCharacterOffset: 0

    property bool copyAllLoading: false
    property var activeCopyRequest: null
    property string copyMessage: ""
    property bool copySucceeded: false

    parent: Overlay.overlay
    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
        color: dialog.pageColor
    }

    component DarkToolbarButton: Button {
        height: 32
        hoverEnabled: true
        background: Rectangle {
            radius: 6
            color: !parent.enabled ? "#EDF1F6"
                   : parent.down ? "#E1E8FA"
                   : parent.hovered ? "#E8EEFF" : "#F0F4FF"
            border.color: "#DCE5F5"
        }
        contentItem: Text {
            text: parent.text
            color: parent.enabled ? dialog.primaryColor : "#A7B2C2"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    function normalizedExtension(extension, name) {
        var value = extension === undefined || extension === null
                ? "" : extension.toString().toLowerCase()
        if (value.length > 0 && value.charAt(0) === ".")
            value = value.substring(1)
        if (value.length === 0 || value === "file") {
            var dot = name.lastIndexOf(".")
            value = dot >= 0 ? name.substring(dot + 1).toLowerCase() : ""
        }
        return value
    }

    function detectPreviewKind(extension, name, serverType, mimeType) {
        var ext = normalizedExtension(extension, name)
        var server = serverType === undefined || serverType === null
                ? "" : serverType.toString().toLowerCase()
        var mime = mimeType === undefined || mimeType === null
                ? "" : mimeType.toString().toLowerCase()

        if (server === "image")
            return "image"
        if (server === "text")
            return "text"
        if (ext === "pdf" || mime === "application/pdf")
            return "pdf"
        if (ext === "docx"
                || mime === "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
            return "docx"

        var imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp",
                               "svg", "ico", "tif", "tiff"]
        if (imageExtensions.indexOf(ext) !== -1 || mime.indexOf("image/") === 0)
            return "image"

        var textExtensions = ["txt", "md", "markdown", "log", "json", "xml",
                              "yaml", "yml", "toml", "csv", "tsv", "ini", "cfg",
                              "conf", "properties", "html", "htm", "css", "js",
                              "ts", "qml", "c", "h", "cpp", "hpp", "cc", "cxx",
                              "java", "py", "sh", "bat", "sql", "vue", "php",
                              "rb", "go", "rs", "tex", "diff", "patch", "srt"]
        if (textExtensions.indexOf(ext) !== -1 || mime.indexOf("text/") === 0)
            return "text"

        return ""
    }

    function isRemote(url) {
        return url.indexOf("http://") === 0 || url.indexOf("https://") === 0
    }

    function abortWork() {
        textSession += 1

        if (activeTextRequest) {
            activeTextRequest.onreadystatechange = null
            activeTextRequest.abort()
            activeTextRequest = null
        }
        if (activeCopyRequest) {
            activeCopyRequest.onreadystatechange = null
            activeCopyRequest.abort()
            activeCopyRequest = null
        }

        textLoading = false
        copyAllLoading = false
        if (manager)
            manager.cancelDocumentPreparation()
    }

    function openPreview(name, path, serverType, extension, mimeType) {
        var kind = detectPreviewKind(extension, name, serverType, mimeType)
        if (kind.length === 0)
            return false

        abortWork()

        fileName = name
        filePath = path
        previewKind = kind
        sourceUrl = manager.fileContentUrl(path)

        imageSource = ""
        imageScale = 1.0
        pdfSource = ""
        pdfPageCount = 0
        pdfCurrentPage = 0
        pdfRenderWidth = 1280
        documentError = ""
        documentLoading = false
        documentRequestId = 0

        textContent = ""
        textLoadError = ""
        textLoadedOnce = false
        textHasMore = kind === "text"
        textOffset = 0
        textTotalBytes = 0
        localTextLoaded = false
        localFullText = ""
        localCharacterOffset = 0
        copyMessage = ""
        copySucceeded = false

        open()

        if (kind === "image") {
            imageSource = sourceUrl
        } else if (kind === "text") {
            Qt.callLater(loadNextTextChunk)
        } else {
            documentLoading = true
            documentRequestId = manager.prepareDocument(path, kind)
        }
        return true
    }

    function formatBytes(value) {
        if (value < 1024)
            return Math.round(value) + " B"
        if (value < 1024 * 1024)
            return (value / 1024).toFixed(1) + " KB"
        if (value < 1024 * 1024 * 1024)
            return (value / (1024 * 1024)).toFixed(1) + " MB"
        return (value / (1024 * 1024 * 1024)).toFixed(2) + " GB"
    }

    function statusLine() {
        if (copyMessage.length > 0)
            return copyMessage
        if (previewKind === "image") {
            if (imageView.status === Image.Error)
                return "图片加载失败"
            if (imageView.status === Image.Loading)
                return "正在加载原始图片…"
            if (imageView.status === Image.Ready)
                return imageView.implicitWidth + " × " + imageView.implicitHeight
                       + "，显示比例 " + Math.round(imageScale * 100) + "%（滚轮缩放）"
            return "暂无图片地址"
        }
        if (previewKind === "text") {
            if (textLoadError.length > 0)
                return textLoadError
            if (copyAllLoading)
                return "正在读取完整文件并复制…"
            if (!textLoadedOnce && textLoading)
                return "正在加载文本…"
            if (textHasMore) {
                var loaded = isRemote(sourceUrl) ? textOffset : localCharacterOffset
                var totalText = isRemote(sourceUrl) && textTotalBytes > 0
                        ? " / " + formatBytes(textTotalBytes) : ""
                return "已加载 " + formatBytes(loaded) + totalText
                       + "，滚动到底部继续加载"
            }
            return textLoadedOnce ? "已加载全部文本" : "准备加载文本"
        }
        if (pagedDocument) {
            if (documentError.length > 0)
                return documentError
            if (pdfPageCount > 0) {
                var converted = previewKind === "docx" ? "DOCX 已转换为 PDF，" : ""
                return converted + "第 " + (pdfCurrentPage + 1) + " 页，共 "
                       + pdfPageCount + " 页，MuPDF 按需渲染"
            }
            return previewKind === "docx"
                   ? "正在下载 DOCX 并转换为 PDF（还原排版和嵌入图片）…"
                   : "正在下载并解析 PDF…"
        }
        return ""
    }

    function showCopyMessage(message, succeeded) {
        copyMessage = message
        copySucceeded = succeeded === true
        copyFeedbackTimer.restart()
    }

    function activeEditor() {
        return textEditor
    }

    function copySelectedText() {
        var editor = activeEditor()
        var selected = editor.selectedText
        if (selected.length === 0) {
            showCopyMessage("请先用鼠标或键盘选择要复制的文本")
            return
        }
        manager.copyTextToClipboard(selected)
        showCopyMessage("已复制选中的 " + selected.length + " 个字符", true)
    }

    function copyTextPreview() {
        if (previewKind !== "text")
            return

        if (activeEditor().selectedText.length > 0) {
            // 按钮不夺取焦点，复制后保留用户原有选区。
            copySelectedText()
        } else {
            // 没有选区时复制全部；分块文本仍会另取完整文件。
            copyAllText()
        }
    }

    function copyAllText() {
        if (previewKind !== "text" || copyAllLoading)
            return

        if (localTextLoaded) {
            manager.copyTextToClipboard(localFullText)
            showCopyMessage("已复制全部文本", true)
            return
        }
        if (textLoadedOnce && !textHasMore && !textLoading) {
            manager.copyTextToClipboard(textContent)
            showCopyMessage("已复制全部文本", true)
            return
        }
        if (sourceUrl.length === 0) {
            showCopyMessage("暂无文本文件地址")
            return
        }

        // 已加载内容可能只是文件前一部分；复制全部必须另取完整文件。
        copyAllLoading = true
        copyMessage = ""
        var session = textSession
        var remote = isRemote(sourceUrl)
        var request = new XMLHttpRequest()
        activeCopyRequest = request

        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || session !== textSession)
                return

            activeCopyRequest = null
            copyAllLoading = false
            var succeeded = (request.status >= 200 && request.status < 300)
                            || (request.status === 0 && !remote)
            if (succeeded) {
                manager.copyTextToClipboard(request.responseText === undefined
                                            ? "" : request.responseText)
                showCopyMessage("已复制全部文本", true)
            } else {
                showCopyMessage(request.status > 0
                                ? "复制全部失败（HTTP " + request.status + "）"
                                : "复制全部失败，请检查网络或文件地址")
            }
        }
        request.open("GET", sourceUrl, true)
        request.send()
    }

    function appendLocalTextChunk() {
        if (!localTextLoaded)
            return
        var chunk = localFullText.substr(localCharacterOffset, textChunkSize)
        localCharacterOffset += chunk.length
        textContent += chunk
        textLoadedOnce = true
        textHasMore = localCharacterOffset < localFullText.length
    }

    function loadNextTextChunk() {
        if (previewKind !== "text" || textLoading || copyAllLoading)
            return
        if (textLoadedOnce && !textHasMore)
            return

        if (!isRemote(sourceUrl) && localTextLoaded) {
            appendLocalTextChunk()
            return
        }
        if (sourceUrl.length === 0) {
            textLoadError = "暂无文本文件地址"
            textHasMore = false
            return
        }

        textLoading = true
        textLoadError = ""
        var session = textSession
        var remote = isRemote(sourceUrl)
        var requestedOffset = textOffset
        var requestUrl = remote
                ? manager.textChunkUrl(filePath, requestedOffset, textChunkSize)
                : sourceUrl
        var request = new XMLHttpRequest()
        activeTextRequest = request

        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || session !== textSession)
                return

            activeTextRequest = null
            textLoading = false
            var succeeded = (request.status >= 200 && request.status < 300)
                            || (request.status === 0 && !remote)
            if (!succeeded) {
                textLoadError = request.status > 0
                        ? "文本加载失败（HTTP " + request.status + "）"
                        : "文本加载失败，请检查网络或文件地址"
                return
            }

            var response = request.responseText === undefined ? "" : request.responseText
            if (!remote) {
                localFullText = response
                localTextLoaded = true
                localCharacterOffset = 0
                textContent = ""
                appendLocalTextChunk()
                return
            }

            var truncated = false
            var nextOffset = NaN
            var totalSize = NaN
            try {
                truncated = request.getResponseHeader("X-Preview-Truncated") === "1"
                nextOffset = Number(request.getResponseHeader("X-Preview-Next-Offset"))
                totalSize = Number(request.getResponseHeader("X-Preview-Total-Size"))
            } catch (error) {
                truncated = false
            }

            var hasNextOffset = isFinite(nextOffset) && nextOffset >= 0
            if (truncated && (!hasNextOffset || nextOffset <= requestedOffset)) {
                textLoadError = "服务器未返回有效的下一分块位置，已停止加载"
                textHasMore = true
                return
            }

            textContent += response
            textLoadedOnce = true
            if (hasNextOffset)
                textOffset = nextOffset
            if (isFinite(totalSize) && totalSize >= 0)
                textTotalBytes = totalSize
            textHasMore = truncated
        }

        request.open("GET", requestUrl, true)
        request.send()
    }

    function maybeLoadNextTextChunk() {
        if (previewKind !== "text" || !textHasMore || textLoading
                || textLoadError.length > 0)
            return
        if (textFlick.contentY + textFlick.height >= textFlick.contentHeight - 240)
            loadNextTextChunk()
    }

    function fitPdfWidth() {
        if (!pagedDocument || pdfView.width <= 0)
            return

        // 按设备像素比渲染，保证高分屏文字清晰；按 256 像素分桶，避免缩放窗口时频繁重渲染。
        var screenRatio = viewport.Screen.devicePixelRatio
        var ratio = screenRatio > 0 ? screenRatio : 1
        var logicalWidth = Math.max(256, pdfView.width - 28)
        var pixels = Math.ceil(logicalWidth * ratio / 256) * 256
        pdfRenderWidth = Math.max(512, Math.min(4096, pixels))
    }

    function pdfPageUrl(pageIndex) {
        if (pdfSource.length === 0 || pageIndex < 0 || pageIndex >= pdfPageCount)
            return ""
        return "image://mupdf/render?source=" + encodeURIComponent(pdfSource)
               + "&page=" + pageIndex + "&width=" + pdfRenderWidth
               + "&request=" + documentRequestId
    }

    function updatePdfCurrentPage() {
        if (!pagedDocument || pdfPageCount <= 0 || pdfView.count <= 0) {
            pdfCurrentPage = 0
            return
        }

        var y = pdfView.contentY + pdfView.height / 2
        var index = pdfView.indexAt(pdfView.width / 2, y)
        if (index < 0)
            index = pdfView.indexAt(pdfView.width / 2, pdfView.contentY + 2)
        if (index >= 0)
            pdfCurrentPage = Math.max(0, Math.min(pdfPageCount - 1, index))
    }

    onClosed: {
        abortWork()
        imageSource = ""
        imageScale = 1.0
        pdfSource = ""
        pdfPageCount = 0
        pdfCurrentPage = 0
        pdfRenderWidth = 1280
        previewKind = ""
    }

    Connections {
        target: dialog.manager

        function onPdfPreviewReady(requestId, localUrl, pageCount) {
            if (!dialog.pagedDocument || requestId !== dialog.documentRequestId)
                return
            dialog.documentError = ""
            dialog.pdfSource = localUrl
            dialog.fitPdfWidth()
            dialog.pdfPageCount = pageCount
            dialog.pdfCurrentPage = 0
            dialog.documentLoading = false
            Qt.callLater(dialog.updatePdfCurrentPage)
        }

        function onDocumentPreviewFailed(requestId, reason) {
            if (!dialog.pagedDocument || requestId !== dialog.documentRequestId)
                return
            dialog.documentLoading = false
            dialog.documentError = reason
        }
    }

    Timer {
        id: copyFeedbackTimer
        interval: 1500
        repeat: false
        onTriggered: {
            dialog.copyMessage = ""
            dialog.copySucceeded = false
        }
    }

    Timer {
        id: pdfFitTimer
        interval: 140
        repeat: false
        onTriggered: dialog.fitPdfWidth()
    }

    contentItem: Item {
        implicitWidth: 0
        implicitHeight: 0

        Rectangle {
            anchors.fill: parent
            color: dialog.pageColor
        }

        Rectangle {
            id: toolbar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 56
            color: dialog.panelColor
            border.color: dialog.lineColor
            z: 20

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 12
                spacing: 10

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: dialog.fileName
                        color: dialog.textDarkColor
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                    }
                    Text {
                        width: parent.width
                        text: dialog.statusLine()
                        color: dialog.textMidColor
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                DarkToolbarButton {
                    visible: dialog.previewKind === "text"
                    width: 76
                    focusPolicy: Qt.NoFocus
                    text: dialog.copyAllLoading ? "复制中…"
                                                : (dialog.copySucceeded ? "已复制" : "复制")
                    ToolTip.visible: hovered
                    ToolTip.text: "复制选中文本；未选择时复制全部"
                    enabled: !dialog.copyAllLoading && dialog.sourceUrl.length > 0
                    onClicked: dialog.copyTextPreview()
                }
                DarkToolbarButton {
                    width: 40
                    text: "×"
                    onClicked: dialog.close()
                    ToolTip.visible: hovered
                    ToolTip.text: "关闭（Esc）"
                }
            }
        }

        Item {
            id: viewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom
            clip: true

            WheelHandler {
                target: viewport
                enabled: dialog.previewKind === "image"
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: function(event) {
                    if (event.angleDelta.y === 0)
                        return

                    var factor = event.angleDelta.y > 0 ? 1.1 : 1 / 1.1
                    dialog.imageScale = Math.max(dialog.imageMinScale,
                            Math.min(dialog.imageMaxScale, dialog.imageScale * factor))
                    event.accepted = true
                }
            }

            // 原始分辨率加载，不设置 sourceSize；PreserveAspectFit 保证宽或高铺满，
            // 另一方向留下的区域由页面背景色填充，不裁切、不拉伸。
            Image {
                id: imageView
                anchors.fill: parent
                visible: dialog.previewKind === "image"
                source: dialog.imageSource
                scale: dialog.imageScale
                transformOrigin: Item.Center
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignVCenter
                asynchronous: true
                autoTransform: true
                cache: true
                smooth: true
                mipmap: true
            }

            BusyIndicator {
                anchors.centerIn: parent
                visible: dialog.previewKind === "image" && imageView.status === Image.Loading
                running: visible
            }
            Text {
                anchors.centerIn: parent
                visible: dialog.previewKind === "image"
                         && (imageView.status === Image.Error || dialog.imageSource.length === 0)
                text: dialog.imageSource.length === 0 ? "暂无图片地址" : "图片加载失败"
                color: dialog.textMidColor
                font.pixelSize: 14
            }

            Flickable {
                id: textFlick
                anchors.fill: parent
                anchors.margins: 22
                visible: dialog.previewKind === "text"
                clip: true
                contentWidth: width
                contentHeight: textEditor.contentHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                onContentYChanged: dialog.maybeLoadNextTextChunk()
                onContentHeightChanged: dialog.maybeLoadNextTextChunk()
                onHeightChanged: dialog.maybeLoadNextTextChunk()

                TextEdit {
                    id: textEditor
                    width: textFlick.width
                    height: contentHeight
                    text: dialog.textContent
                    readOnly: true
                    selectByMouse: true
                    selectByKeyboard: true
                    persistentSelection: true
                    cursorVisible: false
                    color: "#4C5C74"
                    selectionColor: dialog.primaryColor
                    selectedTextColor: dialog.panelColor
                    font.family: "monospace"
                    font.pixelSize: 14
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    textFormat: TextEdit.PlainText
                    // 阻止 TextEdit 提前执行默认的 Ctrl+C，
                    // 让下面的 Keys.onPressed 统一处理。
                    Keys.onShortcutOverride: function(event) {
                        if (event.key === Qt.Key_C
                                && (event.modifiers & Qt.ControlModifier)) {
                            event.accepted = true
                        }
                    }

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_C
                                && (event.modifiers & Qt.ControlModifier)) {
                            if (!event.isAutoRepeat)
                                dialog.copyTextPreview()

                            // 阻止事件继续传递，避免重复复制。
                            event.accepted = true
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    parent: textFlick.parent
                    anchors.top: textFlick.top
                    anchors.right: parent.right
                    anchors.bottom: textFlick.bottom
                    policy: ScrollBar.AsNeeded
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                visible: dialog.previewKind === "text" && dialog.textLoading
                         && !dialog.textLoadedOnce
                running: visible
            }
            Text {
                anchors.centerIn: parent
                visible: dialog.previewKind === "text" && dialog.textLoadedOnce
                         && dialog.textContent.length === 0 && dialog.textLoadError.length === 0
                text: "文本内容为空"
                color: dialog.textMidColor
                font.pixelSize: 14
            }
            DarkToolbarButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 22
                visible: dialog.previewKind === "text" && dialog.textLoadError.length > 0
                width: 90
                text: "重试加载"
                onClicked: dialog.loadNextTextChunk()
            }

            ListView {
                id: pdfView
                anchors.fill: parent
                visible: dialog.pagedDocument && dialog.pdfSource.length > 0
                         && dialog.pdfPageCount > 0 && dialog.documentError.length === 0
                clip: true
                model: dialog.pdfPageCount
                spacing: 14
                cacheBuffer: Math.max(600, height)
                boundsBehavior: Flickable.StopAtBounds

                onWidthChanged: {
                    pdfFitTimer.restart()
                    dialog.updatePdfCurrentPage()
                }
                onHeightChanged: dialog.updatePdfCurrentPage()
                onContentYChanged: dialog.updatePdfCurrentPage()
                onCountChanged: Qt.callLater(dialog.updatePdfCurrentPage)

                delegate: Rectangle {
                    id: pdfPageDelegate
                    x: 14
                    width: ListView.view ? Math.max(1, ListView.view.width - 28) : 1
                    height: Math.max(80, pageImage.height)
                    color: dialog.panelColor

                    Image {
                        id: pageImage
                        width: parent.width
                        height: implicitWidth > 0 && implicitHeight > 0
                                ? width * implicitHeight / implicitWidth
                                : width * 1.4142
                        source: dialog.pdfPageUrl(index)
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter

                        onStatusChanged: {
                            if (status === Image.Ready)
                                Qt.callLater(dialog.updatePdfCurrentPage)
                        }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        visible: pageImage.status === Image.Loading
                        running: visible
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 32
                        visible: pageImage.status === Image.Error
                        text: "第 " + (index + 1) + " 页渲染失败"
                        color: "#C77B76"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                visible: dialog.pagedDocument && dialog.documentLoading
                         && dialog.documentError.length === 0
                running: visible
            }
            Text {
                anchors.centerIn: parent
                width: Math.min(560, parent.width - 48)
                visible: dialog.pagedDocument && dialog.documentError.length > 0
                text: dialog.documentError
                color: "#C77B76"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
