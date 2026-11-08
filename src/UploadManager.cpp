#include "UploadManager.h"

#include "MuPdfRenderer.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

namespace {

QString findLibreOfficeExecutable()
{
    // 可用环境变量覆盖自动探测，便于使用便携版或自定义安装目录。
    const QString configured = qEnvironmentVariable("FILESYNC_LIBREOFFICE").trimmed();
    if (!configured.isEmpty()) {
        const QFileInfo file(configured);
        if (file.isFile() && file.isExecutable())
            return file.absoluteFilePath();

        const QString fromPath = QStandardPaths::findExecutable(configured);
        if (!fromPath.isEmpty())
            return fromPath;
    }

    const QStringList executableNames = {
#if defined(Q_OS_WIN)
        QStringLiteral("soffice.exe"),
        QStringLiteral("libreoffice.exe")
#else
        QStringLiteral("soffice"),
        QStringLiteral("libreoffice")
#endif
    };
    for (const QString &name : executableNames) {
        const QString path = QStandardPaths::findExecutable(name);
        if (!path.isEmpty())
            return path;
    }

    QStringList candidates;
#if defined(Q_OS_WIN)
    const QStringList programDirectories = {
        qEnvironmentVariable("ProgramFiles"),
        qEnvironmentVariable("ProgramFiles(x86)"),
        qEnvironmentVariable("ProgramW6432")
    };
    for (const QString &directory : programDirectories) {
        if (!directory.isEmpty()) {
            candidates.append(QDir(directory).filePath(
                QStringLiteral("LibreOffice/program/soffice.exe")));
        }
    }
#elif defined(Q_OS_MACOS)
    candidates.append(QStringLiteral(
        "/Applications/LibreOffice.app/Contents/MacOS/soffice"));
#endif

    for (const QString &candidate : candidates) {
        const QFileInfo file(candidate);
        if (file.isFile() && file.isExecutable())
            return file.absoluteFilePath();
    }
    return {};
}

QString processOutput(QProcess *process)
{
    QByteArray output = process->readAllStandardError();
    if (output.trimmed().isEmpty())
        output = process->readAllStandardOutput();

    QString text = QString::fromLocal8Bit(output).trimmed();
    // 避免第三方进程的整段日志撑满错误提示区域。
    constexpr int maxMessageLength = 1200;
    if (text.size() > maxMessageLength)
        text = QStringLiteral("…") + text.right(maxMessageLength);
    return text;
}

bool validateFolderName(const QString &folderName, QString *error)
{
    if (folderName.isEmpty()) {
        *error = QStringLiteral("请输入文件夹名称");
        return false;
    }
    if (folderName.size() > 100) {
        *error = QStringLiteral("文件夹名称不能超过 100 个字符");
        return false;
    }
    if (folderName == QStringLiteral(".") || folderName == QStringLiteral("..")) {
        *error = QStringLiteral("文件夹名称不能是“.”或“..”");
        return false;
    }

    const QString invalidCharacters = QStringLiteral("<>:\"/\\|?*");
    for (const QChar ch : folderName) {
        if (ch.unicode() < 32 || invalidCharacters.contains(ch)) {
            *error = QStringLiteral("名称不能包含 < > : \" / \\ | ? * 或控制字符");
            return false;
        }
    }

    // 与 Windows 的命名规则保持一致，避免同步到不同平台后目录不可用。
    if (folderName.endsWith(QLatin1Char('.')) || folderName.endsWith(QLatin1Char(' '))) {
        *error = QStringLiteral("文件夹名称不能以句点或空格结尾");
        return false;
    }

    QString baseName = folderName;
    const int firstDot = baseName.indexOf(QLatin1Char('.'));
    if (firstDot > 0)
        baseName = baseName.left(firstDot);
    baseName = baseName.toUpper();

    const bool reservedDeviceName = baseName == QStringLiteral("CON")
                                    || baseName == QStringLiteral("PRN")
                                    || baseName == QStringLiteral("AUX")
                                    || baseName == QStringLiteral("NUL")
                                    || ((baseName.startsWith(QStringLiteral("COM"))
                                         || baseName.startsWith(QStringLiteral("LPT")))
                                        && baseName.size() == 4
                                        && baseName.at(3) >= QLatin1Char('1')
                                        && baseName.at(3) <= QLatin1Char('9'));
    if (reservedDeviceName) {
        *error = QStringLiteral("该名称是系统保留名称，请更换文件夹名称");
        return false;
    }

    return true;
}

QString displayModified(const QJsonObject &object)
{
    QString value = object.value(QStringLiteral("modified")).toString();
    if (value.isEmpty())
        value = object.value(QStringLiteral("lastModified")).toString();

    if (!value.isEmpty()) {
        const QDateTime isoDate = QDateTime::fromString(value, Qt::ISODateWithMs).isValid()
                                      ? QDateTime::fromString(value, Qt::ISODateWithMs)
                                      : QDateTime::fromString(value, Qt::ISODate);
        return isoDate.isValid()
                   ? isoDate.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"))
                   : value;
    }

    const QJsonValue timestampValue = object.value(QStringLiteral("mtime"));
    if (timestampValue.isDouble()) {
        qint64 timestamp = static_cast<qint64>(timestampValue.toDouble());
        // 同时兼容秒级和毫秒级 Unix 时间戳。
        if (timestamp > 100000000000LL)
            timestamp /= 1000;
        const QDateTime date = QDateTime::fromSecsSinceEpoch(timestamp);
        if (date.isValid())
            return date.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"));
    }

    return QStringLiteral("--");
}

QString fileIconBackground(const QString &extension)
{
    const QString ext = extension.toLower();
    if (ext == QStringLiteral("pdf")) return QStringLiteral("#FFF0EF");
    if (ext == QStringLiteral("doc") || ext == QStringLiteral("docx")) return QStringLiteral("#EAF2FF");
    if (ext == QStringLiteral("xls") || ext == QStringLiteral("xlsx")) return QStringLiteral("#EAF8F2");
    if (ext == QStringLiteral("ppt") || ext == QStringLiteral("pptx")) return QStringLiteral("#FFF0E9");
    if (ext == QStringLiteral("zip") || ext == QStringLiteral("rar")) return QStringLiteral("#FFF5E8");
    return QStringLiteral("#EEF2FF");
}

QString fileIconColor(const QString &extension)
{
    const QString ext = extension.toLower();
    if (ext == QStringLiteral("pdf")) return QStringLiteral("#E47772");
    if (ext == QStringLiteral("doc") || ext == QStringLiteral("docx")) return QStringLiteral("#4C83D9");
    if (ext == QStringLiteral("xls") || ext == QStringLiteral("xlsx")) return QStringLiteral("#28A879");
    if (ext == QStringLiteral("ppt") || ext == QStringLiteral("pptx")) return QStringLiteral("#E58A54");
    if (ext == QStringLiteral("zip") || ext == QStringLiteral("rar")) return QStringLiteral("#D99A42");
    return QStringLiteral("#4B6EF5");
}

QVariantMap makeFileItem(const QJsonObject &object)
{
    QString name = object.value(QStringLiteral("name")).toString();
    QString path = object.value(QStringLiteral("path")).toString();
    if (name.isEmpty() && !path.isEmpty())
        name = QFileInfo(path).fileName();

    QString type = object.value(QStringLiteral("kind")).toString();
    if (type.isEmpty())
        type = object.value(QStringLiteral("type")).toString();
    const QString typeLower = type.toLower();
    const bool isDirectory = object.value(QStringLiteral("isDirectory")).toBool(false)
                             || typeLower == QStringLiteral("folder")
                             || typeLower == QStringLiteral("directory")
                             || typeLower == QStringLiteral("dir");

    QString extension = object.value(QStringLiteral("ext")).toString();
    if (isDirectory) {
        extension = QStringLiteral("文件夹");
    } else if (extension.isEmpty()) {
        extension = QFileInfo(name).suffix().toUpper();
        if (extension.isEmpty())
            extension = QStringLiteral("FILE");
    } else {
        extension = extension.toUpper();
    }

    QString sizeText;
    const QJsonValue sizeValue = object.value(QStringLiteral("size"));
    if (isDirectory) {
        const QJsonValue countValue = object.value(QStringLiteral("fileCount"));
        if (countValue.isDouble())
            sizeText = QStringLiteral("%1 个文件").arg(countValue.toInt());
        else if (countValue.isString() && !countValue.toString().isEmpty())
            sizeText = countValue.toString();
        else if (sizeValue.isString() && !sizeValue.toString().isEmpty())
            sizeText = sizeValue.toString();
        else
            sizeText = QStringLiteral("文件夹");
    } else if (sizeValue.isDouble()) {
        const qint64 bytes = static_cast<qint64>(sizeValue.toDouble());
        if (bytes < 1024)
            sizeText = QStringLiteral("%1 B").arg(bytes);
        else if (bytes < 1024 * 1024)
            sizeText = QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
        else if (bytes < 1024LL * 1024LL * 1024LL)
            sizeText = QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
        else
            sizeText = QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
    } else {
        sizeText = sizeValue.toString(QStringLiteral("--"));
    }

    const QString modified = displayModified(object);
    const QString status = object.value(QStringLiteral("status")).toString(
        QStringLiteral("已同步"));

    QVariantMap item;
    item.insert(QStringLiteral("name"), name);
    item.insert(QStringLiteral("kind"), isDirectory ? QStringLiteral("folder")
                                                    : QStringLiteral("file"));
    item.insert(QStringLiteral("ext"), extension);
    item.insert(QStringLiteral("modified"), modified);
    item.insert(QStringLiteral("size"), sizeText);
    item.insert(QStringLiteral("status"), status);
    item.insert(QStringLiteral("iconBg"), isDirectory ? QStringLiteral("#FFF5E3")
                                                      : fileIconBackground(extension));
    item.insert(QStringLiteral("iconColor"), isDirectory ? QStringLiteral("#E9AD4E")
                                                         : fileIconColor(extension));
    item.insert(QStringLiteral("path"), path.isEmpty() ? name : path);
    item.insert(QStringLiteral("previewType"), object.value(QStringLiteral("previewType")).toString());
    item.insert(QStringLiteral("mimeType"), object.value(QStringLiteral("mimeType")).toString());
    return item;
}

} // namespace

UploadManager::UploadManager(QObject *parent)
    : QObject(parent)
    , m_network()
{
}

UploadManager::~UploadManager()
{
    resetDocumentPreparation();
}

QString UploadManager::serverUrl() const { return m_serverUrl; }
bool UploadManager::uploading() const { return m_uploading; }
bool UploadManager::loadingFiles() const { return m_loadingFiles; }
bool UploadManager::creatingFolder() const { return m_creatingFolder; }
int UploadManager::progress() const { return m_progress; }
QString UploadManager::currentFile() const { return m_currentFile; }
QString UploadManager::statusText() const { return m_statusText; }
QString UploadManager::listStatus() const { return m_listStatus; }
int UploadManager::completedCount() const { return m_completedCount; }
int UploadManager::totalCount() const { return m_totalCount; }
int UploadManager::successCount() const { return m_successCount; }
int UploadManager::failedCount() const { return m_failedCount; }
QString UploadManager::fileListUrl() const { return m_fileListUrl; }

void UploadManager::setServerUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_serverUrl == trimmed)
        return;
    m_serverUrl = trimmed;
    emit serverUrlChanged();
}

void UploadManager::setFileListUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_fileListUrl == trimmed)
        return;
    m_fileListUrl = trimmed;
    emit fileListUrlChanged();
}

void UploadManager::loadFiles()
{
    if (m_loadingFiles)
        return;

    const QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件列表地址无效：请填写 http 或 https 地址");
        setListStatus(reason);
        emit filesLoadFailed(reason);
        return;
    }

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setTransferTimeout(30000);

    setLoadingFiles(true);
    setListStatus(QStringLiteral("正在从服务器加载文件列表…"));
    m_listReply = m_network.get(request);

    connect(m_listReply, &QNetworkReply::finished, this, [this]() {
        if (!m_listReply)
            return;

        QNetworkReply *reply = m_listReply;
        m_listReply = nullptr;
        const QByteArray body = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        QString error;
        if (reply->error() != QNetworkReply::NoError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = reply->errorString();
            if (httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        }
        reply->deleteLater();

        if (!error.isEmpty()) {
            setLoadingFiles(false);
            setListStatus(QStringLiteral("文件列表加载失败：%1").arg(error));
            emit filesLoadFailed(error);
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            error = QStringLiteral("服务器返回的文件列表不是有效 JSON 对象");
            setLoadingFiles(false);
            setListStatus(error);
            emit filesLoadFailed(error);
            return;
        }

        const QJsonObject rootObject = document.object();
        if (rootObject.contains(QStringLiteral("success"))
            && !rootObject.value(QStringLiteral("success")).toBool()) {
            error = rootObject.value(QStringLiteral("message")).toString(
                QStringLiteral("服务器未能返回文件列表"));
            setLoadingFiles(false);
            setListStatus(error);
            emit filesLoadFailed(error);
            return;
        }

        // 兼容两种响应：{ "items": [...] } 或 { "files": [...], "directories": [...] }。
        // 也兼容将列表放在 data 对象中的形式。
        QJsonObject listObject = rootObject;
        if (rootObject.value(QStringLiteral("data")).isObject())
            listObject = rootObject.value(QStringLiteral("data")).toObject();

        QJsonArray entries;
        bool hasList = false;
        if (listObject.value(QStringLiteral("items")).isArray()) {
            entries = listObject.value(QStringLiteral("items")).toArray();
            hasList = true;
        } else {
            if (listObject.value(QStringLiteral("directories")).isArray()) {
                const QJsonArray directories = listObject.value(QStringLiteral("directories")).toArray();
                for (const QJsonValue &value : directories)
                    entries.append(value);
                hasList = true;
            }
            if (listObject.value(QStringLiteral("files")).isArray()) {
                const QJsonArray files = listObject.value(QStringLiteral("files")).toArray();
                for (const QJsonValue &value : files)
                    entries.append(value);
                hasList = true;
            }
        }

        if (!hasList) {
            error = QStringLiteral("文件列表响应缺少 items 数组，或 files/directories 数组");
            setLoadingFiles(false);
            setListStatus(error);
            emit filesLoadFailed(error);
            return;
        }

        QVariantList items;
        items.reserve(entries.size());
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;
            QVariantMap item = makeFileItem(value.toObject());
            if (!item.value(QStringLiteral("name")).toString().isEmpty())
                items.append(item);
        }

        setLoadingFiles(false);
        setListStatus(QStringLiteral("加载完成，共 %1 个文件/目录").arg(items.size()));
        emit filesLoaded(items);
    });
}

void UploadManager::createFolder(const QString &folderName)
{
    const QString name = folderName.trimmed();
    if (m_creatingFolder) {
        setListStatus(QStringLiteral("正在创建其他文件夹，请稍后再试"));
        return;
    }

    QString validationError;
    if (!validateFolderName(name, &validationError)) {
        setListStatus(QStringLiteral("新建文件夹失败：%1").arg(validationError));
        emit folderCreationFailed(name, validationError);
        return;
    }

    // 与文件内容 URL 的推导方式一致：将 /files 映射为同级的 /folders。
    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setListStatus(reason);
        emit folderCreationFailed(name, reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("folders"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    request.setTransferTimeout(30000);

    const QJsonObject payload{
        {QStringLiteral("name"), name}
    };

    setCreatingFolder(true);
    setListStatus(QStringLiteral("正在新建文件夹：%1").arg(name));
    m_folderReply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));

    connect(m_folderReply, &QNetworkReply::finished, this, [this, name]() {
        if (!m_folderReply)
            return;

        QNetworkReply *reply = m_folderReply;
        m_folderReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString networkError = reply->errorString();
        const bool hasNetworkError = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(responseBody, &parseError);
        const bool hasJsonObject = parseError.error == QJsonParseError::NoError
                                   && document.isObject();
        const QJsonObject responseObject = hasJsonObject ? document.object() : QJsonObject();
        const QString serverMessage = responseObject.value(QStringLiteral("message")).toString();

        QString error;
        if (hasNetworkError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = serverMessage.isEmpty() ? networkError : serverMessage;
            if (error.trimmed().isEmpty())
                error = QStringLiteral("服务器返回异常响应");
            if (serverMessage.isEmpty() && httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        } else if (!responseBody.isEmpty() && !hasJsonObject) {
            error = QStringLiteral("服务器返回的新建文件夹结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能创建文件夹") : serverMessage;
        }

        if (!error.isEmpty()) {
            setCreatingFolder(false);
            setListStatus(QStringLiteral("新建文件夹失败：%1").arg(error));
            emit folderCreationFailed(name, error);
            return;
        }

        const QJsonObject folderObject = responseObject.value(QStringLiteral("folder")).toObject();
        const QString actualName = folderObject.value(QStringLiteral("name")).toString(name);
        const QString folderPath = folderObject.value(QStringLiteral("path")).toString(
            responseObject.value(QStringLiteral("path")).toString(actualName));

        QString modifiedText = displayModified(folderObject);
        if (modifiedText == QStringLiteral("--"))
            modifiedText = displayModified(responseObject);
        if (modifiedText == QStringLiteral("--")) {
            modifiedText = QDateTime::currentDateTime().toString(
                QStringLiteral("yyyy-MM-dd HH:mm"));
        }

        setCreatingFolder(false);
        setListStatus(QStringLiteral("文件夹“%1”创建成功").arg(actualName));
        emit folderCreated(actualName, folderPath, modifiedText);
    });
}

QString UploadManager::fileContentUrl(const QString &path) const
{
    const QString value = path.trimmed();
    if (value.isEmpty())
        return QString();

    // 已完整给出的网络、资源或本地文件 URL 可直接使用。
    const QUrl directUrl(value);
    const QString scheme = directUrl.scheme().toLower();
    if (directUrl.isValid()
        && (scheme == QStringLiteral("http")
            || scheme == QStringLiteral("https")
            || scheme == QStringLiteral("file")
            || scheme == QStringLiteral("qrc"))) {
        return directUrl.toString(QUrl::FullyEncoded);
    }

    // 也支持外部模型直接传入本机绝对路径。
    if (QDir::isAbsolutePath(value) && QFileInfo(value).isFile())
        return QUrl::fromLocalFile(value).toString(QUrl::FullyEncoded);

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        return QString();
    }

    // 默认将 /files 映射为 /file，并保留可能存在的 API 路径前缀。
    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("file"));
    endpoint.setFragment(QString());

    QUrlQuery query;
    query.addQueryItem(QStringLiteral("path"), value);
    endpoint.setQuery(query);
    return endpoint.toString(QUrl::FullyEncoded);
}

QString UploadManager::textChunkUrl(const QString &path,
                                    qint64 offset,
                                    qint64 maxBytes) const
{
    QUrl url(fileContentUrl(path));
    if (!url.isValid())
        return {};

    const QString scheme = url.scheme().toLower();
    if (scheme != QStringLiteral("http") && scheme != QStringLiteral("https"))
        return url.toString(QUrl::FullyEncoded);

    QUrlQuery query(url);
    query.addQueryItem(QStringLiteral("offset"), QString::number(qMax<qint64>(0, offset)));
    query.addQueryItem(QStringLiteral("maxBytes"),
                       QString::number(qBound<qint64>(1, maxBytes, 1024LL * 1024LL)));
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

int UploadManager::prepareDocument(const QString &path, const QString &extension)
{
    cancelDocumentPreparation();
    const int requestId = m_documentRequestId;
    m_documentExtension = extension.toLower();
    if (m_documentExtension.startsWith(QLatin1Char('.')))
        m_documentExtension.remove(0, 1);

    const QUrl sourceUrl(fileContentUrl(path));
    const QString scheme = sourceUrl.scheme().toLower();
    const bool supported = m_documentExtension == QStringLiteral("pdf")
                           || m_documentExtension == QStringLiteral("docx");

    if (!supported || !sourceUrl.isValid() || scheme.isEmpty()) {
        const QString reason = !supported
            ? QStringLiteral("仅支持 PDF 和 DOCX 文档预览")
            : QStringLiteral("文档地址无效");
        QTimer::singleShot(0, this, [this, requestId, reason]() {
            failDocumentPreview(requestId, reason);
        });
        return requestId;
    }

    if (scheme == QStringLiteral("file") || scheme == QStringLiteral("qrc")) {
        QTimer::singleShot(0, this, [this, requestId, sourceUrl]() {
            if (requestId == m_documentRequestId)
                prepareLocalDocument(requestId, sourceUrl);
        });
        return requestId;
    }

    if (scheme != QStringLiteral("http") && scheme != QStringLiteral("https")) {
        const QString reason = QStringLiteral("不支持此文档地址协议：%1").arg(scheme);
        QTimer::singleShot(0, this, [this, requestId, reason]() {
            failDocumentPreview(requestId, reason);
        });
        return requestId;
    }

    const QString temporaryPattern = QDir(QDir::tempPath()).filePath(
        QStringLiteral("FileSyncPreview_XXXXXX.%1").arg(m_documentExtension));
    m_documentFile = new QTemporaryFile(temporaryPattern, this);
    if (!m_documentFile->open()) {
        const QString reason = QStringLiteral("无法创建文档预览临时文件");
        QTimer::singleShot(0, this, [this, requestId, reason]() {
            failDocumentPreview(requestId, reason);
        });
        return requestId;
    }

    QNetworkRequest request(sourceUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/octet-stream"));
    request.setTransferTimeout(120000);

    QNetworkReply *reply = m_network.get(request);
    m_documentReply = reply;

    connect(reply, &QIODevice::readyRead, this,
            [this, requestId, reply]() {
        if (requestId != m_documentRequestId || reply != m_documentReply)
            return;

        const QByteArray data = reply->readAll();
        if (!data.isEmpty()
            && (!m_documentFile || m_documentFile->write(data) != data.size())) {
            failDocumentPreview(requestId, QStringLiteral("写入文档预览临时文件失败"));
        }
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, requestId, reply]() {
        if (requestId != m_documentRequestId || reply != m_documentReply)
            return; // resetDocumentPreparation() 已负责释放旧 reply。

        m_documentReply = nullptr;
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QString error;
        if (reply->error() != QNetworkReply::NoError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = reply->errorString();
            if (httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        }

        const QByteArray remainingData = reply->readAll();
        reply->deleteLater();

        if (!error.isEmpty()) {
            failDocumentPreview(requestId,
                                QStringLiteral("文档下载失败：%1").arg(error));
            return;
        }
        if (!remainingData.isEmpty()
            && (!m_documentFile || m_documentFile->write(remainingData) != remainingData.size())) {
            failDocumentPreview(requestId, QStringLiteral("写入文档预览临时文件失败"));
            return;
        }
        if (!m_documentFile || !m_documentFile->flush()) {
            failDocumentPreview(requestId, QStringLiteral("文档预览临时文件写入不完整"));
            return;
        }

        m_documentFile->close();
        processDownloadedDocument(requestId);
    });

    return requestId;
}

void UploadManager::prepareLocalDocument(int requestId, const QUrl &sourceUrl)
{
    if (requestId != m_documentRequestId)
        return;

    if (sourceUrl.isLocalFile()) {
        const QFileInfo info(sourceUrl.toLocalFile());
        if (!info.exists() || !info.isFile() || !info.isReadable()) {
            failDocumentPreview(requestId, QStringLiteral("本地文档不存在或无法读取"));
            return;
        }

        if (m_documentExtension == QStringLiteral("pdf"))
            showPdfPreview(requestId, info.absoluteFilePath());
        else
            convertDocxToPdf(requestId, info.absoluteFilePath());
        return;
    }

    if (sourceUrl.scheme().toLower() != QStringLiteral("qrc")) {
        failDocumentPreview(requestId, QStringLiteral("本地文档地址无效"));
        return;
    }

    QFile resourceFile(QStringLiteral(":") + sourceUrl.path());
    if (!resourceFile.open(QIODevice::ReadOnly)) {
        failDocumentPreview(requestId, QStringLiteral("无法读取资源文档"));
        return;
    }

    const QString temporaryPattern = QDir(QDir::tempPath()).filePath(
        QStringLiteral("FileSyncPreview_XXXXXX.%1").arg(m_documentExtension));
    m_documentFile = new QTemporaryFile(temporaryPattern, this);
    if (!m_documentFile->open()) {
        failDocumentPreview(requestId, QStringLiteral("无法创建文档预览临时文件"));
        return;
    }

    while (!resourceFile.atEnd()) {
        const QByteArray data = resourceFile.read(64 * 1024);
        if (!data.isEmpty() && m_documentFile->write(data) != data.size()) {
            failDocumentPreview(requestId, QStringLiteral("写入文档预览临时文件失败"));
            return;
        }
    }
    m_documentFile->close();
    processDownloadedDocument(requestId);
}

void UploadManager::processDownloadedDocument(int requestId)
{
    if (requestId != m_documentRequestId)
        return;
    if (!m_documentFile) {
        failDocumentPreview(requestId, QStringLiteral("文档预览临时文件不存在"));
        return;
    }

    const QString filePath = m_documentFile->fileName();
    if (m_documentExtension == QStringLiteral("pdf"))
        showPdfPreview(requestId, filePath);
    else
        convertDocxToPdf(requestId, filePath);
}

void UploadManager::convertDocxToPdf(int requestId, const QString &sourcePath)
{
    if (requestId != m_documentRequestId)
        return;

    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() || !sourceInfo.isFile() || !sourceInfo.isReadable()) {
        failDocumentPreview(requestId, QStringLiteral("DOCX 文件不存在或无法读取"));
        return;
    }

    const QString executable = findLibreOfficeExecutable();
    if (executable.isEmpty()) {
        failDocumentPreview(
            requestId,
            QStringLiteral("未找到 LibreOffice，无法将 DOCX 转换为 PDF。"
                           "请安装 LibreOffice 并将 soffice 加入 PATH，或通过 "
                           "FILESYNC_LIBREOFFICE 环境变量指定其可执行文件。"));
        return;
    }

    delete m_documentWorkspace;
    m_documentWorkspace = new QTemporaryDir(
        QDir(QDir::tempPath()).filePath(QStringLiteral("FileSyncDocx_XXXXXX")));
    if (!m_documentWorkspace->isValid()) {
        failDocumentPreview(requestId, QStringLiteral("无法创建 DOCX 转换临时目录"));
        return;
    }

    // 使用固定的 ASCII 文件名，规避部分 LibreOffice 版本对随机名或中文路径的兼容问题。
    const QString inputPath = m_documentWorkspace->filePath(QStringLiteral("document.docx"));
    const QString outputPath = m_documentWorkspace->filePath(QStringLiteral("document.pdf"));
    if (!QFile::copy(sourceInfo.absoluteFilePath(), inputPath)) {
        failDocumentPreview(requestId, QStringLiteral("无法复制 DOCX 到转换临时目录"));
        return;
    }

    // 下载用的源文件已经复制到工作目录，可提前释放；输出 PDF 会继续保留到关闭预览。
    delete m_documentFile;
    m_documentFile = nullptr;

    const QString profileUrl = QUrl::fromLocalFile(
        m_documentWorkspace->filePath(QStringLiteral("libreoffice-profile")))
        .toString(QUrl::FullyEncoded);

    auto *process = new QProcess(this);
    m_documentConverter = process;
    process->setProgram(executable);
    process->setWorkingDirectory(m_documentWorkspace->path());
    process->setProcessChannelMode(QProcess::SeparateChannels);
    process->setArguments({
        QStringLiteral("-env:UserInstallation=") + profileUrl,
        QStringLiteral("--headless"),
        QStringLiteral("--nologo"),
        QStringLiteral("--nodefault"),
        QStringLiteral("--nofirststartwizard"),
        QStringLiteral("--norestore"),
        QStringLiteral("--nolockcheck"),
        QStringLiteral("--convert-to"),
        QStringLiteral("pdf:writer_pdf_Export"),
        QStringLiteral("--outdir"),
        m_documentWorkspace->path(),
        inputPath
    });

    connect(process, &QProcess::errorOccurred, this,
            [this, requestId, process](QProcess::ProcessError error) {
        if (requestId != m_documentRequestId || process != m_documentConverter)
            return;
        if (error == QProcess::FailedToStart) {
            failDocumentPreview(requestId,
                                QStringLiteral("无法启动 LibreOffice：%1")
                                    .arg(process->errorString()));
        }
    });

    connect(process, &QProcess::finished, this,
            [this, requestId, process, inputPath, outputPath](
                int exitCode, QProcess::ExitStatus exitStatus) {
        if (requestId != m_documentRequestId || process != m_documentConverter)
            return;

        const QString details = processOutput(process);
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            QString reason = QStringLiteral("DOCX 转 PDF 失败（退出码 %1）").arg(exitCode);
            if (!details.isEmpty())
                reason += QStringLiteral("：") + details;
            failDocumentPreview(requestId, reason);
            return;
        }

        const QFileInfo outputInfo(outputPath);
        if (!outputInfo.exists() || !outputInfo.isFile() || outputInfo.size() <= 0) {
            QString reason = QStringLiteral(
                "LibreOffice 已结束，但没有生成有效的 PDF 文件");
            if (!details.isEmpty())
                reason += QStringLiteral("：") + details;
            failDocumentPreview(requestId, reason);
            return;
        }

        m_documentConverter = nullptr;
        process->deleteLater();
        QFile::remove(inputPath);
        showPdfPreview(requestId, outputInfo.absoluteFilePath());
    });

    // 大文档转换可能耗时较长，但不能无限挂起；上下文为 process，进程销毁后定时器自动失效。
    QTimer::singleShot(180000, process, [this, requestId, process]() {
        if (requestId == m_documentRequestId && process == m_documentConverter) {
            failDocumentPreview(requestId,
                                QStringLiteral("DOCX 转 PDF 超过 180 秒，已取消转换"));
        }
    });

    process->start();
}

void UploadManager::showPdfPreview(int requestId, const QString &filePath)
{
    if (requestId != m_documentRequestId)
        return;

    QString error;
    const int pageCount = MuPdfRenderer::pageCount(filePath, &error);
    if (pageCount <= 0 || !error.isEmpty()) {
        failDocumentPreview(requestId,
                            error.isEmpty() ? QStringLiteral("PDF 中没有可显示的页面")
                                            : error);
        return;
    }

    // 下载的 PDF 或 DOCX 转换工作目录均由 UploadManager 持有，确保按需翻页时文件仍存在。
    emit pdfPreviewReady(requestId,
                         QUrl::fromLocalFile(filePath).toString(QUrl::FullyEncoded),
                         pageCount);
}

void UploadManager::cancelDocumentPreparation()
{
    ++m_documentRequestId;
    resetDocumentPreparation();
}

void UploadManager::resetDocumentPreparation()
{
    if (m_documentReply) {
        QNetworkReply *reply = m_documentReply;
        m_documentReply = nullptr;
        reply->abort();
        reply->deleteLater();
    }

    if (m_documentConverter) {
        QProcess *process = m_documentConverter;
        m_documentConverter = nullptr;
        disconnect(process, nullptr, this, nullptr);
        if (process->state() != QProcess::NotRunning) {
            process->kill();
            // 等待进程释放工作目录中的文件锁，避免 Windows 下临时目录清理失败。
            process->waitForFinished(1500);
        }
        process->deleteLater();
    }

    delete m_documentFile;
    m_documentFile = nullptr;
    delete m_documentWorkspace;
    m_documentWorkspace = nullptr;
    m_documentExtension.clear();
    MuPdfRenderer::clearCache();
}

void UploadManager::failDocumentPreview(int requestId, const QString &reason)
{
    if (requestId != m_documentRequestId)
        return;
    resetDocumentPreparation();
    emit documentPreviewFailed(requestId, reason);
}

void UploadManager::copyTextToClipboard(const QString &text) const
{
    if (QClipboard *clipboard = QGuiApplication::clipboard())
        clipboard->setText(text);
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
    const QByteArray disposition = QByteArrayLiteral("form-data; name=\"file\"; filename=\"")
                                   + fallbackName
                                   + QByteArrayLiteral("\"; filename*=UTF-8''")
                                   + encodedName;

    filePart.setRawHeader(QByteArrayLiteral("Content-Disposition"), disposition);
    filePart.setRawHeader(QByteArrayLiteral("Content-Type"),
                          QByteArrayLiteral("application/octet-stream"));
    filePart.setBodyDevice(file);
    multiPart->append(filePart);

    QNetworkRequest request{QUrl(m_serverUrl)};
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setTransferTimeout(120000);

    m_reply = m_network.post(request, multiPart);
    multiPart->setParent(m_reply);

    connect(m_reply, &QNetworkReply::uploadProgress, this,
            [this](qint64 sent, qint64 /* total */) {
        if (m_totalBytes > 0) {
            const qint64 currentSent = qBound<qint64>(0, sent, m_currentTask.size);
            const qint64 allSent = qMin(m_totalBytes, m_completedBytes + currentSent);
            setProgress(static_cast<int>((allSent * 100) / m_totalBytes));
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

    QTimer::singleShot(0, this, [this]() { uploadNext(); });
}

void UploadManager::setUploading(bool value)
{
    if (m_uploading == value)
        return;
    m_uploading = value;
    emit uploadingChanged();
}

void UploadManager::setLoadingFiles(bool value)
{
    if (m_loadingFiles == value)
        return;
    m_loadingFiles = value;
    emit loadingFilesChanged();
}

void UploadManager::setCreatingFolder(bool value)
{
    if (m_creatingFolder == value)
        return;
    m_creatingFolder = value;
    emit creatingFolderChanged();
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

void UploadManager::setListStatus(const QString &value)
{
    if (m_listStatus == value)
        return;
    m_listStatus = value;
    emit listStatusChanged();
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
