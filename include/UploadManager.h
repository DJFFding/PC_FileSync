#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QQueue>
#include <QVariantList>

class QNetworkReply;
class QTemporaryFile;
class QUrl;

/**
 * FileSync 文件上传/文件列表控制器。
 *
 * 上传协议：POST multipart/form-data，文件字段名为 file。
 * 文件列表协议：GET /files，返回 JSON 中的 items 数组，或 files + directories 数组。
 */
class UploadManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(QString fileListUrl READ fileListUrl WRITE setFileListUrl NOTIFY fileListUrlChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadingChanged)
    Q_PROPERTY(bool loadingFiles READ loadingFiles NOTIFY loadingFilesChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString currentFile READ currentFile NOTIFY currentFileChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString listStatus READ listStatus NOTIFY listStatusChanged)
    Q_PROPERTY(int completedCount READ completedCount NOTIFY completedCountChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int successCount READ successCount NOTIFY successCountChanged)
    Q_PROPERTY(int failedCount READ failedCount NOTIFY failedCountChanged)

public:
    explicit UploadManager(QObject *parent = nullptr);

    QString serverUrl() const;
    void setServerUrl(const QString &url);

    QString fileListUrl() const;
    void setFileListUrl(const QString &url);

    bool uploading() const;
    bool loadingFiles() const;
    int progress() const;
    QString currentFile() const;
    QString statusText() const;
    QString listStatus() const;
    int completedCount() const;
    int totalCount() const;
    int successCount() const;
    int failedCount() const;

    // 接收 QtQuick.Dialogs FileDialog.selectedFiles（QUrl 列表）。
    Q_INVOKABLE void uploadFiles(const QVariantList &selectedFiles);

    // 启动时或刷新时，从服务器重新获取全部文件及目录。
    Q_INVOKABLE void loadFiles();

    // 将列表中的相对路径转换为可供 QML Image 使用的文件内容 URL。
    Q_INVOKABLE QString fileContentUrl(const QString &path) const;

    // 全屏文本预览使用的分块 URL。远程服务通过 offset/maxBytes 返回后续内容。
    Q_INVOKABLE QString textChunkUrl(const QString &path,
                                     qint64 offset,
                                     qint64 maxBytes) const;

    // PDF/DOCX 预览：返回请求编号，结果通过下面的信号异步返回。
    Q_INVOKABLE int prepareDocument(const QString &path, const QString &extension);
    Q_INVOKABLE void cancelDocumentPreparation();

    // 由 C++ 直接写系统剪贴板，避免复制按钮改变 QML 文本选区。
    Q_INVOKABLE void copyTextToClipboard(const QString &text) const;

signals:
    void serverUrlChanged();
    void fileListUrlChanged();
    void uploadingChanged();
    void loadingFilesChanged();
    void progressChanged();
    void currentFileChanged();
    void statusTextChanged();
    void listStatusChanged();
    void completedCountChanged();
    void totalCountChanged();
    void successCountChanged();
    void failedCountChanged();

    // items 中每项都包含 QML 文件列表使用的角色：name/kind/ext/modified/size/status/iconBg/iconColor/path，
    // 并透传服务端提供的 previewType（image/text/binary）和 mimeType。
    void filesLoaded(const QVariantList &items);
    void filesLoadFailed(const QString &reason);

    void pdfPreviewReady(int requestId, const QString &localUrl, int pageCount);
    void docxPreviewReady(int requestId, const QString &html);
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

    void uploadNext();
    void finishCurrentTask(bool success, const QString &reason = QString());

    void resetDocumentPreparation();
    void prepareLocalDocument(int requestId, const QUrl &sourceUrl);
    void processDownloadedDocument(int requestId);
    void failDocumentPreview(int requestId, const QString &reason);

    void setUploading(bool value);
    void setLoadingFiles(bool value);
    void setProgress(int value);
    void setCurrentFile(const QString &value);
    void setStatusText(const QString &value);
    void setListStatus(const QString &value);
    void setCompletedCount(int value);
    void setTotalCount(int value);
    void setSuccessCount(int value);
    void setFailedCount(int value);
    static QString formatFileSize(qint64 bytes);

    QNetworkAccessManager m_network;
    QQueue<UploadTask> m_queue;
    QNetworkReply *m_reply = nullptr;
    QNetworkReply *m_listReply = nullptr;
    QNetworkReply *m_documentReply = nullptr;
    QTemporaryFile *m_documentFile = nullptr;
    UploadTask m_currentTask;

    int m_documentRequestId = 0;
    QString m_documentExtension;

    QString m_serverUrl = QStringLiteral("http://127.0.0.1:8080/upload");
    QString m_fileListUrl = QStringLiteral("http://127.0.0.1:8080/files");
    QString m_currentFile;
    QString m_statusText;
    QString m_listStatus;
    bool m_uploading = false;
    bool m_loadingFiles = false;
    int m_progress = 0;
    int m_completedCount = 0;
    int m_totalCount = 0;
    int m_successCount = 0;
    int m_failedCount = 0;
    qint64 m_totalBytes = 0;
    qint64 m_completedBytes = 0;
};
