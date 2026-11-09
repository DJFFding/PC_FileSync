import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import FileSyncComponents 1.0

/*
 * FileSync - 文件工作台
 *
 * 用法：
 *   FileManagerPage { anchors.fill: parent }
 *
 * 文件列表使用本地 ListModel；上传、列表和预览通过 C++ UploadManager 接入 HTTP 服务。
 * 服务器文件变化通过 WebSocket 主动推送，客户端自动刷新当前目录并在断线后重连。
 * 行菜单的打开、下载、重命名、移动、收藏和删除由 UploadManager 完成；分享、刷新和立即同步仍通过 signals 暴露给业务层。
 * 删除文件或文件夹时由服务器将整个项目移入回收站，文件夹的全部后代和空目录都会保留。
 * 回收站条目保留 30 天；还原、彻底删除和清空均由 UploadManager 调用服务器完成。
 * 收藏文件夹时由服务器递归登记其全部后代，收藏页展示真实持久化数据。
 */
Item {
    id: root
    objectName: "fileManagerPage"

    // 非最大化时的圆角
    property real cornerRadius: 14
    // 当前窗口是否最大化
    property bool maximized: false

    // 可由 C++ 设置为 QAbstractListModel；模型角色需包含 name/kind/ext/modified/size/status/iconBg/iconColor。
    // 文件预览使用 path；服务端还可提供 previewType（image/text/binary）和 mimeType。
    property var fileModelSource: fileModel

    // 图片高度按原始尺寸和宽高比计算；该值仅限制极端长图，不会裁切或拉伸图片。
    property real maxImagePreviewHeight: 720
    property int textPreviewByteLimit: 65536

    // 与登录页面保持一致的主题色
    property color primaryColor: "#4B6EF5"
    property color primaryDarkColor: "#3558DD"
    property color textDarkColor: "#1E2A45"
    property color textMidColor: "#71809B"
    property color textLightColor: "#A9B5C9"
    property color panelColor: "#FFFFFF"
    property color pageColor: "#F7F9FD"
    property color lineColor: "#E8EDF6"
    property color successColor: "#28B985"
    property color warningColor: "#F2A64A"

    property string currentNav: "我的文件"
    property string currentFilter: "全部"
    property string searchKeyword: ""
    // 收藏夹使用独立的筛选条件，避免影响“我的文件”的列表状态。
    property string favoriteFilter: "全部"
    property string favoriteSearchKeyword: ""
    // 默认使用 UploadManager 返回的真实收藏模型，也可由 C++ 替换为兼容模型。
    property var favoritesModelSource: favoritesModel
    // 最近使用使用独立的真实数据模型；动态角色另含 recentTime/lastAccessed/recentAction/accessCount。
    property var recentModelSource: recentModel
    property string recentFilter: "全部"
    property string recentSearchKeyword: ""
    property string recentError: ""
    property string selectedRecentPath: ""
    property int recentVisibleCount: 0
    property bool recentLoading: uploadManager.loadingRecent || uploadManager.updatingRecent
    // 回收站使用独立状态和数据源，避免污染“我的文件”和“收藏夹”。
    // 模型角色：name/kind/ext/size/iconBg/iconColor/path，另可提供 location/deletedTime。
    property var trashModelSource: trashModel
    property string trashFilter: "全部"
    property string trashSearchKeyword: ""
    property bool trashLoading: uploadManager.loadingTrash || uploadManager.updatingTrash
    property int trashRetentionDays: 30
    property string selectedTrashPath: ""
    property bool detailsVisible: true
    property string selectedName: ""
    property string selectedPath: ""
    property string selectedKind: ""
    property string selectedModified: ""
    property string selectedSize: ""
    property string selectedStatus: ""
    property string selectedExt: ""
    property string pendingCreatedFolderName: ""
    property string pendingCreatedFolderPath: ""
    property string pendingRenamedPath: ""
    property bool refreshAfterCurrentFileLoad: false
    property var breadcrumbItems: root.makeBreadcrumbs(uploadManager.currentPath)
    property string currentLocationText: uploadManager.currentPath.length === 0
                                        ? "我的文件" : "我的文件 / " + uploadManager.currentPath

    // 供 C++ 业务层连接的接口
    signal uploadRequested()
    signal createFolderRequested(string folderName)
    signal downloadRequested(string fileName)
    signal shareRequested(string fileName)
    signal deleteRequested(string fileName)
    signal openFileRequested(string fileName)
    signal previewRequested(string fileName, string filePath, string previewType,
                            string extension, string mimeType)
    signal refreshRequested()
    signal syncNowRequested()
    signal navigationChanged(string navigation)
    signal fileSelected(string fileName, string fileKind)
    signal favoriteRemovalRequested(string fileName, string filePath)
    signal recentRefreshRequested()
    signal recentRemovalRequested(string fileName, string filePath)
    signal recentClearRequested()
    // 回收站刷新、还原、彻底删除和清空均由 UploadManager 完成。
    signal trashRefreshRequested()
    signal trashRestoreRequested(string fileName, string filePath)
    signal trashPermanentDeleteRequested(string fileName, string filePath)
    signal trashEmptyRequested()

    // 两个上传按钮共用独立的上传面板；新建文件夹沿用同样的异步请求模式。
    onUploadRequested: uploadDialog.open()
    onPreviewRequested: uploadManager.recordRecent(filePath, "preview")
    onCreateFolderRequested: uploadManager.createFolder(folderName)
    onRefreshRequested: uploadManager.loadFiles()
    onDeleteRequested: root.requestDelete(root.selectedPath, fileName, root.selectedKind)
    onFavoriteRemovalRequested:(fileName,filePath)=>uploadManager.removeFavorite(filePath)
    onRecentRefreshRequested: {
        root.recentError = ""
        uploadManager.loadRecent()
    }
    onRecentRemovalRequested: {
        if (!uploadManager.updatingRecent)
            uploadManager.removeRecent(filePath)
    }
    onRecentClearRequested: {
        if (!uploadManager.updatingRecent)
            uploadManager.clearRecent()
    }
    onTrashRefreshRequested: uploadManager.loadTrash()
    onTrashRestoreRequested: {
        if (!uploadManager.updatingTrash)
            uploadManager.restoreTrashItem(filePath)
    }
    onTrashPermanentDeleteRequested: {
        if (!uploadManager.updatingTrash)
            uploadManager.permanentlyDeleteTrashItem(filePath)
    }
    onTrashEmptyRequested: {
        if (!uploadManager.updatingTrash)
            uploadManager.emptyTrash()
    }
    onRecentFilterChanged: updateRecentVisibleCount()
    onRecentSearchKeywordChanged: updateRecentVisibleCount()

    onCurrentNavChanged: {
        if (currentNav === "收藏夹")
            uploadManager.loadFavorites()
        else if (currentNav === "最近使用")
            recentRefreshRequested()
        else if (currentNav === "回收站")
            trashRefreshRequested()
    }

    function makeBreadcrumbs(path) {
        var items = [{ name: "我的文件", path: "" }]
        if (path === undefined || path === null || path.length === 0)
            return items

        var parts = path.split("/")
        var currentPath = ""
        for (var i = 0; i < parts.length; ++i) {
            if (parts[i].length === 0)
                continue
            currentPath = currentPath.length === 0 ? parts[i] : currentPath + "/" + parts[i]
            items.push({ name: parts[i], path: currentPath })
        }
        return items
    }

    function openFolder(path) {
        uploadManager.openFolder(path === undefined || path === null ? "" : path.toString())
    }

    // 自定义模型未提供 path 时，按当前云端目录和文件名构造相对路径。
    function cloudItemPath(path, name) {
        if (path !== undefined && path !== null && path.toString().length > 0)
            return path.toString()
        var itemName = name === undefined || name === null ? "" : name.toString()
        return uploadManager.currentPath.length > 0
               ? uploadManager.currentPath + "/" + itemName : itemName
    }

    function requestDelete(path, name, kind) {
        var sourcePath = cloudItemPath(path, name)
        if (sourcePath.length === 0 || uploadManager.deleting)
            return
        deleteConfirmDialog.openFor(sourcePath, name, kind)
    }

    function requestDownload(path, kind) {
        var sourcePath = path === undefined || path === null ? "" : path.toString()
        if (sourcePath.length === 0 || uploadManager.downloading)
            return

        if (kind === "folder") {
            downloadFolderDialog.cloudPath = sourcePath
            downloadFolderDialog.open()
            return
        }

        downloadFileDialog.cloudPath = sourcePath
        downloadFileDialog.currentFile = uploadManager.defaultDownloadUrl(sourcePath)
        downloadFileDialog.open()
    }

    function showDownloadResult(succeeded, isFolder, localPath, reason) {
        downloadResultDialog.showResult(succeeded, isFolder, localPath, reason)
    }

    function clearSelection() {
        selectedName = ""
        selectedPath = ""
        selectedKind = ""
        selectedModified = ""
        selectedSize = ""
        selectedStatus = ""
        selectedExt = ""
        selectedTrashPath = ""
        selectedRecentPath = ""
    }

    function selectFile(name, kind, modified, size, status, ext, path) {
        selectedName = name
        selectedPath = cloudItemPath(path, name)
        selectedKind = kind
        selectedModified = modified
        selectedSize = size
        selectedStatus = status
        selectedExt = ext
        fileSelected(name, kind)
    }

    function matchesFilter(kind) {
        if (currentFilter === "文件")
            return kind !== "folder"
        if (currentFilter === "文件夹")
            return kind === "folder"
        return true
    }

    function matchesSearch(name) {
        return searchKeyword.length === 0 || name.toLowerCase().indexOf(searchKeyword.toLowerCase()) !== -1
    }

    function matchesFavoriteFilter(kind) {
        if (favoriteFilter === "文件")
            return kind !== "folder"
        if (favoriteFilter === "文件夹")
            return kind === "folder"
        return true
    }

    function matchesFavoriteSearch(name) {
        return favoriteSearchKeyword.length === 0
               || name.toLowerCase().indexOf(favoriteSearchKeyword.toLowerCase()) !== -1
    }


    function matchesRecentFilter(kind) {
        if (recentFilter === "文件")
            return kind !== "folder"
        if (recentFilter === "文件夹")
            return kind === "folder"
        return true
    }

    function matchesRecentSearch(name) {
        return recentSearchKeyword.length === 0
               || name.toLowerCase().indexOf(recentSearchKeyword.toLowerCase()) !== -1
    }

    function setRecentItems(items) {
        recentModel.clear()
        if (items !== undefined && items !== null) {
            for (var i = 0; i < items.length; ++i)
                recentModel.append(items[i])
        }
        Qt.callLater(updateRecentVisibleCount)
    }

    function updateRecentVisibleCount() {
        if (recentModelSource !== recentModel) {
            recentVisibleCount = recentPage.itemCount
            return
        }
        var visibleCount = 0
        for (var i = 0; i < recentModel.count; ++i) {
            var item = recentModel.get(i)
            if (matchesRecentFilter(item.kind) && matchesRecentSearch(item.name))
                ++visibleCount
        }
        recentVisibleCount = visibleCount
    }

    function recentActionText(action, kind, count) {
        var text = action === "preview" ? "最近预览"
                 : action === "download" ? "最近下载"
                 : kind === "folder" ? "最近进入" : "最近打开"
        return count > 1 ? text + " · 使用 " + count + " 次" : text
    }

    function formatRecentTime(isoTime, fallbackTime, modifiedTime) {
        var fallback = fallbackTime !== undefined && fallbackTime !== null
                       && fallbackTime.toString().length > 0
                       ? fallbackTime.toString()
                       : (modifiedTime === undefined || modifiedTime === null
                          ? "未知" : modifiedTime.toString())
        if (isoTime === undefined || isoTime === null || isoTime.toString().length === 0)
            return fallback
        var date = new Date(isoTime.toString())
        if (isNaN(date.getTime()))
            return fallback

        function pad(value) { return value < 10 ? "0" + value : value.toString() }
        var timeText = pad(date.getHours()) + ":" + pad(date.getMinutes())
        var now = new Date()
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        var itemDay = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
        var dayDifference = Math.round((today - itemDay) / 86400000)
        if (dayDifference === 0)
            return "今天 " + timeText
        if (dayDifference === 1)
            return "昨天 " + timeText
        if (date.getFullYear() === now.getFullYear())
            return pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " + timeText
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-"
               + pad(date.getDate()) + " " + timeText
    }

    function openRecentItem(path, kind, name, previewType, extension, mimeType) {
        var sourcePath = path === undefined || path === null ? "" : path.toString()
        if (sourcePath.length === 0)
            return
        selectedRecentPath = sourcePath
        if (kind === "folder") {
            currentNav = "我的文件"
            clearSelection()
            navigationChanged(currentNav)
            openFolder(sourcePath)
            return
        }
        previewRequested(name, sourcePath, previewType, extension, mimeType)
    }

    function openRecentLocation(path) {
        var sourcePath = path === undefined || path === null ? "" : path.toString()
        if (sourcePath.length === 0)
            return
        var separator = sourcePath.lastIndexOf("/")
        var parentPath = separator >= 0 ? sourcePath.substring(0, separator) : ""
        currentNav = "我的文件"
        clearSelection()
        navigationChanged(currentNav)
        openFolder(parentPath)
    }

    function removeRecentRecord(name, path) {
        var sourcePath = path === undefined || path === null ? "" : path.toString()
        if (sourcePath.length === 0 || uploadManager.updatingRecent)
            return
        if (selectedRecentPath === sourcePath)
            selectedRecentPath = ""
        recentRemovalRequested(name, sourcePath)
    }

    function matchesTrashFilter(kind) {
        if (trashFilter === "文件")
            return kind !== "folder"
        if (trashFilter === "文件夹")
            return kind === "folder"
        return true
    }

    function matchesTrashSearch(name) {
        return trashSearchKeyword.length === 0
               || name.toLowerCase().indexOf(trashSearchKeyword.toLowerCase()) !== -1
    }

    function trashItemPath(path, name) {
        if (path !== undefined && path !== null && path.toString().length > 0)
            return path.toString()
        return name === undefined || name === null ? "" : name.toString()
    }

    // C++ 可直接替换 trashModelSource，也可在回收站请求完成后调用此函数填充本地模型。
    function setTrashItems(items) {
        trashModel.clear()
        if (items === undefined || items === null)
            return
        for (var i = 0; i < items.length; ++i)
            trashModel.append(items[i])
    }

    function removeFavorite(index, name, path) {
        if (uploadManager.updatingFavorite || path === undefined || path === null
                || path.toString().length === 0)
            return
        if (selectedName === name)
            clearSelection()
        // 是否收藏由服务器权威判断；成功响应后再刷新模型，失败时不错误移除界面数据。
        favoriteRemovalRequested(name, path.toString())
    }

    function openFavoriteFolder(path) {
        currentNav = "我的文件"
        clearSelection()
        navigationChanged(currentNav)
        openFolder(path)
    }

    // 与客户端和服务端保持一致，提前给出名称错误，服务端仍会进行最终校验。
    function validateItemName(itemName, itemKind) {
        var name = itemName === undefined || itemName === null ? "" : itemName.toString().trim()
        var typeName = itemKind === "folder" ? "文件夹名称" : "文件名称"
        if (name.length === 0)
            return "请输入" + typeName
        if (name.length > 100)
            return typeName + "不能超过 100 个字符"
        if (name === "." || name === "..")
            return typeName + "不能是“.”或“..”"

        var invalidCharacters = "<>:\"/\\|?*"
        for (var i = 0; i < name.length; ++i) {
            if (name.charCodeAt(i) < 32 || invalidCharacters.indexOf(name.charAt(i)) !== -1)
                return "名称不能包含 < > : \" / \\ | ? * 或控制字符"
        }
        if (name.charAt(name.length - 1) === "." || name.charAt(name.length - 1) === " ")
            return typeName + "不能以句点或空格结尾"

        var baseName = name
        var firstDot = baseName.indexOf(".")
        if (firstDot > 0)
            baseName = baseName.substring(0, firstDot)
        baseName = baseName.toUpperCase()
        if (["CON", "PRN", "AUX", "NUL"].indexOf(baseName) !== -1
                || /^(COM|LPT)[1-9]$/.test(baseName))
            return "该名称是系统保留名称，请更换" + typeName

        return ""
    }

    function validateFolderName(folderName) {
        return validateItemName(folderName, "folder")
    }

    function isImageExtension(extension) {
        if (extension === undefined || extension === null)
            return false

        var value = extension.toString().toLowerCase()
        return ["jpg", "jpeg", "png", "gif", "bmp", "webp",
                "svg", "ico", "tif", "tiff"].indexOf(value) !== -1
    }

    function isTextExtension(extension) {
        if (extension === undefined || extension === null)
            return false

        var value = extension.toString().toLowerCase()
        return ["txt", "md", "markdown", "log", "json", "xml", "yaml", "yml",
                "csv", "tsv", "ini", "cfg", "conf", "properties", "html", "htm",
                "css", "js", "ts", "qml", "c", "h", "cpp", "hpp", "cc", "cxx",
                "java", "py", "sh", "bat", "sql", "vue", "php", "rb", "go", "rs"
               ].indexOf(value) !== -1
    }

    function previewTypeForExtension(extension) {
        if (isImageExtension(extension))
            return "image"
        if (isTextExtension(extension))
            return "text"
        return "binary"
    }

    function fileTypeDescription(extension) {
        if (extension === undefined || extension === null)
            return "文件"

        var value = extension.toString().toLowerCase()
        if (value === "pdf")
            return "PDF 文档"
        if (["doc", "docx", "rtf", "odt"].indexOf(value) !== -1)
            return "文字文档"
        if (["xls", "xlsx", "csv", "ods"].indexOf(value) !== -1)
            return "表格文件"
        if (["ppt", "pptx", "odp"].indexOf(value) !== -1)
            return "演示文稿"
        if (["txt", "md", "log", "json", "xml"].indexOf(value) !== -1)
            return "文本文件"
        if (["mp4", "mov", "avi", "mkv", "webm"].indexOf(value) !== -1)
            return "视频文件"
        if (["mp3", "wav", "flac", "aac", "ogg"].indexOf(value) !== -1)
            return "音频文件"
        if (["zip", "rar", "7z", "tar", "gz"].indexOf(value) !== -1)
            return "压缩文件"
        return value.length > 0 ? value.toUpperCase() + " 文件" : "文件"
    }

    // 页面背景
    Rectangle {
        anchors.fill: parent
        color: root.pageColor
        bottomRightRadius: root.maximized ? 0 : root.cornerRadius
        antialiasing: true
    }

    Row {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        // 左侧导航栏
        // ============================================================
        FileSidebar {
            id: sidebar
            host: root
        }

        // ============================================================
        // 右侧工作区
        // ============================================================
        Rectangle {
            id: workspace
            width: parent.width - sidebar.width
            height: parent.height
            bottomRightRadius: root.maximized ? 0 : root.cornerRadius
            antialiasing: true
            Row {
                anchors.fill: parent
                spacing: 0

                // 中央文件区域
                Item {
                    id: mainArea
                    width: workspace.width - (root.currentNav !== "收藏夹"
                                              && root.currentNav !== "最近使用"
                                              && root.currentNav !== "回收站"
                                              && root.detailsVisible && workspace.width >= 850 ? 270 : 0)
                    height: parent.height

                    Behavior on width {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    MyFilesPage {
                        id: myFilesPage
                        host: root
                        contextMenu: rowMenu
                        folderDialog: createFolderDialog
                    }

                    // ====================================================
                    // 收藏夹：与“我的文件”并列，仅由导航状态切换显示。
                    // ====================================================
                    FavoritesPage {
                        id: favoritesPage
                        host: root
                    }

                    // ====================================================
                    // 最近使用：真实持久化记录，支持打开、定位、移除和清空。
                    // ====================================================
                    RecentPage {
                        id: recentPage
                        host: root
                        clearDialog: recentClearDialog
                    }

                    // ====================================================
                    // 回收站：独立页面，操作请求交由 UploadManager 处理并刷新数据源。
                    // ====================================================
                    TrashPage {
                        id: trashPage
                        host: root
                        actionDialog: trashActionDialog
                    }
                }

                // ========================================================
                // 右侧详情面板（窄窗口自动隐藏）
                // ========================================================
                FileDetailsPanel {
                    id: detailsPanel
                    host: root
                    availableWidth: workspace.width
                }
            }
        }
    }

    // ============================================================
    // 文件行“更多操作”菜单：打开和下载直接使用当前行的云端相对路径。
    // ============================================================
    FileContextMenu {
        id: rowMenu
        host: root
        renameController: renameDialog
        moveController: moveDialog
    }

    // 真实收藏数据由 UploadManager.favoritesLoaded 填充；动态角色保留 favoriteTime/location。
    ListModel {
        id: favoritesModel
        dynamicRoles: true
    }

    // 最近使用数据由 UploadManager.recentLoaded 填充；记录路径与原文件保持关联。
    ListModel {
        id: recentModel
        dynamicRoles: true
    }

    // 回收站数据由 UploadManager.trashLoaded 填充，也可通过 setTrashItems() 设置。
    ListModel {
        id: trashModel
        dynamicRoles: true
        /*
        ListElement {
            name: "旧版项目方案.pdf"
            kind: "file"
            ext: "PDF"
            path: "旧版项目方案.pdf"
            location: "我的文件 / 项目资料"
            deletedTime: "今天 14:30"
            size: "2.4 MB"
            iconBg: "#FFF0EF"
            iconColor: "#E47772"
        }
        */
    }

    // 示例文件数据：接入 C++ 后可替换为 QAbstractListModel
    ListModel {
        id: fileModel
        dynamicRoles: true
        /*
        ListElement {
            name: "项目资料"
            kind: "folder"
            ext: "文件夹"
            modified: "今天 14:28"
            size: "18 个文件"
            status: "已同步"
            iconBg: "#EEF2FF"
            iconColor: "#4B6EF5"
        }
        ListElement {
            name: "产品原型.fig"
            kind: "file"
            ext: "FIG"
            modified: "今天 13:52"
            size: "8.6 MB"
            status: "已同步"
            iconBg: "#F1ECFF"
            iconColor: "#8A6AE8"
        }
        ListElement {
            name: "客户需求文档.docx"
            kind: "file"
            ext: "DOCX"
            modified: "今天 11:20"
            size: "256 KB"
            status: "已同步"
            iconBg: "#EAF2FF"
            iconColor: "#4C83D9"
        }
        ListElement {
            name: "项目方案.pdf"
            kind: "file"
            ext: "PDF"
            modified: "昨天 17:46"
            size: "2.4 MB"
            status: "已同步"
            iconBg: "#FFF0EF"
            iconColor: "#E47772"
        }
        ListElement {
            name: "会议记录.xlsx"
            kind: "file"
            ext: "XLSX"
            modified: "昨天 16:08"
            size: "128 KB"
            status: "同步中"
            iconBg: "#EAF8F2"
            iconColor: "#28A879"
        }
        ListElement {
            name: "设计素材"
            kind: "folder"
            ext: "文件夹"
            modified: "11 月 03 日"
            size: "32 个文件"
            status: "已同步"
            iconBg: "#EEF2FF"
            iconColor: "#4B6EF5"
        }
        ListElement {
            name: "头像素材.zip"
            kind: "file"
            ext: "ZIP"
            modified: "11 月 02 日"
            size: "36.2 MB"
            status: "等待同步"
            iconBg: "#FFF5E8"
            iconColor: "#D99A42"
        }
        ListElement {
            name: "2026 年度计划.pptx"
            kind: "file"
            ext: "PPTX"
            modified: "10 月 30 日"
            size: "4.1 MB"
            status: "已同步"
            iconBg: "#FFF0E9"
            iconColor: "#E58A54"
        }
        */
    }


    // 删除只移入应用回收站；文件夹及其全部内容由服务端一次性移动。
    DeleteConfirmDialog {
        id: deleteConfirmDialog
        host: root
    }
    TrashActionDialog {
        id: trashActionDialog
        host: root
    }
    CreateFolderDialog {
        id: createFolderDialog
        host: root
    }
    RenameDialog {
        id: renameDialog
        host: root
    }
    MoveDialog {
        id: moveDialog
        host: root
    }
    ClearRecentDialog {
        id: recentClearDialog
        host: root
    }
    OperationResultDialog {
        id: favoriteResultDialog
        host: root
    }
    DownloadResultDialog {
        id: downloadResultDialog
    }

    // 文件夹下载选择目标父目录，实际保存目录由 UploadManager 新建并自动避免重名。
    FolderDialog {
        id: downloadFolderDialog
        title: "选择文件夹保存位置"

        property string cloudPath: ""

        onAccepted: {
            var sourcePath = cloudPath
            cloudPath = ""
            uploadManager.downloadFolder(sourcePath, selectedFolder)
        }
        onRejected: cloudPath = ""
    }

    // 单文件下载保存对话框：只在用户确认目标路径后启动网络请求。
    FileDialog {
        id: downloadFileDialog
        title: "下载到本地"
        fileMode: FileDialog.SaveFile
        nameFilters: ["所有文件 (*)"]

        property string cloudPath: ""

        onAccepted: {
            var sourcePath = cloudPath
            cloudPath = ""
            uploadManager.downloadFile(sourcePath, selectedFile)
        }
        onRejected: cloudPath = ""
    }

    // 上传交互独立封装，页面只负责打开弹窗和维护文件列表。
    UploadDialog {
        id: uploadDialog
        anchors.centerIn: root
        manager: uploadManager
    }

    Connections {
        target: uploadManager

        function onCurrentPathChanged() {
            fileModel.clear()
            root.pendingCreatedFolderName = ""
            root.pendingCreatedFolderPath = ""
            root.pendingRenamedPath = ""
            root.refreshAfterCurrentFileLoad = false
            root.currentFilter = "全部"
            root.searchKeyword = ""
            myFilesPage.clearSearch()
            root.clearSelection()
            rowMenu.close()
            deleteConfirmDialog.close()
            renameDialog.close()
            moveDialog.close()
        }

        // 服务器文件列表加载成功
        function onFilesLoaded(items) {
            fileModel.clear()

            for (var i = 0; i < items.length; ++i) {
                fileModel.append(items[i])
            }

            // 新建完成后以服务器列表为准，并选中新文件夹，保持上传后的交互反馈一致。
            var foundCreatedFolder = false
            var shouldReloadAfterCurrentLoad = root.refreshAfterCurrentFileLoad
            if (root.pendingCreatedFolderName.length > 0) {
                for (var j = 0; j < fileModel.count; ++j) {
                    var item = fileModel.get(j)
                    var itemPath = item.path === undefined || item.path === null ? "" : item.path.toString()
                    var pathMatches = root.pendingCreatedFolderPath.length > 0
                                      ? itemPath === root.pendingCreatedFolderPath
                                      : item.name === root.pendingCreatedFolderName
                    if (item.kind === "folder" && pathMatches) {
                        root.selectFile(item.name, item.kind, item.modified, item.size,
                                        item.status, item.ext, itemPath)
                        foundCreatedFolder = true
                        break
                    }
                }

                // 如果当前响应可能创建于新文件夹之前，则保留选中信息，等待补发的新请求。
                if (foundCreatedFolder || !shouldReloadAfterCurrentLoad) {
                    root.pendingCreatedFolderName = ""
                    root.pendingCreatedFolderPath = ""
                }
            }

            // 重命名后以服务端返回的新路径重新选中对应项目。
            if (root.pendingRenamedPath.length > 0) {
                for (var k = 0; k < fileModel.count; ++k) {
                    var renamedItem = fileModel.get(k)
                    var renamedItemPath = renamedItem.path === undefined || renamedItem.path === null
                                          ? "" : renamedItem.path.toString()
                    if (renamedItemPath === root.pendingRenamedPath) {
                        root.selectFile(renamedItem.name, renamedItem.kind, renamedItem.modified,
                                        renamedItem.size, renamedItem.status, renamedItem.ext,
                                        renamedItemPath)
                        break
                    }
                }
                root.pendingRenamedPath = ""
            }

            // 若创建前已有列表请求，新请求已取代旧请求；未找到新文件夹时再补查一次。
            if (shouldReloadAfterCurrentLoad) {
                root.refreshAfterCurrentFileLoad = false
                if (!foundCreatedFolder)
                    uploadManager.loadFiles()
            }
        }

        function onFavoritesLoaded(items) {
            favoritesModel.clear()
            for (var i = 0; i < items.length; ++i)
                favoritesModel.append(items[i])
        }

        function onFavoritesLoadFailed(reason) {
            console.warn("加载收藏列表失败：" + reason)
        }


        function onRecentLoaded(items) {
            root.recentError = ""
            root.setRecentItems(items)
        }

        function onRecentLoadFailed(reason) {
            root.recentError = reason
            console.warn("加载最近使用失败：" + reason)
            Qt.callLater(root.updateRecentVisibleCount)
        }

        function onRecentRecordFailed(path, reason) {
            // 后台记录失败不打断预览、打开或下载主流程。
            console.warn("记录最近使用失败：" + path + "，" + reason)
        }

        function onRecentItemRemoved(path, recentCount) {
            if (root.selectedRecentPath === path)
                root.selectedRecentPath = ""
            favoriteResultDialog.showResult(true,
                "已从最近使用中移除，原文件未受影响。", "最近使用", "◷")
        }

        function onRecentRemoveFailed(path, reason) {
            favoriteResultDialog.showResult(false,
                "移除最近记录失败：" + reason, "最近使用", "◷")
        }

        function onRecentCleared(removedCount) {
            recentClearDialog.close()
            root.selectedRecentPath = ""
            favoriteResultDialog.showResult(true,
                removedCount > 0 ? "已清空 " + removedCount + " 条最近使用记录，原文件未受影响。"
                                 : "最近使用记录已经是空的。", "最近使用", "◷")
        }

        function onRecentClearFailed(reason) {
            recentClearDialog.close()
            favoriteResultDialog.showResult(false,
                "清空最近使用失败：" + reason, "最近使用", "◷")
        }

        function onTrashLoaded(items) {
            root.setTrashItems(items)
        }

        function onTrashLoadFailed(reason) {
            console.warn("加载回收站失败：" + reason)
            if (root.currentNav === "回收站")
                favoriteResultDialog.showResult(false, "加载回收站失败：" + reason)
        }

        function onTrashItemRestored(trashId, originalPath) {
            root.selectedTrashPath = ""
            uploadManager.loadTrash()
            uploadManager.loadFiles()
            uploadManager.loadFavorites()
            favoriteResultDialog.showResult(true, originalPath.length > 0
                ? "已还原到原位置：" + originalPath
                : "回收站项目已还原。")
        }

        function onTrashItemRestoreFailed(trashId, reason) {
            // 响应丢失或跨卷移动异常时，服务器可能已经产生部分实际变化。
            uploadManager.loadTrash()
            uploadManager.loadFiles()
            favoriteResultDialog.showResult(false, "还原失败：" + reason)
        }

        function onTrashItemPermanentlyDeleted(trashId) {
            root.selectedTrashPath = ""
            uploadManager.loadTrash()
            favoriteResultDialog.showResult(true, "项目已彻底删除。")
        }

        function onTrashPermanentDeleteFailed(trashId, reason) {
            uploadManager.loadTrash()
            favoriteResultDialog.showResult(false, "彻底删除失败：" + reason)
        }

        function onTrashEmptied(deletedCount) {
            root.selectedTrashPath = ""
            uploadManager.loadTrash()
            favoriteResultDialog.showResult(true, deletedCount > 0
                ? "回收站已清空，共彻底删除 " + deletedCount + " 个项目。"
                : "回收站已经是空的。")
        }

        function onTrashEmptyFailed(reason) {
            // 清空可能只失败了一部分，以服务器重新返回的列表为准。
            root.selectedTrashPath = ""
            uploadManager.loadTrash()
            favoriteResultDialog.showResult(false, "清空回收站失败：" + reason)
        }

        function onServerFilesChanged(paths, revision) {
            // 其他客户端删除或还原内容时，正在查看的回收站也保持同步。
            if (root.currentNav === "回收站")
                uploadManager.loadTrash()
        }

        function onFavoriteAdded(path, addedCount, favoriteCount) {
            favoriteResultDialog.showResult(true, addedCount > 0
                ? "收藏成功，新增 " + addedCount + " 个收藏项目。"
                : "所选内容均已在收藏夹中，没有产生重复收藏。")
        }

        function onFavoriteAddFailed(path, reason) {
            favoriteResultDialog.showResult(false, "添加收藏失败：" + reason)
        }

        function onFavoriteRemoved(path, removedCount, favoriteCount) {
            favoriteResultDialog.showResult(true, removedCount > 0
                ? "已取消收藏，共移除 " + removedCount + " 个收藏入口。"
                : "该项目原本就不在收藏夹中。")
        }

        function onFavoriteRemoveFailed(path, reason) {
            favoriteResultDialog.showResult(false, "取消收藏失败：" + reason)
        }

        function onFolderCreated(folderName, folderPath, modifiedText) {
            root.pendingCreatedFolderName = folderName
            root.pendingCreatedFolderPath = folderPath
            root.refreshAfterCurrentFileLoad = uploadManager.loadingFiles
            createFolderDialog.errorText = ""
            createFolderDialog.close()
            // 在线时由服务器 filesChanged 事件驱动刷新；离线时保留原 HTTP 兜底。
            if (!uploadManager.webSocketConnected)
                uploadManager.loadFiles()
        }

        function onFolderCreationFailed(folderName, reason) {
            createFolderDialog.errorText = reason
            createFolderDialog.focusNameField()
        }

        function onItemRenamed(oldPath, newPath, newName) {
            root.pendingRenamedPath = newPath
            root.clearSelection()
            renameDialog.errorText = ""
            renameDialog.close()

            // 主动刷新可取消改名前尚未完成的旧列表请求；WebSocket 事件仍用于同步其他客户端。
            uploadManager.loadFiles()
            uploadManager.loadFavorites()
            uploadManager.loadRecent()
        }

        function onItemRenameFailed(oldPath, reason) {
            renameDialog.errorText = reason
            renameDialog.focusNameField()
        }

        function onFolderChoicesLoaded(folderPath, folders) {
            if (!moveDialog.opened || folderPath !== moveDialog.currentFolderPath)
                return
            moveDialog.folderItems = folders
            moveDialog.errorText = ""
            moveDialog.directoryLoaded = true
        }

        function onFolderChoicesLoadFailed(folderPath, reason) {
            if (!moveDialog.opened || folderPath !== moveDialog.currentFolderPath)
                return
            moveDialog.folderItems = []
            moveDialog.directoryLoaded = false
            moveDialog.errorText = reason
        }

        function onItemMoved(oldPath, newPath, destinationPath) {
            moveDialog.errorText = ""
            moveDialog.close()
            root.clearSelection()

            // 移动后原目录和目标目录都可能变化；当前若仍在原目录，立即移除旧项目。
            // WebSocket 事件会继续同步其他客户端，主动刷新则保证离线时也能更新。
            uploadManager.loadFiles()
            uploadManager.loadFavorites()
            uploadManager.loadRecent()
        }

        function onItemMoveFailed(oldPath, reason) {
            if (!moveDialog.opened)
                return
            moveDialog.errorText = reason
        }

        function onItemDeleted(sourcePath, trashId) {
            root.clearSelection()
            rowMenu.close()
            deleteConfirmDialog.close()

            // 只有服务端确认移动成功后才更新界面；WebSocket 负责同步其他客户端。
            uploadManager.loadFiles()
            uploadManager.loadFavorites()
            uploadManager.loadRecent()
            uploadManager.loadTrash()
            favoriteResultDialog.showResult(true, "已移入回收站，文件及文件夹内容均已保留。")
        }

        function onItemDeleteFailed(sourcePath, reason) {
            favoriteResultDialog.showResult(false, "删除失败：" + reason)
        }

        // 所有上传任务完成。在线时等待服务器事件，避免每个文件都重复刷新。
        function onUploadFinished(successCount, failedCount) {
            if (successCount > 0 && !uploadManager.webSocketConnected)
                uploadManager.loadFiles()
        }

        function onFileDownloaded(path, localPath) {
            root.showDownloadResult(true, false, localPath, "")
        }

        function onFolderDownloaded(path, localPath) {
            root.showDownloadResult(true, true, localPath, "")
        }

        function onFileDownloadFailed(path, reason) {
            root.showDownloadResult(false, false, "", reason)
        }

        function onFolderDownloadFailed(path, reason) {
            root.showDownloadResult(false, true, "", reason)
        }

        function onFilesLoadFailed(reason) {
            console.warn("加载文件列表失败：" + reason)
            if (root.refreshAfterCurrentFileLoad) {
                root.refreshAfterCurrentFileLoad = false
                uploadManager.loadFiles()
            }
        }
    }


    Component.onCompleted: {
        uploadManager.loadFiles()
        uploadManager.loadFavorites()
        uploadManager.loadRecent()
    }
}
