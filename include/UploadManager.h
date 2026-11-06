#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QQueue>
#include <QVariantList>

class QNetworkReply;

/**
 * FileSync 文件上传控制器。
 *
 * 上传协议：POST multipart/form-data，文件字段名为 file。
 * 默认测试接口：http://127.0.0.1:8080/upload
 */
class UploadManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadingChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString currentFile READ currentFile NOTIFY currentFileChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(int completedCount READ completedCount NOTIFY completedCountChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int successCount READ successCount NOTIFY successCountChanged)
    Q_PROPERTY(int failedCount READ failedCount NOTIFY failedCountChanged)

public:
    explicit UploadManager(QObject *parent = nullptr);

    QString serverUrl() const;
    void setServerUrl(const QString &url);

    bool uploading() const;
    int progress() const;
    QString currentFile() const;
    QString statusText() const;
    int completedCount() const;
    int totalCount() const;
    int successCount() const;
    int failedCount() const;

    // 接收 QtQuick.Dialogs FileDialog.selectedFiles（QUrl 列表）。
    Q_INVOKABLE void uploadFiles(const QVariantList &selectedFiles);

signals:
    void serverUrlChanged();
    void uploadingChanged();
    void progressChanged();
    void currentFileChanged();
    void statusTextChanged();
    void completedCountChanged();
    void totalCountChanged();
    void successCountChanged();
    void failedCountChanged();

    // 上传成功后由 QML 插入文件列表。
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
    void setUploading(bool value);
    void setProgress(int value);
    void setCurrentFile(const QString &value);
    void setStatusText(const QString &value);
    void setCompletedCount(int value);
    void setTotalCount(int value);
    void setSuccessCount(int value);
    void setFailedCount(int value);
    static QString formatFileSize(qint64 bytes);

    QNetworkAccessManager m_network;
    QQueue<UploadTask> m_queue;
    QNetworkReply *m_reply = nullptr;
    UploadTask m_currentTask;

    QString m_serverUrl = QStringLiteral("http://127.0.0.1:8080/upload");
    QString m_currentFile;
    QString m_statusText;
    bool m_uploading = false;
    int m_progress = 0;
    int m_completedCount = 0;
    int m_totalCount = 0;
    int m_successCount = 0;
    int m_failedCount = 0;
    qint64 m_totalBytes = 0;
    qint64 m_completedBytes = 0;
};
