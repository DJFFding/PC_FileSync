#pragma once

#include <QObject>
#include <QList>
#include <QNetworkAccessManager>
#include <QQueue>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QWebSocket>

class QNetworkReply;
class QProcess;
class QSaveFile;
class QTemporaryDir;
class QTemporaryFile;
class QUrl;

/**
 * FileSync 文件上传/文件列表控制器。
 *
 * 上传协议：POST multipart/form-data，文件字段名为 file。
 * 新建文件夹协议：POST /folders，JSON 请求体为 { "name": "文件夹名称", "path": "父目录" }。
 * 文件列表协议：GET /files?path=目录，返回当前层 items，以及递归文件统计。
 * 仍兼容仅返回 items 数组，或 files + directories 数组的服务。
 * 实时同步协议：WebSocket /events，接收服务器 filesChanged 事件并自动刷新。
 * 文件内容和列表仍使用 HTTP，WebSocket 只承担服务器主动通知。
 */
class UploadManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(QString fileListUrl READ fileListUrl WRITE setFileListUrl NOTIFY fileListUrlChanged)
    Q_PROPERTY(QString webSocketUrl READ webSocketUrl WRITE setWebSocketUrl NOTIFY webSocketUrlChanged)
    Q_PROPERTY(bool webSocketConnected READ webSocketConnected NOTIFY webSocketConnectedChanged)
    Q_PROPERTY(QString webSocketStatus READ webSocketStatus NOTIFY webSocketStatusChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadingChanged)
    Q_PROPERTY(bool loadingFiles READ loadingFiles NOTIFY loadingFilesChanged)
    Q_PROPERTY(bool creatingFolder READ creatingFolder NOTIFY creatingFolderChanged)
    Q_PROPERTY(bool openingFile READ openingFile NOTIFY openingFileChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString currentFile READ currentFile NOTIFY currentFileChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString listStatus READ listStatus NOTIFY listStatusChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(int cloudFileCount READ cloudFileCount NOTIFY cloudFileCountChanged)
    Q_PROPERTY(int syncedFileCount READ syncedFileCount NOTIFY syncedFileCountChanged)
    Q_PROPERTY(int syncingFileCount READ syncingFileCount NOTIFY syncingFileCountChanged)
    Q_PROPERTY(int completedCount READ completedCount NOTIFY completedCountChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int successCount READ successCount NOTIFY successCountChanged)
    Q_PROPERTY(int failedCount READ failedCount NOTIFY failedCountChanged)

public:
    explicit UploadManager(QObject *parent = nullptr);
    ~UploadManager() override;

    QString serverUrl() const;
    void setServerUrl(const QString &url);

    QString fileListUrl() const;
    void setFileListUrl(const QString &url);

    // 留空时根据 fileListUrl 推导：http→ws、https→wss，端口加一，路径改为 /events。
    QString webSocketUrl() const;
    void setWebSocketUrl(const QString &url);
    bool webSocketConnected() const;
    QString webSocketStatus() const;

    bool uploading() const;
    bool loadingFiles() const;
    bool creatingFolder() const;
    bool openingFile() const;
    bool downloading() const;
    int progress() const;
    QString currentFile() const;
    QString statusText() const;
    QString listStatus() const;
    QString currentPath() const;
    int cloudFileCount() const;
    int syncedFileCount() const;
    int syncingFileCount() const;
    int completedCount() const;
    int totalCount() const;
    int successCount() const;
    int failedCount() const;

    // 接收 QtQuick.Dialogs FileDialog.selectedFiles（QUrl 列表）。
    Q_INVOKABLE void uploadFiles(const QVariantList &selectedFiles);

    // 启动时或刷新时，从服务器重新获取当前目录的直接子项及递归统计。
    Q_INVOKABLE void loadFiles();

    // 手动重建实时事件连接；通常无需调用，断线后客户端会自动重连。
    Q_INVOKABLE void reconnectWebSocket();

    // 双击文件夹或点击面包屑时进入指定云端相对目录；空路径表示根目录。
    Q_INVOKABLE void openFolder(const QString &folderPath);

    // 在当前文件列表接口同级创建 /folders 请求，在当前目录新建一个文件夹。
    Q_INVOKABLE void createFolder(const QString &folderName);

    // 打开文件：远端文件先流式下载到临时目录，再交给系统默认程序打开。
    // 临时文件由本类持有，应用退出前不会被清理，避免外部程序读到不存在的路径。
    Q_INVOKABLE void openFile(const QString &path);

    // 下载文件：destination 接收 QtQuick.Dialogs FileDialog.selectedFile。
    // 使用 QSaveFile 原子写入，失败时不会留下不完整的下载文件。
    Q_INVOKABLE void downloadFile(const QString &path, const QUrl &destination);

    // 下载文件夹：destination 接收 QtQuick.Dialogs FolderDialog.selectedFolder。
    // 在所选目录下新建同名文件夹，递归保留子目录及空目录，不覆盖已有同名目录。
    Q_INVOKABLE void downloadFolder(const QString &path, const QUrl &destination);

    // 为保存对话框提供“系统下载目录 + 原文件名”的默认位置。
    Q_INVOKABLE QUrl defaultDownloadUrl(const QString &path) const;

    // 将列表中的相对路径转换为可供 QML Image 使用的文件内容 URL。
    Q_INVOKABLE QString fileContentUrl(const QString &path) const;

    // 全屏文本预览使用的分块 URL。远程服务通过 offset/maxBytes 返回后续内容。
    Q_INVOKABLE QString textChunkUrl(const QString &path,
                                     qint64 offset,
                                     qint64 maxBytes) const;

    // PDF 直接预览；DOCX 先通过 LibreOffice 转成 PDF，再复用 MuPDF 分页预览。
    // 返回请求编号，结果通过下面的信号异步返回。
    Q_INVOKABLE int prepareDocument(const QString &path, const QString &extension);
    Q_INVOKABLE void cancelDocumentPreparation();

    // 由 C++ 直接写系统剪贴板，避免复制按钮改变 QML 文本选区。
    Q_INVOKABLE void copyTextToClipboard(const QString &text) const;

signals:
    void serverUrlChanged();
    void fileListUrlChanged();
    void webSocketUrlChanged();
    void webSocketConnectedChanged();
    void webSocketStatusChanged();
    void uploadingChanged();
    void loadingFilesChanged();
    void creatingFolderChanged();
    void openingFileChanged();
    void downloadingChanged();
    void progressChanged();
    void currentFileChanged();
    void statusTextChanged();
    void listStatusChanged();
    void currentPathChanged();
    void cloudFileCountChanged();
    void syncedFileCountChanged();
    void syncingFileCountChanged();
    void completedCountChanged();
    void totalCountChanged();
    void successCountChanged();
    void failedCountChanged();

    // items 中每项都包含 QML 文件列表使用的角色：name/kind/ext/modified/size/status/iconBg/iconColor/path，
    // 并透传服务端提供的 previewType（image/text/binary）和 mimeType。
    void filesLoaded(const QVariantList &items);
    void filesLoadFailed(const QString &reason);

    // 所有服务器变更都会透传；当前目录受影响的变更还会触发自动刷新。
    void serverFilesChanged(const QStringList &paths, quint64 revision);

    void folderCreated(const QString &folderName,
                       const QString &folderPath,
                       const QString &modifiedText);
    void folderCreationFailed(const QString &folderName, const QString &reason);

    void fileOpened(const QString &path, const QString &localPath);
    void fileOpenFailed(const QString &path, const QString &reason);
    void fileDownloaded(const QString &path, const QString &localPath);
    void fileDownloadFailed(const QString &path, const QString &reason);
    void folderDownloaded(const QString &path, const QString &localPath);
    void folderDownloadFailed(const QString &path, const QString &reason);

    // DOCX 转换成功后同样发出此信号，QML 无需维护第二套文档视图。
    void pdfPreviewReady(int requestId, const QString &localUrl, int pageCount);
    void documentPreviewFailed(int requestId, const QString &reason);

    void fileUploaded(const QString &fileName,
                      const QString &displaySize,
                      const QString &modifiedText);
    void fileUploadFailed(const QString &fileName, const QString &reason);
    void uploadFinished(int successCount, int failedCount);

private:
    struct UploadTask
    {
        QString path;
        QString fileName;
        qint64 size = 0;
    };

    struct FolderFileTask
    {
        QString cloudPath;
        QString localPath;
    };

    void uploadNext();
    void finishCurrentTask(bool success, const QString &reason = QString());

    void finishOpenFile();
    void failFileOpen(const QString &reason);
    void resetOpenFile();
    void startFileDownload(const QString &path, const QUrl &destination);
    void finishDownload();
    void failDownload(const QString &reason);
    void resetDownload();
    void processNextFolderDirectory();
    void downloadNextFolderFile();
    void finishFolderDownload();
    void failFolderDownload(const QString &reason);
    void resetFolderDownload();

    void resetDocumentPreparation();
    void prepareLocalDocument(int requestId, const QUrl &sourceUrl);
    void processDownloadedDocument(int requestId);
    void convertDocxToPdf(int requestId, const QString &sourcePath);
    void showPdfPreview(int requestId, const QString &filePath);
    void failDocumentPreview(int requestId, const QString &reason);

    QUrl derivedWebSocketUrl() const;
    void openWebSocket();
    void scheduleWebSocketReconnect();
    void handleWebSocketMessage(const QString &message);
    bool eventAffectsCurrentPath(const QStringList &paths) const;
    void scheduleFilesRefresh(int delayMs = 250);
    void setWebSocketConnected(bool value);
    void setWebSocketStatus(const QString &value);

    void setUploading(bool value);
    void setLoadingFiles(bool value);
    void setCreatingFolder(bool value);
    void setOpeningFile(bool value);
    void setDownloading(bool value);
    void setProgress(int value);
    void setCurrentFile(const QString &value);
    void setStatusText(const QString &value);
    void setListStatus(const QString &value);
    void setCloudFileCount(int value);
    void setSyncedFileCount(int value);
    void setSyncingFileCount(int value);
    void updateSyncingFileCount();
    void setCompletedCount(int value);
    void setTotalCount(int value);
    void setSuccessCount(int value);
    void setFailedCount(int value);
    static QString formatFileSize(qint64 bytes);

    QNetworkAccessManager m_network;
    QWebSocket m_eventSocket;
    QTimer m_reconnectTimer;
    QTimer m_refreshTimer;
    QTimer m_pingTimer;
    QTimer m_handshakeTimer;
    QQueue<UploadTask> m_queue;
    QNetworkReply *m_reply = nullptr;
    QNetworkReply *m_listReply = nullptr;
    QNetworkReply *m_folderReply = nullptr;
    QNetworkReply *m_documentReply = nullptr;
    QNetworkReply *m_openReply = nullptr;
    QNetworkReply *m_downloadReply = nullptr;
    QNetworkReply *m_folderListReply = nullptr;
    QTemporaryFile *m_openFile = nullptr;
    QSaveFile *m_downloadFile = nullptr;
    // 已交给外部程序打开的文件需要保留到应用退出，不能下载完成后立即删除。
    QList<QTemporaryFile *> m_openedFiles;
    QString m_openCloudPath;
    QString m_downloadCloudPath;
    QString m_downloadLocalPath;
    QQueue<QString> m_folderPendingDirectories;
    QQueue<FolderFileTask> m_folderFileQueue;
    QSet<QString> m_folderKnownDirectories;
    QSet<QString> m_folderKnownFiles;
    QString m_folderCloudPath;
    QString m_folderLocalRoot;
    int m_folderTotalFiles = 0;
    int m_folderCompletedFiles = 0;
    bool m_folderDownloadActive = false;
    QTemporaryFile *m_documentFile = nullptr;
    QProcess *m_documentConverter = nullptr;
    // 保存 DOCX 转换输入、独立 LibreOffice 配置及输出 PDF，关闭预览前不能删除。
    QTemporaryDir *m_documentWorkspace = nullptr;
    UploadTask m_currentTask;

    int m_documentRequestId = 0;
    QString m_documentExtension;

    QString m_serverUrl = QStringLiteral("http://127.0.0.1:8080/upload");
    QString m_fileListUrl = QStringLiteral("http://127.0.0.1:8080/files");
    QString m_webSocketUrl; // 空字符串表示自动推导
    QString m_activeWebSocketUrl;
    QString m_webSocketStatus = QStringLiteral("实时同步未连接");
    bool m_webSocketConnected = false;
    bool m_shuttingDown = false;
    int m_reconnectAttempt = 0;
    quint64 m_lastEventRevision = 0;
    QString m_currentFile;
    QString m_statusText;
    QString m_listStatus;
    QString m_currentPath;
    QString m_uploadDirectory;
    int m_cloudFileCount = 0;
    int m_syncedFileCount = 0;
    int m_syncingFileCount = 0;
    int m_serverSyncedFileCount = 0;
    int m_serverSyncingFileCount = 0;
    bool m_uploading = false;
    bool m_loadingFiles = false;
    bool m_creatingFolder = false;
    bool m_openingFile = false;
    bool m_downloading = false;
    int m_progress = 0;
    int m_completedCount = 0;
    int m_totalCount = 0;
    int m_successCount = 0;
    int m_failedCount = 0;
    qint64 m_totalBytes = 0;
    qint64 m_completedBytes = 0;
};
