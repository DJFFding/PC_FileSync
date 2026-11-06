#include "UploadManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QTimer>

UploadManager::UploadManager(QObject *parent)
    : QObject(parent)
    , m_network()
{
}

QString UploadManager::serverUrl() const { return m_serverUrl; }
bool UploadManager::uploading() const { return m_uploading; }
int UploadManager::progress() const { return m_progress; }
QString UploadManager::currentFile() const { return m_currentFile; }
QString UploadManager::statusText() const { return m_statusText; }
int UploadManager::completedCount() const { return m_completedCount; }
int UploadManager::totalCount() const { return m_totalCount; }
int UploadManager::successCount() const { return m_successCount; }
int UploadManager::failedCount() const { return m_failedCount; }

void UploadManager::setServerUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_serverUrl == trimmed)
        return;

    m_serverUrl = trimmed;
    emit serverUrlChanged();
}

void UploadManager::uploadFiles(const QVariantList &selectedFiles)
{
    if (m_uploading) {
        setStatusText(QStringLiteral("当前有上传任务正在进行，请稍后再试"));
        return;
    }

    const QUrl endpoint(m_serverUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        setStatusText(QStringLiteral("上传地址无效：请填写 http 或 https 地址"));
        emit fileUploadFailed(QString(), m_statusText);
        return;
    }

    m_queue.clear();
    m_totalBytes = 0;
    m_completedBytes = 0;
    setCompletedCount(0);
    setTotalCount(0);
    setSuccessCount(0);
    setFailedCount(0);
    setProgress(0);

    int rejectedCount = 0;
    for (const QVariant &value : selectedFiles) {
        QString path;
        if (value.canConvert<QUrl>()) {
            const QUrl url = value.toUrl();
            path = url.isLocalFile() ? url.toLocalFile() : value.toString();
        } else {
            path = value.toString();
            const QUrl url(path);
            if (url.isLocalFile())
                path = url.toLocalFile();
        }

        path = QDir::cleanPath(path);
        const QFileInfo info(path);
        if (!info.exists() || !info.isFile() || !info.isReadable()) {
            ++rejectedCount;
            emit fileUploadFailed(info.fileName().isEmpty() ? path : info.fileName(),
                                  QStringLiteral("文件不存在或无法读取"));
            continue;
        }

        UploadTask task;
        task.path = info.absoluteFilePath();
        task.fileName = info.fileName();
        task.size = info.size();
        m_queue.enqueue(task);
        m_totalBytes += task.size;
    }

    setFailedCount(rejectedCount);
    setCompletedCount(rejectedCount);
    setTotalCount(m_queue.size() + rejectedCount);
    if (m_queue.isEmpty()) {
        setProgress(100);
        if (rejectedCount > 0) {
            setStatusText(QStringLiteral("上传结束：成功 0 个，失败 %1 个").arg(rejectedCount));
            emit uploadFinished(0, rejectedCount);
        } else {
            setStatusText(QStringLiteral("未选择文件"));
        }
        return;
    }

    setUploading(true);
    setStatusText(QStringLiteral("准备上传 %1 个文件").arg(m_totalCount));
    uploadNext();
}

void UploadManager::uploadNext()
{
    if (m_queue.isEmpty()) {
        setProgress(100);
        setUploading(false);
        setCurrentFile(QString());
        setStatusText(QStringLiteral("上传完成：成功 %1 个，失败 %2 个")
                          .arg(m_successCount)
                          .arg(m_failedCount));
        emit uploadFinished(m_successCount, m_failedCount);
        return;
    }

    m_currentTask = m_queue.dequeue();
    setCurrentFile(m_currentTask.fileName);
    setStatusText(QStringLiteral("正在上传：%1").arg(m_currentTask.fileName));

    auto *file = new QFile(m_currentTask.path);
    if (!file->open(QIODevice::ReadOnly)) {
        delete file;
        finishCurrentTask(false, QStringLiteral("无法打开本地文件"));
        return;
    }

    auto *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    file->setParent(multiPart);

    QHttpPart filePart;
    QByteArray fallbackName = m_currentTask.fileName.toLatin1();
    bool hasNonAscii = false;
    for (const QChar ch : m_currentTask.fileName) {
        if (ch.unicode() > 0x7f) {
            hasNonAscii = true;
            break;
        }
    }
    if (fallbackName.isEmpty() || hasNonAscii
        || fallbackName.contains('"')
        || fallbackName.contains('\\')
        || fallbackName.contains('/')) {
        fallbackName = QByteArrayLiteral("upload.bin");
    }

    const QByteArray encodedName = QUrl::toPercentEncoding(m_currentTask.fileName);
    QByteArray disposition = QByteArrayLiteral("form-data; name=\"file\"; filename=\"")
                             + fallbackName
                             + QByteArrayLiteral("\"; filename*=UTF-8''")
                             + encodedName;

    filePart.setRawHeader(QByteArrayLiteral("Content-Disposition"), disposition);
    filePart.setRawHeader(QByteArrayLiteral("Content-Type"),
                          QByteArrayLiteral("application/octet-stream"));
    filePart.setBodyDevice(file);
    multiPart->append(filePart);
    QUrl url(m_serverUrl);
    QNetworkRequest request(m_serverUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setTransferTimeout(120000); // 本地测试及大文件上传预留 120 秒超时。

    m_reply = m_network.post(request, multiPart);
    multiPart->setParent(m_reply);

    connect(m_reply, &QNetworkReply::uploadProgress, this,
            [this](qint64 sent, qint64 /* total */) {
        if (m_totalBytes > 0) {
            const qint64 currentSent = qBound<qint64>(0, sent, m_currentTask.size);
            const qint64 allSent = qMin(m_totalBytes, m_completedBytes + currentSent);
            const int value = static_cast<int>((allSent * 100) / m_totalBytes);
            setProgress(value);
        } else if (m_totalCount > 0) {
            setProgress(m_completedCount * 100 / m_totalCount);
        }
    });

    connect(m_reply, &QNetworkReply::finished, this, [this]() {
        if (!m_reply)
            return;

        QNetworkReply *reply = m_reply;
        m_reply = nullptr;

        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        bool success = reply->error() == QNetworkReply::NoError
                       && httpStatus >= 200 && httpStatus < 300;
        QString reason;

        if (!success) {
            reason = reply->errorString();
            if (httpStatus > 0)
                reason = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(reason);
            if (reason.trimmed().isEmpty())
                reason = QStringLiteral("服务器返回异常响应");
        } else if (!responseBody.isEmpty()) {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(responseBody, &parseError);
            if (parseError.error == QJsonParseError::NoError && document.isObject()) {
                const QJsonObject object = document.object();
                if (object.contains(QStringLiteral("success"))
                    && !object.value(QStringLiteral("success")).toBool()) {
                    success = false;
                    reason = object.value(QStringLiteral("message")).toString(
                        QStringLiteral("服务器未接受该文件"));
                }
            }
        }

        reply->deleteLater();
        finishCurrentTask(success, reason);
    });
}

void UploadManager::finishCurrentTask(bool success, const QString &reason)
{
    if (success) {
        setSuccessCount(m_successCount + 1);
        emit fileUploaded(m_currentTask.fileName,
                          formatFileSize(m_currentTask.size),
                          QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm")));
    } else {
        setFailedCount(m_failedCount + 1);
        emit fileUploadFailed(m_currentTask.fileName, reason);
    }

    m_completedBytes += m_currentTask.size;
    setCompletedCount(m_completedCount + 1);

    if (m_totalBytes > 0) {
        const int value = static_cast<int>((qMin(m_completedBytes, m_totalBytes) * 100)
                                           / m_totalBytes);
        setProgress(value);
    } else if (m_totalCount > 0) {
        setProgress(m_completedCount * 100 / m_totalCount);
    }

    // 文件逐个上传；失败的文件不会阻断后续任务。
    QTimer::singleShot(0, this, [this]() { uploadNext(); });
}

void UploadManager::setUploading(bool value)
{
    if (m_uploading == value)
        return;
    m_uploading = value;
    emit uploadingChanged();
}

void UploadManager::setProgress(int value)
{
    value = qBound(0, value, 100);
    if (m_progress == value)
        return;
    m_progress = value;
    emit progressChanged();
}

void UploadManager::setCurrentFile(const QString &value)
{
    if (m_currentFile == value)
        return;
    m_currentFile = value;
    emit currentFileChanged();
}

void UploadManager::setStatusText(const QString &value)
{
    if (m_statusText == value)
        return;
    m_statusText = value;
    emit statusTextChanged();
}

void UploadManager::setCompletedCount(int value)
{
    if (m_completedCount == value)
        return;
    m_completedCount = value;
    emit completedCountChanged();
}

void UploadManager::setTotalCount(int value)
{
    if (m_totalCount == value)
        return;
    m_totalCount = value;
    emit totalCountChanged();
}

void UploadManager::setSuccessCount(int value)
{
    if (m_successCount == value)
        return;
    m_successCount = value;
    emit successCountChanged();
}

void UploadManager::setFailedCount(int value)
{
    if (m_failedCount == value)
        return;
    m_failedCount = value;
    emit failedCountChanged();
}

QString UploadManager::formatFileSize(qint64 bytes)
{
    if (bytes < 1024)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1024 * 1024)
        return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < 1024LL * 1024LL * 1024LL)
        return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}
