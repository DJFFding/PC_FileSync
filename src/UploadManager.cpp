#include "UploadManager.h"

#include "MuPdfRenderer.h"

#include <QClipboard>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHttpMultiPart>
#include <QIODevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSaveFile>
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

QString fileNameForPath(const QString &path)
{
    const QUrl directUrl(path);
    const QString scheme = directUrl.scheme().toLower();
    if (directUrl.isValid()
        && (scheme == QStringLiteral("http")
            || scheme == QStringLiteral("https")
            || scheme == QStringLiteral("file")
            || scheme == QStringLiteral("qrc"))) {
        return QFileInfo(directUrl.path(QUrl::FullyDecoded)).fileName();
    }
    return QFileInfo(QDir::fromNativeSeparators(path)).fileName();
}

// file/qrc 地址与网络下载共用同一个输出设备，避免为大文件额外分配完整内存缓冲区。
bool copyUrlToDevice(const QUrl &sourceUrl, QIODevice *target, QString *error)
{
    if (!target || !target->isOpen() || !target->isWritable()) {
        *error = QStringLiteral("目标文件不可写");
        return false;
    }

    QString sourcePath;
    const QString scheme = sourceUrl.scheme().toLower();
    if (scheme == QStringLiteral("file")) {
        sourcePath = sourceUrl.toLocalFile();
    } else if (scheme == QStringLiteral("qrc")) {
        sourcePath = QStringLiteral(":") + sourceUrl.path();
    } else {
        *error = QStringLiteral("不支持此文件地址协议：%1").arg(scheme);
        return false;
    }

    QFile source(sourcePath);
    if (!source.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("无法读取源文件：%1").arg(source.errorString());
        return false;
    }

    while (!source.atEnd()) {
        const QByteArray data = source.read(64 * 1024);
        if (data.isEmpty()) {
            if (source.error() != QFileDevice::NoError)
                *error = QStringLiteral("读取源文件失败：%1").arg(source.errorString());
            else
                *error = QStringLiteral("读取源文件时发生意外中断");
            return false;
        }
        if (target->write(data) != data.size()) {
            *error = QStringLiteral("写入目标文件失败：%1").arg(target->errorString());
            return false;
        }
    }
    return true;
}

bool validateItemName(const QString &itemName, const QString &itemType, QString *error)
{
    const QString typeName = itemType.isEmpty()
        ? QStringLiteral("名称") : itemType + QStringLiteral("名称");
    if (itemName.isEmpty()) {
        *error = QStringLiteral("请输入%1").arg(typeName);
        return false;
    }
    if (itemName.size() > 100) {
        *error = QStringLiteral("%1不能超过 100 个字符").arg(typeName);
        return false;
    }
    if (itemName == QStringLiteral(".") || itemName == QStringLiteral("..")) {
        *error = QStringLiteral("%1不能是“.”或“..”").arg(typeName);
        return false;
    }

    const QString invalidCharacters = QStringLiteral("<>:\"/\\|?*");
    for (const QChar ch : itemName) {
        if (ch.unicode() < 32 || invalidCharacters.contains(ch)) {
            *error = QStringLiteral("名称不能包含 < > : \" / \\ | ? * 或控制字符");
            return false;
        }
    }

    // 与 Windows 的命名规则保持一致，避免同步到不同平台后名称不可用。
    if (itemName.endsWith(QLatin1Char('.')) || itemName.endsWith(QLatin1Char(' '))) {
        *error = QStringLiteral("%1不能以句点或空格结尾").arg(typeName);
        return false;
    }

    QString baseName = itemName;
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
        *error = QStringLiteral("该名称是系统保留名称，请更换%1").arg(typeName);
        return false;
    }

    return true;
}

bool validateFolderName(const QString &folderName, QString *error)
{
    return validateItemName(folderName, QStringLiteral("文件夹"), error);
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

bool normalizeCloudPath(const QString &path, QString *normalized)
{
    const QString value = QDir::fromNativeSeparators(path);
    const QString cleaned = QDir::cleanPath(value);
    if (value.contains(QLatin1Char('\0'))
        || QDir::isAbsolutePath(value)
        || cleaned == QStringLiteral("..")
        || cleaned.startsWith(QStringLiteral("../"))
        || cleaned.startsWith(QLatin1Char('/'))) {
        return false;
    }

    *normalized = cleaned == QStringLiteral(".") ? QString() : cleaned;
    return true;
}

bool isSyncingStatus(const QString &status)
{
    const QString value = status.trimmed().toLower();
    return value == QStringLiteral("同步中")
           || value == QStringLiteral("正在同步")
           || value == QStringLiteral("上传中")
           || value == QStringLiteral("syncing")
           || value == QStringLiteral("uploading")
           || value == QStringLiteral("in_progress");
}

bool isSyncedStatus(const QString &status)
{
    const QString value = status.trimmed().toLower();
    return value == QStringLiteral("已同步")
           || value == QStringLiteral("同步完成")
           || value == QStringLiteral("synced")
           || value == QStringLiteral("completed");
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
    item.insert(QStringLiteral("favorite"), object.value(QStringLiteral("favorite")).toBool(false));
    item.insert(QStringLiteral("favoriteTime"), object.value(QStringLiteral("favoriteTime")).toString());
    item.insert(QStringLiteral("location"), object.value(QStringLiteral("location")).toString());
    item.insert(QStringLiteral("originalPath"), object.value(QStringLiteral("originalPath")).toString());
    item.insert(QStringLiteral("deletedTime"), object.value(QStringLiteral("deletedTime")).toString());
    return item;
}

} // namespace

UploadManager::UploadManager(QObject *parent)
    : QObject(parent)
    , m_network()
{
    m_reconnectTimer.setSingleShot(true);
    m_refreshTimer.setSingleShot(true);
    m_favoritesRefreshTimer.setSingleShot(true);
    m_trashRefreshTimer.setSingleShot(true);
    m_handshakeTimer.setSingleShot(true);
    m_handshakeTimer.setInterval(15000);
    m_pingTimer.setInterval(30000);

    connect(&m_reconnectTimer, &QTimer::timeout,
            this, &UploadManager::openWebSocket);
    connect(&m_refreshTimer, &QTimer::timeout,
            this, &UploadManager::loadFiles);
    connect(&m_favoritesRefreshTimer, &QTimer::timeout,
            this, &UploadManager::loadFavorites);
    connect(&m_trashRefreshTimer, &QTimer::timeout,
            this, &UploadManager::loadTrash);
    connect(&m_handshakeTimer, &QTimer::timeout, this, [this]() {
        if (m_eventSocket.state() == QAbstractSocket::ConnectingState) {
            setWebSocketStatus(QStringLiteral("实时同步连接超时，正在重试…"));
            m_eventSocket.abort();
            scheduleWebSocketReconnect();
        }
    });
    connect(&m_pingTimer, &QTimer::timeout, this, [this]() {
        if (m_eventSocket.state() == QAbstractSocket::ConnectedState)
            m_eventSocket.ping();
    });

    connect(&m_eventSocket, &QWebSocket::connected, this, [this]() {
        m_reconnectTimer.stop();
        m_handshakeTimer.stop();
        m_reconnectAttempt = 0;
        setWebSocketConnected(true);
        setWebSocketStatus(QStringLiteral("实时同步已连接"));
        m_pingTimer.start();

        // 断线期间可能错过事件，每次建立连接都进行一次全量对账。
        scheduleFilesRefresh(0);
        scheduleFavoritesRefresh(0);
        scheduleTrashRefresh(0);
    });
    connect(&m_eventSocket, &QWebSocket::disconnected, this, [this]() {
        m_handshakeTimer.stop();
        m_pingTimer.stop();
        setWebSocketConnected(false);
        if (!m_shuttingDown) {
            setWebSocketStatus(QStringLiteral("实时同步已断开，等待重连…"));
            scheduleWebSocketReconnect();
        }
    });
    connect(&m_eventSocket, &QWebSocket::textMessageReceived,
            this, &UploadManager::handleWebSocketMessage);
    connect(&m_eventSocket,
            QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::error),
            this, [this](QAbstractSocket::SocketError) {
        if (m_shuttingDown)
            return;
        setWebSocketStatus(QStringLiteral("实时同步连接异常：%1")
                               .arg(m_eventSocket.errorString()));
        qWarning().noquote() << QStringLiteral("WebSocket 错误：%1")
                                    .arg(m_eventSocket.errorString());
        if (m_eventSocket.state() == QAbstractSocket::UnconnectedState)
            scheduleWebSocketReconnect();
    });

    // 延迟到事件循环启动后连接，让 QML 有机会先覆盖服务器地址。
    QTimer::singleShot(0, this, &UploadManager::openWebSocket);
}

UploadManager::~UploadManager()
{
    m_shuttingDown = true;
    m_reconnectTimer.stop();
    m_refreshTimer.stop();
    m_favoritesRefreshTimer.stop();
    m_trashRefreshTimer.stop();
    m_pingTimer.stop();
    m_handshakeTimer.stop();
    m_eventSocket.abort();
    if (m_favoriteReply) {
        QNetworkReply *reply = m_favoriteReply;
        m_favoriteReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_favoriteListReply) {
        QNetworkReply *reply = m_favoriteListReply;
        m_favoriteListReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_moveReply) {
        QNetworkReply *reply = m_moveReply;
        m_moveReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_deleteReply) {
        QNetworkReply *reply = m_deleteReply;
        m_deleteReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_trashListReply) {
        QNetworkReply *reply = m_trashListReply;
        m_trashListReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_trashActionReply) {
        QNetworkReply *reply = m_trashActionReply;
        m_trashActionReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_folderChoicesReply) {
        QNetworkReply *reply = m_folderChoicesReply;
        m_folderChoicesReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    resetOpenFile();
    resetDownload();
    resetFolderDownload();
    for (QTemporaryFile *file : m_openedFiles)
        delete file;
    m_openedFiles.clear();
    resetDocumentPreparation();
}

QString UploadManager::serverUrl() const { return m_serverUrl; }
bool UploadManager::uploading() const { return m_uploading; }
bool UploadManager::loadingFiles() const { return m_loadingFiles; }
bool UploadManager::creatingFolder() const { return m_creatingFolder; }
bool UploadManager::renaming() const { return m_renaming; }
bool UploadManager::moving() const { return m_moving; }
bool UploadManager::loadingFolderChoices() const { return m_loadingFolderChoices; }
bool UploadManager::openingFile() const { return m_openingFile; }
bool UploadManager::downloading() const { return m_downloading; }
bool UploadManager::loadingFavorites() const { return m_loadingFavorites; }
bool UploadManager::updatingFavorite() const { return m_updatingFavorite; }
bool UploadManager::deleting() const { return m_deleting; }
bool UploadManager::loadingTrash() const { return m_loadingTrash; }
bool UploadManager::updatingTrash() const { return m_updatingTrash; }
int UploadManager::progress() const { return m_progress; }
QString UploadManager::currentFile() const { return m_currentFile; }
QString UploadManager::statusText() const { return m_statusText; }
QString UploadManager::listStatus() const { return m_listStatus; }
QString UploadManager::currentPath() const { return m_currentPath; }
int UploadManager::cloudFileCount() const { return m_cloudFileCount; }
int UploadManager::syncedFileCount() const { return m_syncedFileCount; }
int UploadManager::syncingFileCount() const { return m_syncingFileCount; }
int UploadManager::completedCount() const { return m_completedCount; }
int UploadManager::totalCount() const { return m_totalCount; }
int UploadManager::successCount() const { return m_successCount; }
int UploadManager::failedCount() const { return m_failedCount; }
QString UploadManager::fileListUrl() const { return m_fileListUrl; }

QString UploadManager::webSocketUrl() const
{
    return m_webSocketUrl.isEmpty()
        ? derivedWebSocketUrl().toString(QUrl::FullyEncoded) : m_webSocketUrl;
}

bool UploadManager::webSocketConnected() const { return m_webSocketConnected; }
QString UploadManager::webSocketStatus() const { return m_webSocketStatus; }

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
    if (m_webSocketUrl.isEmpty())
        emit webSocketUrlChanged();
    reconnectWebSocket();
}

void UploadManager::setWebSocketUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_webSocketUrl == trimmed)
        return;
    m_webSocketUrl = trimmed;
    emit webSocketUrlChanged();
    reconnectWebSocket();
}

QUrl UploadManager::derivedWebSocketUrl() const
{
    QUrl endpoint(m_fileListUrl);
    const QString scheme = endpoint.scheme().toLower();
    if (!endpoint.isValid()
        || (scheme != QStringLiteral("http") && scheme != QStringLiteral("https"))) {
        return {};
    }

    const int currentPort = endpoint.port(scheme == QStringLiteral("https") ? 443 : 80);
    if (currentPort <= 0 || currentPort >= 65535)
        return {};
    endpoint.setPort(currentPort + 1);
    endpoint.setScheme(scheme == QStringLiteral("https")
                           ? QStringLiteral("wss") : QStringLiteral("ws"));

    // 与 /files 保持相同 API 前缀，只替换最后一段。
    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("events"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());
    return endpoint;
}

void UploadManager::reconnectWebSocket()
{
    if (m_shuttingDown)
        return;

    m_reconnectAttempt = 0;
    m_reconnectTimer.stop();
    m_handshakeTimer.stop();
    if (m_eventSocket.state() != QAbstractSocket::UnconnectedState)
        m_eventSocket.abort();
    QTimer::singleShot(0, this, &UploadManager::openWebSocket);
}

void UploadManager::openWebSocket()
{
    if (m_shuttingDown)
        return;

    const QString endpointText = webSocketUrl();
    const auto state = m_eventSocket.state();
    if ((state == QAbstractSocket::ConnectedState
         || state == QAbstractSocket::ConnectingState)
        && m_activeWebSocketUrl == endpointText) {
        return;
    }
    if (state != QAbstractSocket::UnconnectedState) {
        m_eventSocket.abort();
        QTimer::singleShot(0, this, &UploadManager::openWebSocket);
        return;
    }

    const QUrl endpoint(endpointText);
    if (!endpoint.isValid() || endpoint.host().isEmpty()
        || (endpoint.scheme() != QStringLiteral("ws")
            && endpoint.scheme() != QStringLiteral("wss"))) {
        setWebSocketStatus(QStringLiteral("实时同步地址无效，请使用 ws 或 wss 地址"));
        scheduleWebSocketReconnect();
        return;
    }

    m_reconnectTimer.stop();
    m_activeWebSocketUrl = endpointText;
    setWebSocketStatus(QStringLiteral("正在连接实时同步服务…"));
    m_handshakeTimer.start();
    m_eventSocket.open(endpoint);
}

void UploadManager::scheduleWebSocketReconnect()
{
    if (m_shuttingDown || m_reconnectTimer.isActive()
        || m_eventSocket.state() != QAbstractSocket::UnconnectedState) {
        return;
    }

    const int exponent = qMin(m_reconnectAttempt, 5);
    const int delayMs = qMin(30000, 1000 * (1 << exponent));
    ++m_reconnectAttempt;
    setWebSocketStatus(QStringLiteral("实时同步将在 %1 秒后重连")
                           .arg(delayMs / 1000));
    m_reconnectTimer.start(delayMs);
}

void UploadManager::scheduleFilesRefresh(int delayMs)
{
    if (m_shuttingDown || m_refreshTimer.isActive())
        return;
    m_refreshTimer.start(qMax(0, delayMs));
}

void UploadManager::scheduleFavoritesRefresh(int delayMs)
{
    if (m_shuttingDown || m_favoritesRefreshTimer.isActive())
        return;
    m_favoritesRefreshTimer.start(qMax(0, delayMs));
}

void UploadManager::scheduleTrashRefresh(int delayMs)
{
    if (m_shuttingDown || m_trashRefreshTimer.isActive())
        return;
    m_trashRefreshTimer.start(qMax(0, delayMs));
}

bool UploadManager::eventAffectsCurrentPath(const QStringList &paths) const
{
    if (paths.isEmpty() || m_currentPath.isEmpty())
        return true;

    const QString currentPrefix = m_currentPath + QLatin1Char('/');
    for (const QString &rawPath : paths) {
        QString path;
        if (!normalizeCloudPath(rawPath, &path) || path.isEmpty())
            return true; // 根目录或无法识别的路径按全量变更处理。
        if (path == m_currentPath || path.startsWith(currentPrefix)
            || m_currentPath.startsWith(path + QLatin1Char('/'))) {
            return true;
        }
    }
    return false;
}

void UploadManager::handleWebSocketMessage(const QString &message)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(message.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning().noquote() << QStringLiteral("忽略无效的 WebSocket 事件");
        return;
    }

    const QJsonObject event = document.object();
    const QString type = event.value(QStringLiteral("type")).toString();
    const quint64 revision = event.value(QStringLiteral("revision"))
                                 .toVariant().toULongLong();
    if (type == QStringLiteral("ready")) {
        // 服务器可能已重启，revision 以其最新连接消息为基准。
        m_lastEventRevision = revision;
        return;
    }
    const bool isFilesChanged = type == QStringLiteral("filesChanged");
    const bool isFavoritesChanged = type == QStringLiteral("favoritesChanged");
    const bool isTrashChanged = type == QStringLiteral("trashChanged");
    if (!isFilesChanged && !isFavoritesChanged && !isTrashChanged)
        return;
    if (revision > 0 && revision <= m_lastEventRevision)
        return;
    m_lastEventRevision = revision;

    if (isFavoritesChanged) {
        scheduleFavoritesRefresh();
        return;
    }
    if (isTrashChanged) {
        scheduleTrashRefresh();
        return;
    }

    QStringList paths;
    const QJsonArray pathArray = event.value(QStringLiteral("paths")).toArray();
    paths.reserve(pathArray.size());
    for (const QJsonValue &value : pathArray)
        paths.append(value.toString());

    emit serverFilesChanged(paths, revision);
    // 文件改名、移动、删除或元数据变化也可能影响收藏页，不只刷新当前目录。
    scheduleFavoritesRefresh();
    if (!eventAffectsCurrentPath(paths))
        return;

    setListStatus(QStringLiteral("检测到服务器文件变化，正在同步…"));
    scheduleFilesRefresh();
}

void UploadManager::setWebSocketConnected(bool value)
{
    if (m_webSocketConnected == value)
        return;
    m_webSocketConnected = value;
    emit webSocketConnectedChanged();
}

void UploadManager::setWebSocketStatus(const QString &value)
{
    if (m_webSocketStatus == value)
        return;
    m_webSocketStatus = value;
    emit webSocketStatusChanged();
}

void UploadManager::openFolder(const QString &folderPath)
{
    QString normalized;
    if (!normalizeCloudPath(folderPath, &normalized)) {
        const QString reason = QStringLiteral("目录路径无效或不安全");
        setListStatus(reason);
        emit filesLoadFailed(reason);
        return;
    }

    if (m_currentPath != normalized) {
        m_currentPath = normalized;
        m_serverSyncedFileCount = 0;
        m_serverSyncingFileCount = 0;
        setCloudFileCount(0);
        setSyncedFileCount(0);
        updateSyncingFileCount();
        emit currentPathChanged();
    }
    loadFiles();
}

void UploadManager::loadFiles()
{
    // 目录切换以最后一次操作为准，取消旧请求，防止旧响应覆盖新目录。
    if (m_listReply) {
        QNetworkReply *oldReply = m_listReply;
        m_listReply = nullptr;
        disconnect(oldReply, nullptr, this, nullptr);
        oldReply->abort();
        oldReply->deleteLater();
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件列表地址无效：请填写 http 或 https 地址");
        setLoadingFiles(false);
        setListStatus(reason);
        emit filesLoadFailed(reason);
        return;
    }

    QUrlQuery query(endpoint);
    query.removeQueryItem(QStringLiteral("path"));
    if (!m_currentPath.isEmpty())
        query.addQueryItem(QStringLiteral("path"), m_currentPath);
    endpoint.setQuery(query);

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(30000);

    setLoadingFiles(true);
    setListStatus(QStringLiteral("正在从服务器加载文件列表…"));
    QNetworkReply *reply = m_network.get(request);
    m_listReply = reply;
    const QString requestedPath = m_currentPath;

    connect(reply, &QNetworkReply::finished, this, [this, reply, requestedPath]() {
        if (reply != m_listReply) {
            reply->deleteLater();
            return;
        }

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
        int derivedTotal = 0;
        int derivedSynced = 0;
        int derivedSyncing = 0;
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;

            const QJsonObject object = value.toObject();
            QVariantMap item = makeFileItem(object);
            if (item.value(QStringLiteral("name")).toString().isEmpty())
                continue;

            items.append(item);
            if (item.value(QStringLiteral("kind")).toString() == QStringLiteral("folder"))
                continue;

            ++derivedTotal;
            const QString status = item.value(QStringLiteral("status")).toString();
            if (isSyncedStatus(status))
                ++derivedSynced;
            if (isSyncingStatus(status))
                ++derivedSyncing;
        }

        const QJsonValue totalValue = listObject.value(QStringLiteral("totalFiles"));
        const QJsonValue syncedValue = listObject.value(QStringLiteral("syncedFiles"));
        const QJsonValue syncingValue = listObject.value(QStringLiteral("syncingFiles"));
        const int serverTotal = totalValue.isDouble() ? qMax(0, totalValue.toInt()) : derivedTotal;
        const int serverSyncing = syncingValue.isDouble()
            ? qBound(0, syncingValue.toInt(), serverTotal) : derivedSyncing;
        int serverSynced = syncedValue.isDouble() ? qMax(0, syncedValue.toInt()) : derivedSynced;
        if (!syncedValue.isDouble() && totalValue.isDouble() && derivedTotal != serverTotal) {
            // 旧服务若只返回当前层条目和递归 totalFiles，未标记同步中的文件视为已同步。
            serverSynced = qMax(0, serverTotal - serverSyncing);
        }
        serverSynced = qBound(0, serverSynced, qMax(0, serverTotal - serverSyncing));

        m_serverSyncedFileCount = serverSynced;
        m_serverSyncingFileCount = serverSyncing;
        setCloudFileCount(serverTotal);
        setSyncedFileCount(serverSynced);
        updateSyncingFileCount();

        setLoadingFiles(false);
        const QString location = requestedPath.isEmpty()
            ? QStringLiteral("我的文件") : requestedPath;
        setListStatus(QStringLiteral("%1：共 %2 个文件，当前层 %3 个项目")
                          .arg(location)
                          .arg(serverTotal)
                          .arg(items.size()));
        emit filesLoaded(items);
    });
}

void UploadManager::loadFavorites()
{
    if (m_favoriteListReply) {
        QNetworkReply *oldReply = m_favoriteListReply;
        m_favoriteListReply = nullptr;
        disconnect(oldReply, nullptr, this, nullptr);
        oldReply->abort();
        oldReply->deleteLater();
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setLoadingFavorites(false);
        emit favoritesLoadFailed(reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("favorites"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(30000);

    setLoadingFavorites(true);
    QNetworkReply *reply = m_network.get(request);
    m_favoriteListReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply != m_favoriteListReply) {
            reply->deleteLater();
            return;
        }

        m_favoriteListReply = nullptr;
        const QByteArray body = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString networkError = reply->errorString();
        const bool hasNetworkError = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
        const bool hasJsonObject = parseError.error == QJsonParseError::NoError
                                   && document.isObject();
        QJsonObject responseObject = hasJsonObject ? document.object() : QJsonObject();
        const QString serverMessage = responseObject.value(QStringLiteral("message")).toString();

        QString error;
        if (hasNetworkError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = serverMessage.isEmpty() ? networkError : serverMessage;
            if (error.trimmed().isEmpty())
                error = QStringLiteral("服务器返回异常响应");
            if (serverMessage.isEmpty() && httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        } else if (!hasJsonObject) {
            error = QStringLiteral("服务器返回的收藏列表不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能返回收藏列表") : serverMessage;
        }

        if (!error.isEmpty()) {
            setLoadingFavorites(false);
            emit favoritesLoadFailed(error);
            return;
        }

        if (responseObject.value(QStringLiteral("data")).isObject())
            responseObject = responseObject.value(QStringLiteral("data")).toObject();
        if (!responseObject.value(QStringLiteral("items")).isArray()) {
            setLoadingFavorites(false);
            emit favoritesLoadFailed(QStringLiteral("收藏列表响应缺少 items 数组"));
            return;
        }

        QVariantList items;
        const QJsonArray entries = responseObject.value(QStringLiteral("items")).toArray();
        items.reserve(entries.size());
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;

            QVariantMap item = makeFileItem(value.toObject());
            QString itemPath;
            if (!normalizeCloudPath(item.value(QStringLiteral("path")).toString(), &itemPath)
                || itemPath.isEmpty()
                || item.value(QStringLiteral("name")).toString().isEmpty()) {
                continue;
            }
            item.insert(QStringLiteral("path"), itemPath);
            item.insert(QStringLiteral("favorite"), true);
            if (item.value(QStringLiteral("favoriteTime")).toString().isEmpty())
                item.insert(QStringLiteral("favoriteTime"), item.value(QStringLiteral("modified")));
            if (item.value(QStringLiteral("location")).toString().isEmpty()) {
                const int separator = itemPath.lastIndexOf(QLatin1Char('/'));
                const QString parentPath = separator >= 0
                    ? itemPath.left(separator) : QString();
                item.insert(QStringLiteral("location"), parentPath.isEmpty()
                            ? QStringLiteral("我的文件")
                            : QStringLiteral("我的文件 / ") + parentPath);
            }
            items.append(item);
        }

        setLoadingFavorites(false);
        emit favoritesLoaded(items);
    });
}

void UploadManager::addFavorite(const QString &path)
{
    setFavorite(path, true);
}

void UploadManager::removeFavorite(const QString &path)
{
    setFavorite(path, false);
}

void UploadManager::setFavorite(const QString &path, bool favorite)
{
    QString sourcePath;
    const bool validPath = normalizeCloudPath(path, &sourcePath);
    const QString reportedPath = validPath ? sourcePath : path;

    auto failStart = [this, reportedPath, favorite](const QString &reason) {
        setListStatus((favorite ? QStringLiteral("添加收藏失败：")
                                : QStringLiteral("取消收藏失败：")) + reason);
        if (favorite)
            emit favoriteAddFailed(reportedPath, reason);
        else
            emit favoriteRemoveFailed(reportedPath, reason);
    };

    if (m_updatingFavorite) {
        failStart(QStringLiteral("正在处理其他收藏操作，请稍后再试"));
        return;
    }
    if (!validPath || sourcePath.isEmpty()) {
        failStart(QStringLiteral("文件或文件夹路径无效或不安全"));
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        failStart(QStringLiteral("文件服务地址无效：请填写 http 或 https 地址"));
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + (favorite ? QStringLiteral("favorites")
                                         : QStringLiteral("favorites/remove")));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    request.setTransferTimeout(120000);

    const QJsonObject payload{
        {QStringLiteral("path"), sourcePath},
        {QStringLiteral("recursive"), true}
    };
    const QString itemName = QFileInfo(sourcePath).fileName();
    setUpdatingFavorite(true);
    setListStatus(favorite ? QStringLiteral("正在添加收藏：%1").arg(itemName)
                           : QStringLiteral("正在取消收藏：%1").arg(itemName));

    QNetworkReply *reply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_favoriteReply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, sourcePath, itemName, favorite]() {
        if (reply != m_favoriteReply) {
            reply->deleteLater();
            return;
        }

        m_favoriteReply = nullptr;
        const QByteArray body = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString networkError = reply->errorString();
        const bool hasNetworkError = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
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
        } else if (!hasJsonObject) {
            error = QStringLiteral("服务器返回的收藏结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能完成收藏操作") : serverMessage;
        }

        if (!error.isEmpty()) {
            setUpdatingFavorite(false);
            setListStatus((favorite ? QStringLiteral("添加收藏失败：")
                                    : QStringLiteral("取消收藏失败：")) + error);
            if (favorite)
                emit favoriteAddFailed(sourcePath, error);
            else
                emit favoriteRemoveFailed(sourcePath, error);
            return;
        }

        setUpdatingFavorite(false);
        const int favoriteCount = qMax(0, responseObject.value(
            QStringLiteral("favoriteCount")).toInt());
        if (favorite) {
            const int addedCount = qMax(0, responseObject.value(
                QStringLiteral("addedCount")).toInt());
            setListStatus(addedCount > 0
                ? QStringLiteral("收藏“%1”完成，新增 %2 个收藏项目")
                      .arg(itemName).arg(addedCount)
                : QStringLiteral("“%1”的所选内容均已在收藏夹中").arg(itemName));
            emit favoriteAdded(sourcePath, addedCount, favoriteCount);
        } else {
            const int removedCount = qMax(0, responseObject.value(
                QStringLiteral("removedCount")).toInt());
            setListStatus(removedCount > 0
                ? QStringLiteral("已取消收藏“%1”，共移除 %2 个收藏入口")
                      .arg(itemName).arg(removedCount)
                : QStringLiteral("“%1”原本就不在收藏夹中").arg(itemName));
            emit favoriteRemoved(sourcePath, removedCount, favoriteCount);
        }
        loadFavorites();
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
        {QStringLiteral("name"), name},
        {QStringLiteral("path"), m_currentPath}
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

void UploadManager::renameItem(const QString &path, const QString &newName)
{
    QString sourcePath;
    const bool validPath = normalizeCloudPath(path, &sourcePath);
    const QString reportedPath = validPath ? sourcePath : path;
    if (m_renaming) {
        const QString reason = QStringLiteral("正在重命名其他项目，请稍后再试");
        setListStatus(reason);
        emit itemRenameFailed(reportedPath, reason);
        return;
    }

    if (!validPath || sourcePath.isEmpty()) {
        const QString reason = QStringLiteral("原文件路径无效或不安全");
        setListStatus(QStringLiteral("重命名失败：%1").arg(reason));
        emit itemRenameFailed(reportedPath, reason);
        return;
    }

    const QString name = newName.trimmed();
    QString validationError;
    if (!validateItemName(name, QString(), &validationError)) {
        setListStatus(QStringLiteral("重命名失败：%1").arg(validationError));
        emit itemRenameFailed(sourcePath, validationError);
        return;
    }

    const QString oldName = QFileInfo(sourcePath).fileName();
    if (name == oldName) {
        setListStatus(QStringLiteral("名称未修改"));
        emit itemRenamed(sourcePath, sourcePath, name);
        return;
    }

    // 与新建文件夹一致，将 /files 映射为同级的 /rename。
    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setListStatus(reason);
        emit itemRenameFailed(sourcePath, reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("rename"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    request.setTransferTimeout(30000);

    const QJsonObject payload{
        {QStringLiteral("path"), sourcePath},
        {QStringLiteral("newName"), name}
    };

    setRenaming(true);
    setListStatus(QStringLiteral("正在将“%1”重命名为“%2”…").arg(oldName, name));
    QNetworkReply *reply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_renameReply = reply;

    connect(reply, &QNetworkReply::finished, this, [this, reply, sourcePath, oldName, name]() {
        if (reply != m_renameReply) {
            reply->deleteLater();
            return;
        }

        m_renameReply = nullptr;
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
            error = QStringLiteral("服务器返回的重命名结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能完成重命名") : serverMessage;
        }

        if (!error.isEmpty()) {
            setRenaming(false);
            setListStatus(QStringLiteral("重命名失败：%1").arg(error));
            emit itemRenameFailed(sourcePath, error);
            return;
        }

        const QString actualName = responseObject.value(QStringLiteral("name")).toString(name);
        QString newPath = responseObject.value(QStringLiteral("path")).toString();
        if (newPath.isEmpty())
            newPath = responseObject.value(QStringLiteral("newPath")).toString();
        if (newPath.isEmpty()) {
            const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
            const QString parentPath = pathSeparator >= 0
                ? sourcePath.left(pathSeparator) : QString();
            newPath = parentPath.isEmpty()
                ? actualName : parentPath + QLatin1Char('/') + actualName;
        }

        setRenaming(false);
        setListStatus(QStringLiteral("“%1”已重命名为“%2”").arg(oldName, actualName));
        emit itemRenamed(sourcePath, newPath, actualName);
    });
}

void UploadManager::moveItem(const QString &path, const QString &destinationPath)
{
    QString sourcePath;
    QString targetDirectory;
    const bool validSource = normalizeCloudPath(path, &sourcePath);
    const bool validDestination = normalizeCloudPath(destinationPath, &targetDirectory);
    const QString reportedPath = validSource ? sourcePath : path;

    if (m_moving) {
        const QString reason = QStringLiteral("正在移动其他项目，请稍后再试");
        setListStatus(reason);
        emit itemMoveFailed(reportedPath, reason);
        return;
    }
    if (!validSource || sourcePath.isEmpty()) {
        const QString reason = QStringLiteral("原文件或文件夹路径无效或不安全");
        setListStatus(QStringLiteral("移动失败：%1").arg(reason));
        emit itemMoveFailed(reportedPath, reason);
        return;
    }
    if (!validDestination) {
        const QString reason = QStringLiteral("目标文件夹路径无效或不安全");
        setListStatus(QStringLiteral("移动失败：%1").arg(reason));
        emit itemMoveFailed(sourcePath, reason);
        return;
    }

    // 目标不能是源文件夹自身或其子孙后代；服务端会再次做权威校验。
    if (targetDirectory == sourcePath
        || targetDirectory.startsWith(sourcePath + QLatin1Char('/'))) {
        const QString reason = QStringLiteral("不能将文件夹移动到自身或其子文件夹中");
        setListStatus(QStringLiteral("移动失败：%1").arg(reason));
        emit itemMoveFailed(sourcePath, reason);
        return;
    }

    const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
    const QString sourceParent = pathSeparator >= 0
        ? sourcePath.left(pathSeparator) : QString();
    const QString itemName = pathSeparator >= 0
        ? sourcePath.mid(pathSeparator + 1) : sourcePath;
    if (targetDirectory == sourceParent) {
        setListStatus(QStringLiteral("“%1”已在目标文件夹中").arg(itemName));
        emit itemMoved(sourcePath, sourcePath, targetDirectory);
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setListStatus(reason);
        emit itemMoveFailed(sourcePath, reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("move"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    request.setTransferTimeout(120000);

    const QJsonObject payload{
        {QStringLiteral("path"), sourcePath},
        {QStringLiteral("destinationPath"), targetDirectory}
    };

    setMoving(true);
    setListStatus(QStringLiteral("正在移动“%1”…").arg(itemName));
    QNetworkReply *reply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_moveReply = reply;

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, sourcePath, targetDirectory, itemName]() {
        if (reply != m_moveReply) {
            reply->deleteLater();
            return;
        }

        m_moveReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
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
            error = QStringLiteral("服务器返回的移动结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能完成移动") : serverMessage;
        }

        if (!error.isEmpty()) {
            setMoving(false);
            setListStatus(QStringLiteral("移动失败：%1").arg(error));
            emit itemMoveFailed(sourcePath, error);
            return;
        }

        QString actualDestination = responseObject.value(
            QStringLiteral("destinationPath")).toString(targetDirectory);
        QString normalizedDestination;
        if (!normalizeCloudPath(actualDestination, &normalizedDestination))
            normalizedDestination = targetDirectory;
        actualDestination = normalizedDestination;

        QString newPath = responseObject.value(QStringLiteral("newPath")).toString();
        if (newPath.isEmpty())
            newPath = responseObject.value(QStringLiteral("path")).toString();
        if (newPath.isEmpty()) {
            newPath = actualDestination.isEmpty()
                ? itemName : actualDestination + QLatin1Char('/') + itemName;
        }
        QString normalizedNewPath;
        if (!normalizeCloudPath(newPath, &normalizedNewPath) || normalizedNewPath.isEmpty()) {
            const QString reason = QStringLiteral("服务器返回的新路径无效");
            setMoving(false);
            setListStatus(QStringLiteral("移动失败：%1").arg(reason));
            emit itemMoveFailed(sourcePath, reason);
            return;
        }
        newPath = normalizedNewPath;

        setMoving(false);
        const QString location = actualDestination.isEmpty()
            ? QStringLiteral("我的文件") : actualDestination;
        setListStatus(QStringLiteral("“%1”已移动到“%2”").arg(itemName, location));
        emit itemMoved(sourcePath, newPath, actualDestination);
    });
}

void UploadManager::deleteItem(const QString &path)
{
    QString sourcePath;
    const bool validPath = normalizeCloudPath(path, &sourcePath);
    const QString reportedPath = validPath ? sourcePath : path;
    if (m_deleting) {
        const QString reason = QStringLiteral("正在删除其他项目，请稍后再试");
        setListStatus(reason);
        emit itemDeleteFailed(reportedPath, reason);
        return;
    }
    if (!validPath || sourcePath.isEmpty()) {
        const QString reason = QStringLiteral("文件或文件夹路径无效或不安全");
        setListStatus(QStringLiteral("删除失败：%1").arg(reason));
        emit itemDeleteFailed(reportedPath, reason);
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setListStatus(reason);
        emit itemDeleteFailed(sourcePath, reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("trash"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    // 跨磁盘移动大文件夹时，服务端可能需要先复制再清理源目录。
    request.setTransferTimeout(120000);

    const QJsonObject payload{{QStringLiteral("path"), sourcePath}};
    const QString itemName = QFileInfo(sourcePath).fileName();
    setDeleting(true);
    setListStatus(QStringLiteral("正在将“%1”移入回收站…").arg(itemName));
    QNetworkReply *reply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_deleteReply = reply;

    connect(reply, &QNetworkReply::finished, this, [this, reply, sourcePath, itemName]() {
        if (reply != m_deleteReply) {
            reply->deleteLater();
            return;
        }

        m_deleteReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
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
            error = QStringLiteral("服务器返回的删除结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能将项目移入回收站") : serverMessage;
        }

        if (!error.isEmpty()) {
            setDeleting(false);
            setListStatus(QStringLiteral("删除失败：%1").arg(error));
            emit itemDeleteFailed(sourcePath, error);
            return;
        }

        QString trashId = responseObject.value(QStringLiteral("trashId")).toString();
        if (trashId.isEmpty())
            trashId = responseObject.value(QStringLiteral("id")).toString();
        if (trashId.isEmpty())
            trashId = responseObject.value(QStringLiteral("path")).toString();

        setDeleting(false);
        setListStatus(QStringLiteral("“%1”已移入回收站").arg(itemName));
        emit itemDeleted(sourcePath, trashId);
    });
}

void UploadManager::loadTrash()
{
    // 主动刷新取代已计划的刷新，避免操作成功信号与 WebSocket 事件造成重复请求。
    m_trashRefreshTimer.stop();
    // 回收站刷新以最后一次请求为准，避免旧响应覆盖新数据。
    if (m_trashListReply) {
        QNetworkReply *oldReply = m_trashListReply;
        m_trashListReply = nullptr;
        disconnect(oldReply, nullptr, this, nullptr);
        oldReply->abort();
        oldReply->deleteLater();
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setLoadingTrash(false);
        emit trashLoadFailed(reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("trash"));
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(30000);

    setLoadingTrash(true);
    QNetworkReply *reply = m_network.get(request);
    m_trashListReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply != m_trashListReply) {
            reply->deleteLater();
            return;
        }

        m_trashListReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString networkError = reply->errorString();
        const bool hasNetworkError = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(responseBody, &parseError);
        const bool hasJsonObject = parseError.error == QJsonParseError::NoError
                                   && document.isObject();
        QJsonObject responseObject = hasJsonObject ? document.object() : QJsonObject();
        const QString serverMessage = responseObject.value(QStringLiteral("message")).toString();

        QString error;
        if (hasNetworkError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = serverMessage.isEmpty() ? networkError : serverMessage;
            if (error.trimmed().isEmpty())
                error = QStringLiteral("服务器返回异常响应");
            if (serverMessage.isEmpty() && httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        } else if (!hasJsonObject) {
            error = QStringLiteral("服务器返回的回收站列表不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能返回回收站列表") : serverMessage;
        }

        if (responseObject.value(QStringLiteral("data")).isObject())
            responseObject = responseObject.value(QStringLiteral("data")).toObject();
        const QJsonValue itemsValue = responseObject.value(QStringLiteral("items"));
        if (error.isEmpty() && !itemsValue.isArray())
            error = QStringLiteral("回收站列表响应缺少 items 数组");

        if (!error.isEmpty()) {
            setLoadingTrash(false);
            emit trashLoadFailed(error);
            return;
        }

        QVariantList items;
        const QJsonArray entries = itemsValue.toArray();
        items.reserve(entries.size());
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;
            QVariantMap item = makeFileItem(value.toObject());
            if (!item.value(QStringLiteral("name")).toString().isEmpty()
                && !item.value(QStringLiteral("path")).toString().isEmpty()) {
                items.append(item);
            }
        }

        setLoadingTrash(false);
        emit trashLoaded(items);
    });
}

void UploadManager::restoreTrashItem(const QString &trashId)
{
    startTrashAction(TrashAction::Restore, trashId);
}

void UploadManager::permanentlyDeleteTrashItem(const QString &trashId)
{
    startTrashAction(TrashAction::PermanentDelete, trashId);
}

void UploadManager::emptyTrash()
{
    startTrashAction(TrashAction::Empty);
}

void UploadManager::failTrashAction(TrashAction action,
                                    const QString &trashId,
                                    const QString &reason)
{
    setUpdatingTrash(false);
    switch (action) {
    case TrashAction::Restore:
        setListStatus(QStringLiteral("还原失败：%1").arg(reason));
        emit trashItemRestoreFailed(trashId, reason);
        break;
    case TrashAction::PermanentDelete:
        setListStatus(QStringLiteral("彻底删除失败：%1").arg(reason));
        emit trashPermanentDeleteFailed(trashId, reason);
        break;
    case TrashAction::Empty:
        setListStatus(QStringLiteral("清空回收站失败：%1").arg(reason));
        emit trashEmptyFailed(reason);
        break;
    }
}

void UploadManager::startTrashAction(TrashAction action, const QString &trashId)
{
    const QString requestedId = trashId.trimmed();
    if (m_updatingTrash) {
        failTrashAction(action, requestedId,
                        QStringLiteral("另一个回收站操作尚未完成，请稍后再试"));
        return;
    }

    if (action != TrashAction::Empty
        && (requestedId.isEmpty() || requestedId.size() > 128
            || requestedId == QStringLiteral(".") || requestedId == QStringLiteral("..")
            || requestedId.contains(QLatin1Char('/'))
            || requestedId.contains(QLatin1Char('\\'))
            || requestedId.contains(QLatin1Char('\0')))) {
        failTrashAction(action, requestedId, QStringLiteral("回收站条目 ID 无效或不安全"));
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        failTrashAction(action, requestedId,
                        QStringLiteral("文件服务地址无效：请填写 http 或 https 地址"));
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");

    QString actionPath;
    QString pendingText;
    QJsonObject payload;
    switch (action) {
    case TrashAction::Restore:
        actionPath = QStringLiteral("trash/restore");
        pendingText = QStringLiteral("正在还原回收站项目…");
        payload.insert(QStringLiteral("path"), requestedId);
        break;
    case TrashAction::PermanentDelete:
        actionPath = QStringLiteral("trash/delete");
        pendingText = QStringLiteral("正在彻底删除回收站项目…");
        payload.insert(QStringLiteral("path"), requestedId);
        break;
    case TrashAction::Empty:
        actionPath = QStringLiteral("trash/empty");
        pendingText = QStringLiteral("正在清空回收站…");
        break;
    }

    endpoint.setPath(basePath + actionPath);
    endpoint.setQuery(QUrlQuery());
    endpoint.setFragment(QString());

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Content-Type"),
                         QByteArrayLiteral("application/json; charset=utf-8"));
    // 大文件夹还原或清空可能需要跨磁盘复制、递归清理。
    request.setTransferTimeout(120000);

    setUpdatingTrash(true);
    setListStatus(pendingText);
    QNetworkReply *reply = m_network.post(
        request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_trashActionReply = reply;

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, action, requestedId]() {
        if (reply != m_trashActionReply) {
            reply->deleteLater();
            return;
        }

        m_trashActionReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
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
            error = QStringLiteral("服务器返回的回收站操作结果不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能完成回收站操作") : serverMessage;
        }

        if (!error.isEmpty()) {
            failTrashAction(action, requestedId, error);
            return;
        }

        setUpdatingTrash(false);
        switch (action) {
        case TrashAction::Restore: {
            QString originalPath = responseObject.value(QStringLiteral("originalPath")).toString();
            if (originalPath.isEmpty())
                originalPath = responseObject.value(QStringLiteral("path")).toString();
            QString normalizedPath;
            if (!normalizeCloudPath(originalPath, &normalizedPath) || normalizedPath.isEmpty())
                normalizedPath.clear();
            setListStatus(normalizedPath.isEmpty()
                ? QStringLiteral("回收站项目已还原")
                : QStringLiteral("已还原到“%1”").arg(normalizedPath));
            emit trashItemRestored(requestedId, normalizedPath);
            break;
        }
        case TrashAction::PermanentDelete:
            setListStatus(QStringLiteral("回收站项目已彻底删除"));
            emit trashItemPermanentlyDeleted(requestedId);
            break;
        case TrashAction::Empty: {
            const int deletedCount = qMax(0, responseObject.value(
                QStringLiteral("deletedCount")).toInt());
            setListStatus(QStringLiteral("回收站已清空，共删除 %1 个项目").arg(deletedCount));
            emit trashEmptied(deletedCount);
            break;
        }
        }
    });
}

void UploadManager::loadFolderChoices(const QString &folderPath)
{
    // 目标目录浏览以最后一次操作为准，避免旧响应覆盖新目录。
    if (m_folderChoicesReply) {
        QNetworkReply *oldReply = m_folderChoicesReply;
        m_folderChoicesReply = nullptr;
        disconnect(oldReply, nullptr, this, nullptr);
        oldReply->abort();
        oldReply->deleteLater();
    }

    QString requestedPath;
    if (!normalizeCloudPath(folderPath, &requestedPath)) {
        const QString reason = QStringLiteral("目录路径无效或不安全");
        setLoadingFolderChoices(false);
        emit folderChoicesLoadFailed(folderPath, reason);
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        const QString reason = QStringLiteral("文件服务地址无效：请填写 http 或 https 地址");
        setLoadingFolderChoices(false);
        emit folderChoicesLoadFailed(requestedPath, reason);
        return;
    }

    QString basePath = endpoint.path();
    const int lastSlash = basePath.lastIndexOf(QLatin1Char('/'));
    basePath = lastSlash >= 0 ? basePath.left(lastSlash + 1) : QStringLiteral("/");
    endpoint.setPath(basePath + QStringLiteral("folders"));
    endpoint.setFragment(QString());
    QUrlQuery query(endpoint);
    query.removeQueryItem(QStringLiteral("path"));
    if (!requestedPath.isEmpty())
        query.addQueryItem(QStringLiteral("path"), requestedPath);
    endpoint.setQuery(query);

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(30000);

    setLoadingFolderChoices(true);
    QNetworkReply *reply = m_network.get(request);
    m_folderChoicesReply = reply;

    connect(reply, &QNetworkReply::finished, this, [this, reply, requestedPath]() {
        if (reply != m_folderChoicesReply) {
            reply->deleteLater();
            return;
        }

        m_folderChoicesReply = nullptr;
        const QByteArray responseBody = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString networkError = reply->errorString();
        const bool hasNetworkError = reply->error() != QNetworkReply::NoError;
        reply->deleteLater();

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(responseBody, &parseError);
        const bool hasJsonObject = parseError.error == QJsonParseError::NoError
                                   && document.isObject();
        QJsonObject responseObject = hasJsonObject ? document.object() : QJsonObject();
        const QString serverMessage = responseObject.value(QStringLiteral("message")).toString();

        QString error;
        if (hasNetworkError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = serverMessage.isEmpty() ? networkError : serverMessage;
            if (error.trimmed().isEmpty())
                error = QStringLiteral("服务器返回异常响应");
            if (serverMessage.isEmpty() && httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        } else if (!hasJsonObject) {
            error = QStringLiteral("服务器返回的目录列表不是有效 JSON 对象");
        } else if (responseObject.contains(QStringLiteral("success"))
                   && !responseObject.value(QStringLiteral("success")).toBool()) {
            error = serverMessage.isEmpty()
                ? QStringLiteral("服务器未能返回目录列表") : serverMessage;
        }

        if (!error.isEmpty()) {
            setLoadingFolderChoices(false);
            emit folderChoicesLoadFailed(requestedPath, error);
            return;
        }

        if (responseObject.value(QStringLiteral("data")).isObject())
            responseObject = responseObject.value(QStringLiteral("data")).toObject();
        QJsonArray entries = responseObject.value(QStringLiteral("folders")).toArray();
        if (entries.isEmpty() && responseObject.value(QStringLiteral("items")).isArray())
            entries = responseObject.value(QStringLiteral("items")).toArray();
        if (!responseObject.value(QStringLiteral("folders")).isArray()
            && !responseObject.value(QStringLiteral("items")).isArray()) {
            setLoadingFolderChoices(false);
            emit folderChoicesLoadFailed(requestedPath,
                                         QStringLiteral("目录列表响应缺少 folders 数组"));
            return;
        }

        QVariantList folders;
        const QString directoryPrefix = requestedPath.isEmpty()
            ? QString() : requestedPath + QLatin1Char('/');
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;

            QJsonObject object = value.toObject();
            object.insert(QStringLiteral("kind"), QStringLiteral("folder"));
            const QString responseName = object.value(QStringLiteral("name")).toString();
            if (object.value(QStringLiteral("path")).toString().isEmpty()
                && !responseName.isEmpty()) {
                object.insert(QStringLiteral("path"), requestedPath.isEmpty()
                              ? responseName
                              : requestedPath + QLatin1Char('/') + responseName);
            }
            QVariantMap folder = makeFileItem(object);
            QString name = folder.value(QStringLiteral("name")).toString();
            QString childPath = folder.value(QStringLiteral("path")).toString();
            if (childPath.isEmpty() && !name.isEmpty()) {
                childPath = requestedPath.isEmpty()
                    ? name : requestedPath + QLatin1Char('/') + name;
            }

            QString normalizedChildPath;
            if (!normalizeCloudPath(childPath, &normalizedChildPath)
                || normalizedChildPath.isEmpty()) {
                continue;
            }
            if (!directoryPrefix.isEmpty()
                && !normalizedChildPath.startsWith(directoryPrefix)) {
                continue;
            }
            const QString directName = directoryPrefix.isEmpty()
                ? normalizedChildPath : normalizedChildPath.mid(directoryPrefix.size());
            if (directName.isEmpty() || directName.contains(QLatin1Char('/')))
                continue;

            folder.insert(QStringLiteral("name"), directName);
            folder.insert(QStringLiteral("path"), normalizedChildPath);
            folder.insert(QStringLiteral("kind"), QStringLiteral("folder"));
            folders.append(folder);
        }

        setLoadingFolderChoices(false);
        emit folderChoicesLoaded(requestedPath, folders);
    });
}

void UploadManager::openFile(const QString &path)
{
    const QString requestedPath = path.trimmed();
    if (m_openingFile) {
        const QString reason = QStringLiteral("正在打开其他文件，请稍后再试");
        setListStatus(reason);
        emit fileOpenFailed(requestedPath, reason);
        return;
    }

    m_openCloudPath = requestedPath;
    if (requestedPath.isEmpty()) {
        failFileOpen(QStringLiteral("文件路径为空"));
        return;
    }

    const QUrl sourceUrl(fileContentUrl(requestedPath));
    const QString scheme = sourceUrl.scheme().toLower();
    if (!sourceUrl.isValid() || scheme.isEmpty()) {
        failFileOpen(QStringLiteral("文件地址无效"));
        return;
    }

    // 外部模型若直接提供本地文件，无需再复制到临时目录。
    if (scheme == QStringLiteral("file")) {
        const QString localPath = sourceUrl.toLocalFile();
        const QFileInfo info(localPath);
        if (!info.exists() || !info.isFile() || !info.isReadable()) {
            failFileOpen(QStringLiteral("本地文件不存在或无法读取"));
            return;
        }
        if (!QDesktopServices::openUrl(sourceUrl)) {
            failFileOpen(QStringLiteral("系统无法找到可打开此文件的程序"));
            return;
        }

        const QString cloudPath = m_openCloudPath;
        m_openCloudPath.clear();
        setListStatus(QStringLiteral("已打开文件：%1").arg(info.fileName()));
        emit fileOpened(cloudPath, info.absoluteFilePath());
        return;
    }

    if (scheme != QStringLiteral("http")
        && scheme != QStringLiteral("https")
        && scheme != QStringLiteral("qrc")) {
        failFileOpen(QStringLiteral("不支持此文件地址协议：%1").arg(scheme));
        return;
    }

    // 保留原扩展名，Windows 和 macOS 才能据此选择合适的默认程序。
    QString suffix = QFileInfo(fileNameForPath(requestedPath)).suffix();
    if (suffix.size() > 32)
        suffix = suffix.left(32);
    const QString temporaryPattern = QDir(QDir::tempPath()).filePath(
        QStringLiteral("FileSyncOpen_XXXXXX%1")
            .arg(suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix));
    m_openFile = new QTemporaryFile(temporaryPattern, this);
    if (!m_openFile->open()) {
        failFileOpen(QStringLiteral("无法创建打开文件所需的临时文件：%1")
                         .arg(m_openFile->errorString()));
        return;
    }

    setOpeningFile(true);
    setListStatus(QStringLiteral("正在准备打开：%1")
                      .arg(fileNameForPath(requestedPath)));

    if (scheme == QStringLiteral("qrc")) {
        QString error;
        if (!copyUrlToDevice(sourceUrl, m_openFile, &error)) {
            failFileOpen(error);
            return;
        }
        finishOpenFile();
        return;
    }

    QNetworkRequest request(sourceUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/octet-stream"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(120000);

    QNetworkReply *reply = m_network.get(request);
    m_openReply = reply;
    connect(reply, &QIODevice::readyRead, this, [this, reply]() {
        if (reply != m_openReply)
            return;

        const QByteArray data = reply->readAll();
        if (!data.isEmpty()
            && (!m_openFile || m_openFile->write(data) != data.size())) {
            failFileOpen(QStringLiteral("写入打开文件所需的临时文件失败"));
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply != m_openReply)
            return;

        m_openReply = nullptr;
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
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
            failFileOpen(QStringLiteral("文件下载失败：%1").arg(error));
            return;
        }
        if (!remainingData.isEmpty()
            && (!m_openFile || m_openFile->write(remainingData) != remainingData.size())) {
            failFileOpen(QStringLiteral("写入打开文件所需的临时文件失败"));
            return;
        }
        finishOpenFile();
    });
}

void UploadManager::finishOpenFile()
{
    if (!m_openFile) {
        failFileOpen(QStringLiteral("打开文件所需的临时文件不存在"));
        return;
    }
    if (!m_openFile->flush()) {
        failFileOpen(QStringLiteral("临时文件写入不完整：%1")
                         .arg(m_openFile->errorString()));
        return;
    }

    const QString localPath = m_openFile->fileName();
    m_openFile->close();
    if (!QDesktopServices::openUrl(QUrl::fromLocalFile(localPath))) {
        failFileOpen(QStringLiteral("系统无法找到可打开此文件的程序"));
        return;
    }

    const QString cloudPath = m_openCloudPath;
    m_openedFiles.append(m_openFile);
    m_openFile = nullptr;
    m_openCloudPath.clear();
    setOpeningFile(false);
    setListStatus(QStringLiteral("已打开文件：%1").arg(QFileInfo(localPath).fileName()));
    emit fileOpened(cloudPath, localPath);
}

void UploadManager::failFileOpen(const QString &reason)
{
    const QString cloudPath = m_openCloudPath;
    resetOpenFile();
    m_openCloudPath.clear();
    setOpeningFile(false);
    setListStatus(QStringLiteral("打开文件失败：%1").arg(reason));
    emit fileOpenFailed(cloudPath, reason);
}

void UploadManager::resetOpenFile()
{
    if (m_openReply) {
        QNetworkReply *reply = m_openReply;
        m_openReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    delete m_openFile;
    m_openFile = nullptr;
}

QUrl UploadManager::defaultDownloadUrl(const QString &path) const
{
    QString fileName = fileNameForPath(path.trimmed());
    if (fileName.isEmpty())
        fileName = QStringLiteral("download.bin");

    QString directory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (directory.isEmpty())
        directory = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (directory.isEmpty())
        directory = QDir::currentPath();
    QDir().mkpath(directory);
    return QUrl::fromLocalFile(QDir(directory).filePath(fileName));
}

void UploadManager::downloadFile(const QString &path, const QUrl &destination)
{
    const QString requestedPath = path.trimmed();
    if (m_downloading) {
        const QString reason = QStringLiteral("正在下载其他内容，请稍后再试");
        setListStatus(reason);
        emit fileDownloadFailed(requestedPath, reason);
        return;
    }
    startFileDownload(requestedPath, destination);
}

void UploadManager::startFileDownload(const QString &path, const QUrl &destination)
{
    const QString requestedPath = path.trimmed();
    m_downloadCloudPath = requestedPath;
    m_downloadLocalPath.clear();
    if (requestedPath.isEmpty()) {
        failDownload(QStringLiteral("文件路径为空"));
        return;
    }
    if (!destination.isValid() || !destination.isLocalFile()) {
        failDownload(QStringLiteral("请选择有效的本地保存位置"));
        return;
    }

    const QUrl sourceUrl(fileContentUrl(requestedPath));
    const QString scheme = sourceUrl.scheme().toLower();
    if (!sourceUrl.isValid() || scheme.isEmpty()) {
        failDownload(QStringLiteral("文件地址无效"));
        return;
    }
    if (scheme != QStringLiteral("http")
        && scheme != QStringLiteral("https")
        && scheme != QStringLiteral("file")
        && scheme != QStringLiteral("qrc")) {
        failDownload(QStringLiteral("不支持此文件地址协议：%1").arg(scheme));
        return;
    }

    m_downloadLocalPath = destination.toLocalFile();
    const QFileInfo destinationInfo(m_downloadLocalPath);
    if (m_downloadLocalPath.isEmpty() || destinationInfo.isDir()) {
        failDownload(QStringLiteral("保存位置不是有效文件路径"));
        return;
    }
    if (!QDir(destinationInfo.absolutePath()).exists()) {
        failDownload(QStringLiteral("保存目录不存在"));
        return;
    }

    m_downloadFile = new QSaveFile(m_downloadLocalPath, this);
    if (!m_downloadFile->open(QIODevice::WriteOnly)) {
        failDownload(QStringLiteral("无法写入保存位置：%1")
                         .arg(m_downloadFile->errorString()));
        return;
    }

    setDownloading(true);
    if (m_folderDownloadActive) {
        setListStatus(QStringLiteral("正在下载文件夹：%1/%2 个文件，当前：%3")
                          .arg(m_folderCompletedFiles + 1)
                          .arg(m_folderTotalFiles)
                          .arg(fileNameForPath(requestedPath)));
    } else {
        setListStatus(QStringLiteral("正在下载：%1")
                          .arg(fileNameForPath(requestedPath)));
    }

    if (scheme == QStringLiteral("file") || scheme == QStringLiteral("qrc")) {
        QString error;
        if (!copyUrlToDevice(sourceUrl, m_downloadFile, &error)) {
            failDownload(error);
            return;
        }
        finishDownload();
        return;
    }

    QNetworkRequest request(sourceUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/octet-stream"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(120000);

    QNetworkReply *reply = m_network.get(request);
    m_downloadReply = reply;
    connect(reply, &QIODevice::readyRead, this, [this, reply]() {
        if (reply != m_downloadReply)
            return;

        const QByteArray data = reply->readAll();
        if (!data.isEmpty()
            && (!m_downloadFile || m_downloadFile->write(data) != data.size())) {
            failDownload(QStringLiteral("写入下载文件失败"));
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply != m_downloadReply)
            return;

        m_downloadReply = nullptr;
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
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
            failDownload(QStringLiteral("文件下载失败：%1").arg(error));
            return;
        }
        if (!remainingData.isEmpty()
            && (!m_downloadFile
                || m_downloadFile->write(remainingData) != remainingData.size())) {
            failDownload(QStringLiteral("写入下载文件失败"));
            return;
        }
        finishDownload();
    });
}

void UploadManager::finishDownload()
{
    if (!m_downloadFile) {
        failDownload(QStringLiteral("下载目标文件不存在"));
        return;
    }
    if (!m_downloadFile->commit()) {
        failDownload(QStringLiteral("无法完成下载文件写入：%1")
                         .arg(m_downloadFile->errorString()));
        return;
    }

    if (m_folderDownloadActive) {
        ++m_folderCompletedFiles;
        delete m_downloadFile;
        m_downloadFile = nullptr;
        m_downloadCloudPath.clear();
        m_downloadLocalPath.clear();
        setListStatus(QStringLiteral("正在下载文件夹：%1/%2 个文件")
                          .arg(m_folderCompletedFiles)
                          .arg(m_folderTotalFiles));
        QTimer::singleShot(0, this, &UploadManager::downloadNextFolderFile);
        return;
    }

    const QString cloudPath = m_downloadCloudPath;
    const QString localPath = m_downloadLocalPath;
    delete m_downloadFile;
    m_downloadFile = nullptr;
    m_downloadCloudPath.clear();
    m_downloadLocalPath.clear();
    setDownloading(false);
    setListStatus(QStringLiteral("下载完成：%1").arg(localPath));
    emit fileDownloaded(cloudPath, localPath);
}

void UploadManager::failDownload(const QString &reason)
{
    if (m_folderDownloadActive) {
        failFolderDownload(reason);
        return;
    }

    const QString cloudPath = m_downloadCloudPath;
    resetDownload();
    m_downloadCloudPath.clear();
    m_downloadLocalPath.clear();
    setDownloading(false);
    setListStatus(QStringLiteral("下载失败：%1").arg(reason));
    emit fileDownloadFailed(cloudPath, reason);
}

void UploadManager::resetDownload()
{
    if (m_downloadReply) {
        QNetworkReply *reply = m_downloadReply;
        m_downloadReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_downloadFile) {
        if (m_downloadFile->isOpen())
            m_downloadFile->cancelWriting();
        delete m_downloadFile;
        m_downloadFile = nullptr;
    }
}

void UploadManager::downloadFolder(const QString &path, const QUrl &destination)
{
    const QString requestedPath = path.trimmed();
    auto failStart = [this, requestedPath](const QString &reason) {
        setListStatus(QStringLiteral("文件夹下载失败：%1").arg(reason));
        emit folderDownloadFailed(requestedPath, reason);
    };

    if (m_downloading) {
        failStart(QStringLiteral("正在下载其他内容，请稍后再试"));
        return;
    }

    QString normalizedPath;
    if (!normalizeCloudPath(requestedPath, &normalizedPath) || normalizedPath.isEmpty()) {
        failStart(QStringLiteral("文件夹路径无效或不安全"));
        return;
    }
    if (!destination.isValid() || !destination.isLocalFile()) {
        failStart(QStringLiteral("请选择有效的本地保存目录"));
        return;
    }

    const QFileInfo destinationInfo(destination.toLocalFile());
    if (!destinationInfo.exists() || !destinationInfo.isDir()) {
        failStart(QStringLiteral("保存位置不是有效目录"));
        return;
    }

    QString folderName = fileNameForPath(normalizedPath);
    if (folderName.isEmpty())
        folderName = QStringLiteral("下载的文件夹");

    // 自动避开已有目录，禁止把本次文件合并或覆盖到用户的同名目录中。
    const QDir destinationDirectory(destinationInfo.absoluteFilePath());
    QString candidateName = folderName;
    QString localRoot = destinationDirectory.filePath(candidateName);
    int suffix = 0;
    while (QFileInfo::exists(localRoot)) {
        candidateName = QStringLiteral("%1 (%2)").arg(folderName).arg(++suffix);
        localRoot = destinationDirectory.filePath(candidateName);
    }
    if (!QDir().mkpath(localRoot)) {
        failStart(QStringLiteral("无法创建本地保存文件夹"));
        return;
    }

    resetFolderDownload();
    m_folderCloudPath = normalizedPath;
    m_folderLocalRoot = QDir(localRoot).absolutePath();
    m_folderPendingDirectories.enqueue(normalizedPath);
    m_folderKnownDirectories.insert(normalizedPath);
    m_folderDownloadActive = true;
    setDownloading(true);
    setListStatus(QStringLiteral("正在扫描文件夹：%1").arg(folderName));
    processNextFolderDirectory();
}

void UploadManager::processNextFolderDirectory()
{
    if (!m_folderDownloadActive || m_shuttingDown)
        return;
    if (m_folderPendingDirectories.isEmpty()) {
        downloadNextFolderFile();
        return;
    }

    QUrl endpoint(m_fileListUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        failFolderDownload(QStringLiteral("文件列表地址无效"));
        return;
    }

    const QString requestedDirectory = m_folderPendingDirectories.dequeue();
    QUrlQuery query(endpoint);
    query.removeQueryItem(QStringLiteral("path"));
    query.addQueryItem(QStringLiteral("path"), requestedDirectory);
    endpoint.setQuery(query);

    QNetworkRequest request(endpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/json"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setTransferTimeout(30000);

    QNetworkReply *reply = m_network.get(request);
    m_folderListReply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, requestedDirectory]() {
        if (reply != m_folderListReply || !m_folderDownloadActive)
            return;

        m_folderListReply = nullptr;
        const QByteArray body = reply->readAll();
        const int httpStatus = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QString error;
        if (reply->error() != QNetworkReply::NoError
            || (httpStatus != 0 && (httpStatus < 200 || httpStatus >= 300))) {
            error = reply->errorString();
            if (httpStatus > 0)
                error = QStringLiteral("HTTP %1：%2").arg(httpStatus).arg(error);
        }
        reply->deleteLater();

        if (!error.isEmpty()) {
            failFolderDownload(QStringLiteral("读取目录失败：%1").arg(error));
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            failFolderDownload(QStringLiteral("服务器返回的目录列表不是有效 JSON 对象"));
            return;
        }

        const QJsonObject rootObject = document.object();
        if (rootObject.contains(QStringLiteral("success"))
            && !rootObject.value(QStringLiteral("success")).toBool()) {
            failFolderDownload(rootObject.value(QStringLiteral("message")).toString(
                QStringLiteral("服务器未能返回目录列表")));
            return;
        }

        QJsonObject listObject = rootObject;
        if (rootObject.value(QStringLiteral("data")).isObject())
            listObject = rootObject.value(QStringLiteral("data")).toObject();

        QJsonArray entries;
        bool hasList = false;
        if (listObject.value(QStringLiteral("items")).isArray()) {
            entries = listObject.value(QStringLiteral("items")).toArray();
            hasList = true;
        } else {
            // 兼容旧接口；旧 directories 数组未必显式带有 kind 字段。
            if (listObject.value(QStringLiteral("directories")).isArray()) {
                const QJsonArray directories = listObject.value(
                    QStringLiteral("directories")).toArray();
                for (const QJsonValue &value : directories) {
                    if (!value.isObject())
                        continue;
                    QJsonObject object = value.toObject();
                    object.insert(QStringLiteral("kind"), QStringLiteral("folder"));
                    entries.append(object);
                }
                hasList = true;
            }
            if (listObject.value(QStringLiteral("files")).isArray()) {
                const QJsonArray files = listObject.value(QStringLiteral("files")).toArray();
                for (const QJsonValue &value : files) {
                    if (!value.isObject())
                        continue;
                    QJsonObject object = value.toObject();
                    object.insert(QStringLiteral("kind"), QStringLiteral("file"));
                    entries.append(object);
                }
                hasList = true;
            }
        }
        if (!hasList) {
            failFolderDownload(QStringLiteral("目录列表响应缺少 items 或 files/directories 数组"));
            return;
        }

        const QString directoryPrefix = requestedDirectory.isEmpty()
            ? QString() : requestedDirectory + QLatin1Char('/');
        const QString rootPrefix = m_folderCloudPath + QLatin1Char('/');
        for (const QJsonValue &value : entries) {
            if (!value.isObject())
                continue;

            QJsonObject object = value.toObject();
            QString name = object.value(QStringLiteral("name")).toString();
            QString itemPath = object.value(QStringLiteral("path")).toString();
            if (name.isEmpty() && !itemPath.isEmpty())
                name = QFileInfo(itemPath).fileName();
            if (name.isEmpty())
                continue;
            if (itemPath.isEmpty()) {
                itemPath = requestedDirectory.isEmpty()
                    ? name : requestedDirectory + QLatin1Char('/') + name;
            }
            object.insert(QStringLiteral("name"), name);
            object.insert(QStringLiteral("path"), itemPath);

            const QVariantMap item = makeFileItem(object);
            QString childPath;
            if (!normalizeCloudPath(item.value(QStringLiteral("path")).toString(),
                                    &childPath) || childPath.isEmpty()) {
                failFolderDownload(QStringLiteral("服务器返回了无效的子项路径"));
                return;
            }

            // 当前接口应只返回直接子项，拒绝伪造的父目录或跨目录路径。
            if ((!directoryPrefix.isEmpty() && !childPath.startsWith(directoryPrefix))
                || !childPath.startsWith(rootPrefix)) {
                failFolderDownload(QStringLiteral("服务器返回了超出下载范围的子项路径"));
                return;
            }
            const QString directName = directoryPrefix.isEmpty()
                ? childPath : childPath.mid(directoryPrefix.size());
            if (directName.isEmpty() || directName.contains(QLatin1Char('/'))) {
                failFolderDownload(QStringLiteral("服务器返回的子项不是当前目录的直接子项"));
                return;
            }

            const QString relativePath = childPath.mid(rootPrefix.size());
            if (relativePath.isEmpty()) {
                failFolderDownload(QStringLiteral("服务器返回了无效的本地相对路径"));
                return;
            }
            const QString localPath = QDir(m_folderLocalRoot).filePath(relativePath);
            const bool isDirectory = item.value(QStringLiteral("kind")).toString()
                                     == QStringLiteral("folder");
            if (isDirectory) {
                if (m_folderKnownDirectories.contains(childPath))
                    continue;
                if (!QDir().mkpath(localPath)) {
                    failFolderDownload(QStringLiteral("无法创建本地子目录：%1")
                                           .arg(relativePath));
                    return;
                }
                m_folderKnownDirectories.insert(childPath);
                m_folderPendingDirectories.enqueue(childPath);
            } else {
                if (m_folderKnownFiles.contains(childPath))
                    continue;
                if (!QDir().mkpath(QFileInfo(localPath).absolutePath())) {
                    failFolderDownload(QStringLiteral("无法创建文件保存目录：%1")
                                           .arg(relativePath));
                    return;
                }
                m_folderKnownFiles.insert(childPath);
                m_folderFileQueue.enqueue(FolderFileTask{childPath, localPath});
                ++m_folderTotalFiles;
            }
        }

        processNextFolderDirectory();
    });
}

void UploadManager::downloadNextFolderFile()
{
    if (!m_folderDownloadActive || m_shuttingDown)
        return;
    if (m_folderFileQueue.isEmpty()) {
        finishFolderDownload();
        return;
    }

    const FolderFileTask task = m_folderFileQueue.dequeue();
    setListStatus(QStringLiteral("正在下载文件夹：%1/%2 个文件")
                      .arg(m_folderCompletedFiles + 1)
                      .arg(m_folderTotalFiles));
    startFileDownload(task.cloudPath, QUrl::fromLocalFile(task.localPath));
}

void UploadManager::finishFolderDownload()
{
    const QString cloudPath = m_folderCloudPath;
    const QString localPath = m_folderLocalRoot;
    const int fileCount = m_folderTotalFiles;
    resetFolderDownload();
    m_folderDownloadActive = false;
    setDownloading(false);
    setListStatus(QStringLiteral("文件夹下载完成：%1（%2 个文件）")
                      .arg(localPath)
                      .arg(fileCount));
    emit folderDownloaded(cloudPath, localPath);
}

void UploadManager::failFolderDownload(const QString &reason)
{
    const QString cloudPath = m_folderCloudPath;
    const QString localRoot = m_folderLocalRoot;
    resetDownload();
    resetFolderDownload();
    m_folderDownloadActive = false;
    setDownloading(false);

    // 本地根目录由本次任务新建，失败时可安全清理，不会触碰用户已有目录。
    if (!localRoot.isEmpty() && !QDir(localRoot).removeRecursively()) {
        qWarning().noquote() << QStringLiteral("无法完整清理失败的文件夹下载目录：%1")
                                    .arg(localRoot);
    }
    setListStatus(QStringLiteral("文件夹下载失败：%1").arg(reason));
    emit folderDownloadFailed(cloudPath, reason);
}

void UploadManager::resetFolderDownload()
{
    if (m_folderListReply) {
        QNetworkReply *reply = m_folderListReply;
        m_folderListReply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    m_folderPendingDirectories.clear();
    m_folderFileQueue.clear();
    m_folderKnownDirectories.clear();
    m_folderKnownFiles.clear();
    m_folderCloudPath.clear();
    m_folderLocalRoot.clear();
    m_folderTotalFiles = 0;
    m_folderCompletedFiles = 0;
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

    QUrl endpoint(m_serverUrl);
    if (!endpoint.isValid()
        || (endpoint.scheme() != QStringLiteral("http")
            && endpoint.scheme() != QStringLiteral("https"))) {
        setStatusText(QStringLiteral("上传地址无效：请填写 http 或 https 地址"));
        emit fileUploadFailed(QString(), m_statusText);
        return;
    }

    // 上传任务固定到发起时所在目录，即使用户随后切换目录也不会改变目标。
    m_uploadDirectory = m_currentPath;

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

    QUrl endpoint(m_serverUrl);
    QUrlQuery uploadQuery(endpoint);
    uploadQuery.removeQueryItem(QStringLiteral("path"));
    if (!m_uploadDirectory.isEmpty())
        uploadQuery.addQueryItem(QStringLiteral("path"), m_uploadDirectory);
    endpoint.setQuery(uploadQuery);

    QNetworkRequest request{endpoint};
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
    updateSyncingFileCount();
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

void UploadManager::setRenaming(bool value)
{
    if (m_renaming == value)
        return;
    m_renaming = value;
    emit renamingChanged();
}

void UploadManager::setMoving(bool value)
{
    if (m_moving == value)
        return;
    m_moving = value;
    emit movingChanged();
}

void UploadManager::setLoadingFolderChoices(bool value)
{
    if (m_loadingFolderChoices == value)
        return;
    m_loadingFolderChoices = value;
    emit loadingFolderChoicesChanged();
}

void UploadManager::setOpeningFile(bool value)
{
    if (m_openingFile == value)
        return;
    m_openingFile = value;
    emit openingFileChanged();
}

void UploadManager::setDownloading(bool value)
{
    if (m_downloading == value)
        return;
    m_downloading = value;
    emit downloadingChanged();
}

void UploadManager::setLoadingFavorites(bool value)
{
    if (m_loadingFavorites == value)
        return;
    m_loadingFavorites = value;
    emit loadingFavoritesChanged();
}

void UploadManager::setUpdatingFavorite(bool value)
{
    if (m_updatingFavorite == value)
        return;
    m_updatingFavorite = value;
    emit updatingFavoriteChanged();
}

void UploadManager::setDeleting(bool value)
{
    if (m_deleting == value)
        return;
    m_deleting = value;
    emit deletingChanged();
}

void UploadManager::setLoadingTrash(bool value)
{
    if (m_loadingTrash == value)
        return;
    m_loadingTrash = value;
    emit loadingTrashChanged();
}

void UploadManager::setUpdatingTrash(bool value)
{
    if (m_updatingTrash == value)
        return;
    m_updatingTrash = value;
    emit updatingTrashChanged();
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

void UploadManager::setCloudFileCount(int value)
{
    value = qMax(0, value);
    if (m_cloudFileCount == value)
        return;
    m_cloudFileCount = value;
    emit cloudFileCountChanged();
}

void UploadManager::setSyncedFileCount(int value)
{
    value = qMax(0, value);
    if (m_syncedFileCount == value)
        return;
    m_syncedFileCount = value;
    emit syncedFileCountChanged();
}

void UploadManager::setSyncingFileCount(int value)
{
    value = qMax(0, value);
    if (m_syncingFileCount == value)
        return;
    m_syncingFileCount = value;
    emit syncingFileCountChanged();
}

void UploadManager::updateSyncingFileCount()
{
    const int activeUploads = m_uploading && m_uploadDirectory == m_currentPath
        ? qMax(0, m_totalCount - m_completedCount) : 0;
    setSyncingFileCount(m_serverSyncingFileCount + activeUploads);
}

void UploadManager::setCompletedCount(int value)
{
    if (m_completedCount == value)
        return;
    m_completedCount = value;
    emit completedCountChanged();
    updateSyncingFileCount();
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
