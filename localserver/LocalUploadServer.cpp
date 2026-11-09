#include "LocalUploadServer.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMimeDatabase>
#include <QMimeType>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>
#include <QWebSocket>
#include <QWebSocketProtocol>

#include <QDebug>

#include <algorithm>
#include <functional>
#include <limits>
#include <utility>

namespace {

QString uploadedFilesPath()
{
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uploaded_files"));
}

QString trashFilesPath()
{
    // 回收站与被监听的 uploaded_files 完全分离，删除后不会再出现在正常文件列表中。
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uploaded_files_trash"));
}

QString itemOrderFilePath()
{
    // 顺序表不放在 uploaded_files 内，避免被当成用户文件展示或纳入目录监听。
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uploaded_files_order.json"));
}

QString favoritesFilePath()
{
    // 收藏元数据同样独立于用户文件，重启服务后仍可恢复。
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uploaded_files_favorites.json"));
}

QString displayFavoriteTime(const QString &storedValue)
{
    const QDateTime utcTime = QDateTime::fromString(storedValue, Qt::ISODateWithMs);
    const QDateTime isoTime = utcTime.isValid()
        ? utcTime : QDateTime::fromString(storedValue, Qt::ISODate);
    return isoTime.isValid()
        ? isoTime.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"))
        : storedValue;
}

// 将客户端传入的云端相对路径限制在上传根目录内。空字符串和 "." 均表示根目录。
bool cleanCloudPath(const QString &requestedPath, QString *cleanPath, QString *error)
{
    const QString relativePath = QDir::fromNativeSeparators(requestedPath);
    const QString cleaned = QDir::cleanPath(relativePath);
    if (relativePath.contains(QLatin1Char('\0'))
        || QDir::isAbsolutePath(relativePath)
        || cleaned == QStringLiteral("..")
        || cleaned.startsWith(QStringLiteral("../"))
        || cleaned.startsWith(QLatin1Char('/'))) {
        *error = QStringLiteral("目录路径不安全");
        return false;
    }

    *cleanPath = cleaned == QStringLiteral(".") ? QString() : cleaned;
    return true;
}

bool resolveCloudDirectory(const QDir &rootDir,
                           const QString &requestedPath,
                           QDir *directory,
                           QString *relativePath,
                           QString *error)
{
    QString cleaned;
    if (!cleanCloudPath(requestedPath, &cleaned, error))
        return false;

    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    if (canonicalRoot.isEmpty()) {
        *error = QStringLiteral("文件存储目录不可用");
        return false;
    }

    if (cleaned.isEmpty()) {
        *directory = QDir(canonicalRoot);
        relativePath->clear();
        return true;
    }

    const QFileInfo targetInfo(rootDir.filePath(cleaned));
    const QString canonicalTarget = QDir::fromNativeSeparators(targetInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (!targetInfo.exists() || !targetInfo.isDir() || targetInfo.isSymLink()
        || canonicalTarget.isEmpty() || !canonicalTarget.startsWith(rootPrefix)) {
        *error = QStringLiteral("目录不存在或不可访问");
        return false;
    }

    *directory = QDir(canonicalTarget);
    *relativePath = cleaned;
    return true;
}

Qt::CaseSensitivity fileSystemCaseSensitivity()
{
#ifdef Q_OS_WIN
    return Qt::CaseInsensitive;
#else
    return Qt::CaseSensitive;
#endif
}

bool isSameOrDescendantPath(const QString &path, const QString &directory)
{
    const QString cleanPath = QDir::fromNativeSeparators(QDir::cleanPath(path));
    const QString cleanDirectory = QDir::fromNativeSeparators(QDir::cleanPath(directory));
    const Qt::CaseSensitivity sensitivity = fileSystemCaseSensitivity();
    if (cleanPath.compare(cleanDirectory, sensitivity) == 0)
        return true;

    const QString prefix = cleanDirectory.endsWith(QLatin1Char('/'))
        ? cleanDirectory : cleanDirectory + QLatin1Char('/');
    return cleanPath.startsWith(prefix, sensitivity);
}

// 跨挂载卷移动时，先复制到目标父目录中的临时目录，再一次性重命名为最终项目。
// 源目录中的符号链接会被拒绝，避免递归复制到存储根目录之外。
bool copyPathRecursively(const QFileInfo &sourceInfo,
                         const QString &targetPath,
                         QString *error)
{
    if (sourceInfo.isSymLink()) {
        *error = QStringLiteral("源项目中包含符号链接，无法安全地跨卷复制");
        return false;
    }

    if (sourceInfo.isDir()) {
        if (!QDir().mkpath(targetPath)) {
            *error = QStringLiteral("无法在目标位置创建目录，请检查写入权限");
            return false;
        }

        const QDir sourceDirectory(sourceInfo.absoluteFilePath());
        const QFileInfoList entries = sourceDirectory.entryInfoList(
            QDir::AllEntries | QDir::NoDotAndDotDot, QDir::NoSort);
        for (const QFileInfo &childInfo : entries) {
            if (!copyPathRecursively(
                    childInfo, QDir(targetPath).filePath(childInfo.fileName()), error)) {
                return false;
            }
        }
        return true;
    }

    if (sourceInfo.isFile()) {
        if (QFileInfo::exists(targetPath) || QFileInfo(targetPath).isSymLink()) {
            *error = QStringLiteral("目标位置已存在同名项目");
            return false;
        }
        if (!QFile::copy(sourceInfo.absoluteFilePath(), targetPath)) {
            *error = QStringLiteral("复制文件失败，请检查磁盘空间和目录权限");
            return false;
        }
        return true;
    }

    *error = QStringLiteral("不支持移动此文件类型");
    return false;
}

bool moveFileOrDirectory(const QString &sourcePath,
                         const QString &targetPath,
                         QString *error)
{
    if (QFile::rename(sourcePath, targetPath))
        return true;

    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() || sourceInfo.isSymLink()
        || (!sourceInfo.isFile() && !sourceInfo.isDir())) {
        *error = QStringLiteral("原文件或文件夹已不存在，或不可移动");
        return false;
    }
    if (QFileInfo::exists(targetPath) || QFileInfo(targetPath).isSymLink()) {
        *error = QStringLiteral("目标文件夹中已存在同名文件或文件夹");
        return false;
    }

    QTemporaryDir stagingDirectory(
        QDir(QFileInfo(targetPath).absolutePath()).filePath(
            QStringLiteral(".filesync-move-XXXXXX")));
    if (!stagingDirectory.isValid()) {
        *error = QStringLiteral("无法在目标磁盘创建移动暂存目录，请检查写入权限");
        return false;
    }

    const QString stagedPath = QDir(stagingDirectory.path()).filePath(
        QStringLiteral("payload"));
    if (!copyPathRecursively(sourceInfo, stagedPath, error))
        return false;

    if (QFileInfo::exists(targetPath) || QFileInfo(targetPath).isSymLink()) {
        *error = QStringLiteral("移动期间目标位置出现了同名项目，已取消移动");
        return false;
    }
    if (!QFile::rename(stagedPath, targetPath)) {
        *error = QStringLiteral("无法将暂存内容提交到目标文件夹");
        return false;
    }

    if (sourceInfo.isDir()) {
        if (!QDir(sourceInfo.absoluteFilePath()).removeRecursively()) {
            *error = QStringLiteral(
                "内容已复制到目标位置，但源文件夹未能完全删除；请检查源目录权限和残留项目");
            return false;
        }
    } else if (!QFile::remove(sourceInfo.absoluteFilePath())) {
        *error = QStringLiteral(
            "文件已复制到目标位置，但源文件未能删除；请检查源文件是否被占用");
        return false;
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

    // 使用单级名称并限制跨平台非法字符，不能借该接口创建或进入嵌套路径。
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

QString formatFileSize(qint64 bytes)
{
    if (bytes < 1024)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1024LL * 1024LL)
        return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < 1024LL * 1024LL * 1024LL)
        return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}

bool isTextMimeName(const QString &mimeName)
{
    if (mimeName.startsWith(QStringLiteral("image/")))
        return false;
    if (mimeName.startsWith(QStringLiteral("text/")))
        return true;

    static const QSet<QString> textMimeNames{
        QStringLiteral("application/json"),
        QStringLiteral("application/x-ndjson"),
        QStringLiteral("application/xml"),
        QStringLiteral("application/javascript"),
        QStringLiteral("application/x-javascript"),
        QStringLiteral("application/yaml"),
        QStringLiteral("application/x-yaml"),
        QStringLiteral("application/sql"),
        QStringLiteral("application/toml"),
        QStringLiteral("application/x-toml"),
        QStringLiteral("application/x-sh"),
        QStringLiteral("application/x-httpd-php")
    };
    return textMimeNames.contains(mimeName)
           || mimeName.endsWith(QStringLiteral("+json"))
           || mimeName.endsWith(QStringLiteral("+xml"));
}

bool hasTextExtension(const QString &suffix)
{
    static const QSet<QString> textExtensions{
        QStringLiteral("txt"), QStringLiteral("md"), QStringLiteral("markdown"),
        QStringLiteral("log"), QStringLiteral("json"), QStringLiteral("xml"),
        QStringLiteral("yaml"), QStringLiteral("yml"), QStringLiteral("toml"),
        QStringLiteral("csv"), QStringLiteral("tsv"), QStringLiteral("ini"),
        QStringLiteral("cfg"), QStringLiteral("conf"), QStringLiteral("properties"),
        QStringLiteral("html"), QStringLiteral("htm"), QStringLiteral("css"),
        QStringLiteral("js"), QStringLiteral("ts"), QStringLiteral("qml"),
        QStringLiteral("c"), QStringLiteral("h"), QStringLiteral("cpp"),
        QStringLiteral("hpp"), QStringLiteral("cc"), QStringLiteral("cxx"),
        QStringLiteral("java"), QStringLiteral("py"), QStringLiteral("sh"),
        QStringLiteral("bat"), QStringLiteral("sql"), QStringLiteral("vue"),
        QStringLiteral("php"), QStringLiteral("rb"), QStringLiteral("go"),
        QStringLiteral("rs"), QStringLiteral("tex"), QStringLiteral("diff"),
        QStringLiteral("patch"), QStringLiteral("srt")
    };
    return textExtensions.contains(suffix.toLower());
}

QMimeType detectMimeType(const QFileInfo &fileInfo)
{
    QMimeDatabase mimeDatabase;
    QMimeType mimeType = mimeDatabase.mimeTypeForFile(fileInfo, QMimeDatabase::MatchExtension);
    if (mimeType.name() == QStringLiteral("application/octet-stream"))
        mimeType = mimeDatabase.mimeTypeForFile(fileInfo.absoluteFilePath(), QMimeDatabase::MatchContent);
    return mimeType;
}

QString previewTypeForFile(const QFileInfo &fileInfo, const QString &mimeName)
{
    if (mimeName.startsWith(QStringLiteral("image/")))
        return QStringLiteral("image");
    if (isTextMimeName(mimeName) || hasTextExtension(fileInfo.suffix()))
        return QStringLiteral("text");
    return QStringLiteral("binary");
}

QByteArray completeUtf8Prefix(const QByteArray &data)
{
    if (data.isEmpty())
        return data;

    const int size = data.size();
    int sequenceStart = size - 1;
    int continuationCount = 0;
    while (sequenceStart > 0 && continuationCount < 3) {
        const unsigned char byte = static_cast<unsigned char>(data.at(sequenceStart));
        if ((byte & 0xC0) != 0x80)
            break;
        --sequenceStart;
        ++continuationCount;
    }

    const unsigned char lead = static_cast<unsigned char>(data.at(sequenceStart));
    int expectedLength = 0;
    if (lead < 0x80)
        expectedLength = 1;
    else if ((lead & 0xE0) == 0xC0)
        expectedLength = 2;
    else if ((lead & 0xF0) == 0xE0)
        expectedLength = 3;
    else if ((lead & 0xF8) == 0xF0)
        expectedLength = 4;

    const int availableLength = size - sequenceStart;
    if (expectedLength > availableLength)
        return data.left(sequenceStart);
    return data;
}

void fileIconColors(const QString &extension, QString *background, QString *foreground)
{
    const QString ext = extension.toUpper();
    *background = QStringLiteral("#EEF2FF");
    *foreground = QStringLiteral("#4B6EF5");

    if (ext == QStringLiteral("PDF")) {
        *background = QStringLiteral("#FFF0EF");
        *foreground = QStringLiteral("#E47772");
    } else if (ext == QStringLiteral("DOC") || ext == QStringLiteral("DOCX")) {
        *background = QStringLiteral("#EAF2FF");
        *foreground = QStringLiteral("#4C83D9");
    } else if (ext == QStringLiteral("XLS") || ext == QStringLiteral("XLSX")
               || ext == QStringLiteral("CSV")) {
        *background = QStringLiteral("#EAF8F2");
        *foreground = QStringLiteral("#28A879");
    } else if (ext == QStringLiteral("PPT") || ext == QStringLiteral("PPTX")) {
        *background = QStringLiteral("#FFF0E9");
        *foreground = QStringLiteral("#E58A54");
    } else if (ext == QStringLiteral("ZIP") || ext == QStringLiteral("RAR")
               || ext == QStringLiteral("7Z") || ext == QStringLiteral("TAR")) {
        *background = QStringLiteral("#FFF5E8");
        *foreground = QStringLiteral("#D99A42");
    } else if (ext == QStringLiteral("JPG") || ext == QStringLiteral("JPEG")
               || ext == QStringLiteral("PNG") || ext == QStringLiteral("GIF")
               || ext == QStringLiteral("WEBP")) {
        *background = QStringLiteral("#F1ECFF");
        *foreground = QStringLiteral("#8A6AE8");
    }
}

/*
 * 递归扫描目录。
 * items 中采用扁平列表保存所有条目，path 字段保留相对 uploaded_files 的路径。
 * 文件夹排在其子项目之前，fileCount 表示该文件夹下递归包含的文件总数。
 */
int appendDirectoryItems(const QDir &directory,
                         const QString &relativeDirectory,
                         QJsonArray *items,
                         const QHash<QString, quint64> &itemOrder)
{
    int fileCount = 0;
    QFileInfoList entries = directory.entryInfoList(
        QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Readable,
        QDir::NoSort);

    auto cloudPathForEntry = [&relativeDirectory](const QFileInfo &info) {
        return relativeDirectory.isEmpty()
            ? info.fileName()
            : relativeDirectory + QLatin1Char('/') + info.fileName();
    };

    // 文件夹始终在前；同类条目只按首次上传/创建时分配的顺序号升序排列。
    // 不再使用名称或修改时间排序，因此重命名不会改变条目位置。
    std::stable_sort(entries.begin(), entries.end(),
                     [&itemOrder, &cloudPathForEntry](const QFileInfo &left,
                                                      const QFileInfo &right) {
        if (left.isDir() != right.isDir())
            return left.isDir();

        const quint64 missingOrder = std::numeric_limits<quint64>::max();
        const quint64 leftOrder = itemOrder.value(cloudPathForEntry(left), missingOrder);
        const quint64 rightOrder = itemOrder.value(cloudPathForEntry(right), missingOrder);
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;

        // 正常情况下每个条目都有唯一顺序号；此处仅为旧数据或异常数据提供确定性兜底。
        const int nameComparison = left.fileName().compare(right.fileName(), Qt::CaseInsensitive);
        return nameComparison != 0 ? nameComparison < 0
                                   : left.fileName() < right.fileName();
    });

    for (const QFileInfo &info : entries) {
        // 不跟随符号链接，避免循环目录或意外扫描上传目录之外的内容。
        if (info.isSymLink())
            continue;

        const QString relativePath = relativeDirectory.isEmpty()
            ? info.fileName()
            : relativeDirectory + QLatin1Char('/') + info.fileName();

        if (info.isDir()) {
            // 先放置占位项，递归完成后再补上文件夹的文件数量。
            const int folderIndex = items->size();
            items->append(QJsonObject());

            const int childFileCount = appendDirectoryItems(
                QDir(info.absoluteFilePath()), relativePath, items, itemOrder);

            const QJsonObject folderObject{
                {QStringLiteral("name"), info.fileName()},
                {QStringLiteral("path"), relativePath},
                {QStringLiteral("kind"), QStringLiteral("folder")},
                {QStringLiteral("ext"), QStringLiteral("文件夹")},
                {QStringLiteral("modified"), info.lastModified().toString(
                     QStringLiteral("yyyy-MM-dd HH:mm"))},
                {QStringLiteral("size"), QStringLiteral("%1 个文件").arg(childFileCount)},
                {QStringLiteral("fileCount"), childFileCount},
                {QStringLiteral("status"), QStringLiteral("已同步")},
                {QStringLiteral("iconBg"), QStringLiteral("#FFF5E3")},
                {QStringLiteral("iconColor"), QStringLiteral("#E9AD4E")}
            };
            items->replace(folderIndex, folderObject);
            fileCount += childFileCount;
        } else if (info.isFile()) {
            const QString extension = info.suffix().isEmpty()
                ? QStringLiteral("FILE") : info.suffix().toUpper();
            QString iconBg;
            QString iconColor;
            fileIconColors(extension, &iconBg, &iconColor);
            const QString mimeName = detectMimeType(info).name();

            const QJsonObject fileObject{
                {QStringLiteral("name"), info.fileName()},
                {QStringLiteral("path"), relativePath},
                {QStringLiteral("kind"), QStringLiteral("file")},
                {QStringLiteral("ext"), extension},
                {QStringLiteral("modified"), info.lastModified().toString(
                     QStringLiteral("yyyy-MM-dd HH:mm"))},
                {QStringLiteral("size"), formatFileSize(info.size())},
                {QStringLiteral("sizeBytes"), static_cast<double>(info.size())},
                {QStringLiteral("status"), QStringLiteral("已同步")},
                {QStringLiteral("iconBg"), iconBg},
                {QStringLiteral("iconColor"), iconColor},
                {QStringLiteral("mimeType"), mimeName},
                {QStringLiteral("previewType"), previewTypeForFile(info, mimeName)}
            };
            items->append(fileObject);
            ++fileCount;
        }
    }

    return fileCount;
}

} // namespace

LocalUploadServer::LocalUploadServer(QObject *parent)
    : QObject(parent)
    , m_server()
    , m_eventServer(QStringLiteral("FileSync Events"),
                    QWebSocketServer::NonSecureMode)
{
    connect(&m_server, &QTcpServer::newConnection, this, [this]() {
        while (m_server.hasPendingConnections()) {
            QTcpSocket *socket = m_server.nextPendingConnection();
            m_buffers.insert(socket, QByteArray());

            connect(socket, &QTcpSocket::readyRead, this,
                    [this, socket]() { readRequest(socket); });
            connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
                m_buffers.remove(socket);
                socket->deleteLater();
            });
        }
    });

    connect(&m_eventServer, &QWebSocketServer::newConnection,
            this, &LocalUploadServer::handleEventConnection);

    // 目录信号覆盖新增、删除和重命名；文件信号覆盖内容及元数据修改。
    connect(&m_fileWatcher, &QFileSystemWatcher::directoryChanged,
            this, [this](const QString &path) {
        queueFileChange(cloudPathForFileName(path));
    });
    connect(&m_fileWatcher, &QFileSystemWatcher::fileChanged,
            this, [this](const QString &path) {
        queueFileChange(cloudPathForFileName(path));
    });

    // 高频变更合并为一个事件，避免客户端因一次保存操作反复刷新。
    m_changeTimer.setSingleShot(true);
    m_changeTimer.setInterval(250);
    connect(&m_changeTimer, &QTimer::timeout,
            this, &LocalUploadServer::broadcastFileChanges);
}

bool LocalUploadServer::listen(quint16 port, quint16 eventPort)
{
    if (m_server.isListening() || m_eventServer.isListening()) {
        qWarning().noquote() << QStringLiteral("FileSync 服务已经在监听");
        return false;
    }

    const quint32 resolvedEventPort = eventPort == 0
        ? static_cast<quint32>(port) + 1 : static_cast<quint32>(eventPort);
    if (resolvedEventPort > 65535) {
        qCritical().noquote() << QStringLiteral("WebSocket 端口无效");
        return false;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        QDir appDir(QCoreApplication::applicationDirPath());
        if (!appDir.mkpath(QStringLiteral("uploaded_files"))) {
            qCritical().noquote() << QStringLiteral("无法创建文件存储目录");
            return false;
        }
        rootDir = QDir(uploadedFilesPath());
    }

    if (!m_server.listen(QHostAddress::LocalHost, port)) {
        qCritical().noquote() << QStringLiteral("HTTP 监听失败：%1")
                                     .arg(m_server.errorString());
        return false;
    }

    if (!m_eventServer.listen(QHostAddress::LocalHost,
                              static_cast<quint16>(resolvedEventPort))) {
        qCritical().noquote() << QStringLiteral("WebSocket 监听失败：%1")
                                     .arg(m_eventServer.errorString());
        m_server.close();
        return false;
    }

    m_storageRoot = QDir::cleanPath(rootDir.absolutePath());
    m_knownPaths.clear();
    m_pendingChanges.clear();
    m_watchInitialized = false;
    loadItemOrder();
    synchronizeItemOrder();
    loadFavorites();
    rebuildFileSystemWatch();
    synchronizeFavorites();

    qInfo().noquote() << QStringLiteral("FileSync 本地测试服务已启动：")
                      << QStringLiteral("http://127.0.0.1:%1/upload")
                             .arg(m_server.serverPort());
    qInfo().noquote() << QStringLiteral("文件列表接口：")
                      << QStringLiteral("http://127.0.0.1:%1/files")
                             .arg(m_server.serverPort());
    qInfo().noquote() << QStringLiteral("实时变更事件：")
                      << QStringLiteral("ws://127.0.0.1:%1/events")
                             .arg(m_eventServer.serverPort());
    qInfo().noquote() << QStringLiteral("上传目录：%1").arg(m_storageRoot);
    return true;
}

void LocalUploadServer::handleEventConnection()
{
    while (m_eventServer.hasPendingConnections()) {
        QWebSocket *socket = m_eventServer.nextPendingConnection();
        if (!socket)
            continue;

        if (socket->requestUrl().path() != QStringLiteral("/events")) {
            socket->close(QWebSocketProtocol::CloseCodePolicyViolated,
                          QStringLiteral("请连接 /events"));
            socket->deleteLater();
            continue;
        }

        socket->setParent(this);
        m_eventClients.append(socket);
        connect(socket, &QWebSocket::disconnected, this, [this, socket]() {
            m_eventClients.removeAll(socket);
            socket->deleteLater();
        });

        const QJsonObject readyEvent{
            {QStringLiteral("type"), QStringLiteral("ready")},
            {QStringLiteral("revision"), static_cast<double>(m_revision)},
            {QStringLiteral("timestamp"),
             QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}
        };
        socket->sendTextMessage(QString::fromUtf8(
            QJsonDocument(readyEvent).toJson(QJsonDocument::Compact)));
    }
}

QString LocalUploadServer::cloudPathForFileName(const QString &absolutePath) const
{
    if (m_storageRoot.isEmpty())
        return {};

    const QString relative = QDir(m_storageRoot).relativeFilePath(
        QDir::cleanPath(absolutePath));
    const QString normalized = QDir::fromNativeSeparators(relative);
    if (normalized == QStringLiteral("."))
        return {};
    if (normalized == QStringLiteral("..")
        || normalized.startsWith(QStringLiteral("../"))
        || QDir::isAbsolutePath(normalized)) {
        return {};
    }
    return normalized;
}

void LocalUploadServer::loadItemOrder()
{
    m_itemOrder.clear();
    m_nextItemOrder = 1;

    QFile orderFile(itemOrderFilePath());
    if (!orderFile.exists())
        return;
    if (!orderFile.open(QIODevice::ReadOnly)) {
        qWarning().noquote() << QStringLiteral("无法读取文件顺序表：%1")
                                    .arg(orderFile.errorString());
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(orderFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning().noquote() << QStringLiteral("文件顺序表格式无效，将重新补全缺失顺序");
        return;
    }

    const QJsonObject rootObject = document.object();
    const QJsonObject savedItems = rootObject.value(QStringLiteral("items")).toObject();
    quint64 largestOrder = 0;
    for (auto it = savedItems.constBegin(); it != savedItems.constEnd(); ++it) {
        QString cloudPath;
        QString pathError;
        bool orderOk = false;
        const quint64 order = it.value().toVariant().toULongLong(&orderOk);
        if (!orderOk || order == 0
            || !cleanCloudPath(it.key(), &cloudPath, &pathError) || cloudPath.isEmpty()) {
            continue;
        }
        m_itemOrder.insert(cloudPath, order);
        largestOrder = qMax(largestOrder, order);
    }

    m_nextItemOrder = qMax<quint64>(
        1, rootObject.value(QStringLiteral("nextOrder")).toVariant().toULongLong());
    if (largestOrder >= m_nextItemOrder
        && largestOrder < std::numeric_limits<quint64>::max()) {
        m_nextItemOrder = largestOrder + 1;
    }
}

void LocalUploadServer::saveItemOrder() const
{
    QJsonObject items;
    for (auto it = m_itemOrder.constBegin(); it != m_itemOrder.constEnd(); ++it)
        items.insert(it.key(), static_cast<double>(it.value()));

    const QJsonObject rootObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("nextOrder"), static_cast<double>(m_nextItemOrder)},
        {QStringLiteral("items"), items}
    };
    const QByteArray data = QJsonDocument(rootObject).toJson(QJsonDocument::Compact);

    QSaveFile orderFile(itemOrderFilePath());
    if (!orderFile.open(QIODevice::WriteOnly)) {
        qWarning().noquote() << QStringLiteral("无法保存文件顺序表：%1")
                                    .arg(orderFile.errorString());
        return;
    }
    if (orderFile.write(data) != data.size() || !orderFile.commit()) {
        qWarning().noquote() << QStringLiteral("文件顺序表写入失败：%1")
                                    .arg(orderFile.errorString());
    }
}

void LocalUploadServer::synchronizeItemOrder()
{
    QDir rootDir(m_storageRoot);
    if (m_storageRoot.isEmpty() || !rootDir.exists())
        return;

    struct PendingItem
    {
        QString cloudPath;
        QDateTime sortTime;
        bool isDirectory = false;
    };

    QSet<QString> existingPaths;
    QList<PendingItem> pendingItems;
    std::function<void(const QDir &, const QString &)> collect =
        [&](const QDir &directory, const QString &relativeDirectory) {
        const QFileInfoList entries = directory.entryInfoList(
            QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
            QDir::NoSort);
        for (const QFileInfo &info : entries) {
            if (info.isSymLink())
                continue;

            const QString cloudPath = relativeDirectory.isEmpty()
                ? info.fileName()
                : relativeDirectory + QLatin1Char('/') + info.fileName();
            existingPaths.insert(cloudPath);
            if (!m_itemOrder.contains(cloudPath)) {
                QDateTime sortTime = info.birthTime();
                if (!sortTime.isValid())
                    sortTime = info.lastModified();
                pendingItems.append(PendingItem{cloudPath, sortTime, info.isDir()});
            }

            if (info.isDir())
                collect(QDir(info.absoluteFilePath()), cloudPath);
        }
    };
    collect(rootDir, QString());

    bool changed = false;
    for (auto it = m_itemOrder.begin(); it != m_itemOrder.end();) {
        if (!existingPaths.contains(it.key())) {
            it = m_itemOrder.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }

    // 首次启用该版本时，旧文件没有顺序记录，使用创建时间（无效时用修改时间）补齐一次。
    // 此后只使用持久化顺序号，不再受名称和修改时间影响。
    std::sort(pendingItems.begin(), pendingItems.end(),
              [](const PendingItem &left, const PendingItem &right) {
        if (left.sortTime.isValid() != right.sortTime.isValid())
            return left.sortTime.isValid();
        if (left.sortTime.isValid() && left.sortTime != right.sortTime)
            return left.sortTime < right.sortTime;
        if (left.isDirectory != right.isDirectory)
            return left.isDirectory;
        return left.cloudPath < right.cloudPath;
    });

    for (const PendingItem &item : std::as_const(pendingItems)) {
        m_itemOrder.insert(item.cloudPath, m_nextItemOrder++);
        changed = true;
    }

    if (changed)
        saveItemOrder();
}

void LocalUploadServer::registerItemOrder(const QString &cloudPath)
{
    QString normalizedPath;
    QString pathError;
    if (!cleanCloudPath(cloudPath, &normalizedPath, &pathError)
        || normalizedPath.isEmpty()) {
        return;
    }

    // 每次成功上传/创建都分配新顺序号；若该路径是删除后重建的，也不能继承旧位置。
    m_itemOrder.insert(normalizedPath, m_nextItemOrder++);
    saveItemOrder();
}

void LocalUploadServer::moveItemOrder(const QString &oldCloudPath,
                                      const QString &newCloudPath)
{
    QString oldPath;
    QString newPath;
    QString pathError;
    if (!cleanCloudPath(oldCloudPath, &oldPath, &pathError) || oldPath.isEmpty()
        || !cleanCloudPath(newCloudPath, &newPath, &pathError) || newPath.isEmpty()
        || oldPath == newPath) {
        return;
    }

    // 清理由外部删除遗留的目标路径记录，避免旧数据混入本次重命名后的子树。
    const QString newPrefix = newPath + QLatin1Char('/');
    for (auto it = m_itemOrder.begin(); it != m_itemOrder.end();) {
        if (it.key() == newPath || it.key().startsWith(newPrefix))
            it = m_itemOrder.erase(it);
        else
            ++it;
    }

    // 文件夹重命名时，所有后代的云端路径也会变化，但各自顺序号必须保持不变。
    QList<QPair<QString, quint64>> movedItems;
    const QString oldPrefix = oldPath + QLatin1Char('/');
    for (auto it = m_itemOrder.begin(); it != m_itemOrder.end();) {
        if (it.key() == oldPath || it.key().startsWith(oldPrefix)) {
            movedItems.append(qMakePair(newPath + it.key().mid(oldPath.size()), it.value()));
            it = m_itemOrder.erase(it);
        } else {
            ++it;
        }
    }

    for (const auto &item : std::as_const(movedItems))
        m_itemOrder.insert(item.first, item.second);

    if (!m_itemOrder.contains(newPath))
        m_itemOrder.insert(newPath, m_nextItemOrder++);
    saveItemOrder();
}

void LocalUploadServer::loadFavorites()
{
    m_favoriteTimes.clear();

    QFile favoritesFile(favoritesFilePath());
    if (!favoritesFile.exists())
        return;
    if (!favoritesFile.open(QIODevice::ReadOnly)) {
        qWarning().noquote() << QStringLiteral("无法读取收藏记录：%1")
                                    .arg(favoritesFile.errorString());
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(
        favoritesFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning().noquote() << QStringLiteral("收藏记录格式无效，将忽略损坏的记录");
        return;
    }

    const QJsonObject savedItems = document.object()
        .value(QStringLiteral("items")).toObject();
    for (auto it = savedItems.constBegin(); it != savedItems.constEnd(); ++it) {
        QString cloudPath;
        QString pathError;
        const QString favoriteTime = it.value().toString();
        if (favoriteTime.isEmpty()
            || !cleanCloudPath(it.key(), &cloudPath, &pathError)
            || cloudPath.isEmpty()) {
            continue;
        }
        m_favoriteTimes.insert(cloudPath, favoriteTime);
    }
}

bool LocalUploadServer::saveFavorites() const
{
    QJsonObject items;
    for (auto it = m_favoriteTimes.constBegin(); it != m_favoriteTimes.constEnd(); ++it)
        items.insert(it.key(), it.value());

    const QJsonObject rootObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("items"), items}
    };
    const QByteArray data = QJsonDocument(rootObject).toJson(QJsonDocument::Compact);

    QSaveFile favoritesFile(favoritesFilePath());
    if (!favoritesFile.open(QIODevice::WriteOnly)) {
        qWarning().noquote() << QStringLiteral("无法保存收藏记录：%1")
                                    .arg(favoritesFile.errorString());
        return false;
    }
    if (favoritesFile.write(data) != data.size() || !favoritesFile.commit()) {
        qWarning().noquote() << QStringLiteral("收藏记录写入失败：%1")
                                    .arg(favoritesFile.errorString());
        return false;
    }
    return true;
}

void LocalUploadServer::synchronizeFavorites()
{
    // 外部删除文件后，收藏快捷入口也随之失效；重命名/移动由 moveFavorites 保留。
    bool changed = false;
    for (auto it = m_favoriteTimes.begin(); it != m_favoriteTimes.end();) {
        if (!m_knownPaths.contains(it.key())) {
            it = m_favoriteTimes.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed)
        saveFavorites();
}

void LocalUploadServer::moveFavorites(const QString &oldCloudPath,
                                      const QString &newCloudPath)
{
    QString oldPath;
    QString newPath;
    QString pathError;
    if (!cleanCloudPath(oldCloudPath, &oldPath, &pathError) || oldPath.isEmpty()
        || !cleanCloudPath(newCloudPath, &newPath, &pathError) || newPath.isEmpty()
        || oldPath == newPath) {
        return;
    }

    const auto previousFavorites = m_favoriteTimes;
    const QString newPrefix = newPath + QLatin1Char('/');
    for (auto it = m_favoriteTimes.begin(); it != m_favoriteTimes.end();) {
        if (it.key() == newPath || it.key().startsWith(newPrefix))
            it = m_favoriteTimes.erase(it);
        else
            ++it;
    }

    QList<QPair<QString, QString>> movedItems;
    const QString oldPrefix = oldPath + QLatin1Char('/');
    for (auto it = m_favoriteTimes.begin(); it != m_favoriteTimes.end();) {
        if (it.key() == oldPath || it.key().startsWith(oldPrefix)) {
            movedItems.append(qMakePair(newPath + it.key().mid(oldPath.size()), it.value()));
            it = m_favoriteTimes.erase(it);
        } else {
            ++it;
        }
    }
    for (const auto &item : std::as_const(movedItems))
        m_favoriteTimes.insert(item.first, item.second);

    if (m_favoriteTimes != previousFavorites && !saveFavorites())
        m_favoriteTimes = previousFavorites;
}

void LocalUploadServer::broadcastFavoritesChanged(const QString &cloudPath)
{
    if (!m_eventServer.isListening())
        return;

    const QJsonObject event{
        {QStringLiteral("type"), QStringLiteral("favoritesChanged")},
        {QStringLiteral("revision"), static_cast<double>(++m_revision)},
        {QStringLiteral("paths"), QJsonArray{cloudPath}},
        {QStringLiteral("timestamp"),
         QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}
    };
    const QString message = QString::fromUtf8(
        QJsonDocument(event).toJson(QJsonDocument::Compact));
    for (QWebSocket *socket : std::as_const(m_eventClients)) {
        if (socket && socket->state() == QAbstractSocket::ConnectedState)
            socket->sendTextMessage(message);
    }
}

void LocalUploadServer::rebuildFileSystemWatch()
{
    QDir rootDir(m_storageRoot);
    if (m_storageRoot.isEmpty() || !rootDir.exists())
        return;

    QSet<QString> currentPaths;
    QSet<QString> currentAbsolutePaths;
    currentPaths.insert(QString()); // 根目录
    currentAbsolutePaths.insert(QDir::cleanPath(rootDir.absolutePath()));

    std::function<void(const QDir &)> collect = [&](const QDir &directory) {
        const QFileInfoList entries = directory.entryInfoList(
            QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
            QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &info : entries) {
            if (info.isSymLink())
                continue;

            const QString absolutePath = QDir::cleanPath(info.absoluteFilePath());
            const QString cloudPath = cloudPathForFileName(absolutePath);
            currentPaths.insert(cloudPath);
            currentAbsolutePaths.insert(absolutePath);
            if (info.isDir())
                collect(QDir(absolutePath));
        }
    };
    collect(rootDir);

    if (m_watchInitialized) {
        for (const QString &path : currentPaths) {
            if (!m_knownPaths.contains(path) && !path.isEmpty())
                m_pendingChanges.insert(path);
        }
        for (const QString &path : m_knownPaths) {
            if (!currentPaths.contains(path))
                m_pendingChanges.insert(path);
        }
    }

    QStringList watchedPaths = m_fileWatcher.directories();
    watchedPaths.append(m_fileWatcher.files());
    QSet<QString> watchedSet(watchedPaths.begin(), watchedPaths.end());
    for (const QString &path : watchedPaths) {
        const QString cleaned = QDir::cleanPath(path);
        if (!currentAbsolutePaths.contains(cleaned)) {
            m_fileWatcher.removePath(path);
            watchedSet.remove(cleaned);
        }
    }
    for (const QString &path : currentAbsolutePaths) {
        if (!watchedSet.contains(path) && !m_fileWatcher.addPath(path))
            qWarning().noquote() << QStringLiteral("无法监听文件路径：%1").arg(path);
    }

    m_knownPaths = currentPaths;
    m_watchInitialized = true;
}

void LocalUploadServer::queueFileChange(const QString &cloudPath)
{
    if (!m_eventServer.isListening())
        return;

    m_pendingChanges.insert(QDir::fromNativeSeparators(cloudPath));
    if (!m_changeTimer.isActive())
        m_changeTimer.start();
}

void LocalUploadServer::broadcastFileChanges()
{
    // 重新扫描可同时发现新增/删除项，并补建新增目录及改名文件的监听。
    rebuildFileSystemWatch();
    synchronizeItemOrder();
    synchronizeFavorites();
    if (m_pendingChanges.isEmpty())
        return;

    QStringList paths = m_pendingChanges.values();
    m_pendingChanges.clear();
    std::sort(paths.begin(), paths.end());

    // 大量变更时退化为全量刷新通知，避免构造过大的 WebSocket 消息。
    if (paths.size() > 200) {
        paths.clear();
        paths.append(QString());
    }

    QJsonArray pathArray;
    for (const QString &path : paths)
        pathArray.append(path);

    const QJsonObject event{
        {QStringLiteral("type"), QStringLiteral("filesChanged")},
        {QStringLiteral("revision"), static_cast<double>(++m_revision)},
        {QStringLiteral("paths"), pathArray},
        {QStringLiteral("timestamp"),
         QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}
    };
    const QString message = QString::fromUtf8(
        QJsonDocument(event).toJson(QJsonDocument::Compact));

    for (QWebSocket *socket : std::as_const(m_eventClients)) {
        if (socket && socket->state() == QAbstractSocket::ConnectedState)
            socket->sendTextMessage(message);
    }
}

void LocalUploadServer::readRequest(QTcpSocket *socket)
{
    if (!m_buffers.contains(socket))
        return;

    QByteArray &buffer = m_buffers[socket];
    buffer += socket->readAll();

    const int headerEnd = buffer.indexOf(QByteArrayLiteral("\r\n\r\n"));
    if (headerEnd < 0)
        return;

    const QByteArray headerBlock = buffer.left(headerEnd);
    const int requestLineEnd = headerBlock.indexOf('\n');
    const QByteArray requestLine = (requestLineEnd >= 0
        ? headerBlock.left(requestLineEnd) : headerBlock).trimmed();
    const QList<QByteArray> requestParts = requestLine.split(' ');

    if (requestParts.size() < 2) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("HTTP 请求行格式错误")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const QByteArray method = requestParts.at(0).trimmed().toUpper();
    const QByteArray target = requestParts.at(1).trimmed();
    const QUrl requestUrl = QUrl::fromEncoded(target);
    const QString requestPath = requestUrl.path();

    // GET 请求没有请求体，不能要求它必须携带 Content-Length。
    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/files")) {
        processFilesRequest(socket, requestUrl);
        return;
    }

    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/folders")) {
        processFoldersRequest(socket, requestUrl);
        return;
    }

    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/favorites")) {
        processFavoritesRequest(socket);
        return;
    }

    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/trash")) {
        processTrashRequest(socket);
        return;
    }

    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/file")) {
        processFileRequest(socket, requestUrl);
        return;
    }

    const bool isUploadRequest = method == QByteArrayLiteral("POST")
                                 && requestPath == QStringLiteral("/upload");
    const bool isCreateFolderRequest = method == QByteArrayLiteral("POST")
                                       && requestPath == QStringLiteral("/folders");
    const bool isRenameRequest = method == QByteArrayLiteral("POST")
                                 && requestPath == QStringLiteral("/rename");
    const bool isMoveRequest = method == QByteArrayLiteral("POST")
                               && requestPath == QStringLiteral("/move");
    const bool isMoveToTrashRequest = method == QByteArrayLiteral("POST")
                                      && requestPath == QStringLiteral("/trash");
    const bool isAddFavoriteRequest = method == QByteArrayLiteral("POST")
                                      && requestPath == QStringLiteral("/favorites");
    const bool isRemoveFavoriteRequest = method == QByteArrayLiteral("POST")
                                         && requestPath == QStringLiteral("/favorites/remove");
    if (!isUploadRequest && !isCreateFolderRequest && !isRenameRequest && !isMoveRequest
        && !isMoveToTrashRequest && !isAddFavoriteRequest && !isRemoveFavoriteRequest) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("接口不存在，请使用 GET /files、GET /folders、GET /favorites、GET /trash、GET /file、POST /upload、POST /folders、POST /rename、POST /move、POST /trash、POST /favorites 或 POST /favorites/remove")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const QRegularExpression lengthExpression(
        QStringLiteral("(?:^|\\r\\n)content-length\\s*:\\s*(\\d+)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch lengthMatch = lengthExpression.match(
        QString::fromLatin1(headerBlock));
    if (!lengthMatch.hasMatch()) {
        sendJson(socket, 411, QByteArrayLiteral("Length Required"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("缺少 Content-Length")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    bool lengthOk = false;
    const qint64 contentLength = lengthMatch.captured(1).toLongLong(&lengthOk);
    if (!lengthOk || contentLength < 0 || contentLength > 512LL * 1024LL * 1024LL) {
        sendJson(socket, 413, QByteArrayLiteral("Payload Too Large"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("测试服务端仅允许 512 MB 以内的请求体")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }
    if ((isCreateFolderRequest || isRenameRequest || isMoveRequest || isMoveToTrashRequest
         || isAddFavoriteRequest || isRemoveFavoriteRequest)
        && contentLength > 64 * 1024) {
        sendJson(socket, 413, QByteArrayLiteral("Payload Too Large"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("JSON 请求体不能超过 64 KB")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const qint64 bodyStart = headerEnd + 4;
    if (buffer.size() < bodyStart + contentLength)
        return;

    const QByteArray body = buffer.mid(static_cast<int>(bodyStart),
                                       static_cast<int>(contentLength));
    if (isCreateFolderRequest) {
        processCreateFolderRequest(socket, body);
        return;
    }
    if (isRenameRequest) {
        processRenameRequest(socket, body);
        return;
    }
    if (isMoveRequest) {
        processMoveRequest(socket, body);
        return;
    }
    if (isMoveToTrashRequest) {
        processMoveToTrashRequest(socket, body);
        return;
    }
    if (isAddFavoriteRequest) {
        processAddFavoriteRequest(socket, body);
        return;
    }
    if (isRemoveFavoriteRequest) {
        processRemoveFavoriteRequest(socket, body);
        return;
    }
    processRequest(socket, requestUrl, headerBlock, body);
}

void LocalUploadServer::processFilesRequest(QTcpSocket *socket, const QUrl &requestUrl)
{
    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        QDir appDir(QCoreApplication::applicationDirPath());
        if (!appDir.mkpath(QStringLiteral("uploaded_files"))) {
            sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                     QJsonDocument(QJsonObject{
                         {QStringLiteral("success"), false},
                         {QStringLiteral("message"), QStringLiteral("无法创建文件存储目录")}
                     }).toJson(QJsonDocument::Compact));
            return;
        }
        rootDir = QDir(uploadedFilesPath());
    }

    const QUrlQuery requestQuery(requestUrl);
    const QString requestedPath = requestQuery.queryItemValue(
        QStringLiteral("path"), QUrl::FullyDecoded);
    QDir currentDir;
    QString currentPath;
    QString pathError;
    if (!resolveCloudDirectory(rootDir, requestedPath, &currentDir, &currentPath, &pathError)) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), pathError}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    // 外部程序直接新增/删除的文件也在返回列表前补齐或清理顺序记录。
    synchronizeItemOrder();

    // 仅扫描当前目录子树；递归统计全部文件，但列表只保留当前目录的直接子项。
    QJsonArray allItems;
    const int totalFiles = appendDirectoryItems(currentDir, currentPath, &allItems, m_itemOrder);
    QJsonArray items;
    int syncedFiles = 0;
    int syncingFiles = 0;
    const QString pathPrefix = currentPath.isEmpty()
        ? QString() : currentPath + QLatin1Char('/');

    for (const QJsonValue &value : allItems) {
        const QJsonObject object = value.toObject();
        const QString itemPath = object.value(QStringLiteral("path")).toString();
        const QString status = object.value(QStringLiteral("status")).toString();
        if (object.value(QStringLiteral("kind")).toString() != QStringLiteral("folder")) {
            if (status == QStringLiteral("同步中") || status == QStringLiteral("正在同步")
                || status.compare(QStringLiteral("syncing"), Qt::CaseInsensitive) == 0) {
                ++syncingFiles;
            } else if (status == QStringLiteral("已同步")
                       || status.compare(QStringLiteral("synced"), Qt::CaseInsensitive) == 0) {
                ++syncedFiles;
            }
        }

        if (!pathPrefix.isEmpty() && !itemPath.startsWith(pathPrefix))
            continue;
        const QString relativeName = pathPrefix.isEmpty()
            ? itemPath : itemPath.mid(pathPrefix.size());
        if (!relativeName.isEmpty() && !relativeName.contains(QLatin1Char('/')))
            items.append(object);
    }

    QString parentPath;
    const int lastSlash = currentPath.lastIndexOf(QLatin1Char('/'));
    if (lastSlash >= 0)
        parentPath = currentPath.left(lastSlash);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("currentPath"), currentPath},
        {QStringLiteral("parentPath"), parentPath},
        {QStringLiteral("totalFiles"), totalFiles},
        {QStringLiteral("syncedFiles"), syncedFiles},
        {QStringLiteral("syncingFiles"), syncingFiles},
        {QStringLiteral("totalItems"), items.size()},
        {QStringLiteral("items"), items}
    };

    qInfo().noquote() << QStringLiteral("目录查询成功：%1，%2 个文件，当前层 %3 个项目")
                             .arg(currentPath.isEmpty() ? QStringLiteral("/") : currentPath)
                             .arg(totalFiles)
                             .arg(items.size());

    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processFoldersRequest(QTcpSocket *socket, const QUrl &requestUrl)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件存储目录不存在"));
        return;
    }

    const QString requestedPath = QUrlQuery(requestUrl).queryItemValue(
        QStringLiteral("path"), QUrl::FullyDecoded);
    QDir currentDir;
    QString currentPath;
    QString pathError;
    if (!resolveCloudDirectory(rootDir, requestedPath,
                               &currentDir, &currentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    QJsonArray folders;
    const QFileInfoList entries = currentDir.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable,
        QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : entries) {
        if (info.isSymLink())
            continue;

        const QString folderPath = currentPath.isEmpty()
            ? info.fileName() : currentPath + QLatin1Char('/') + info.fileName();
        folders.append(QJsonObject{
            {QStringLiteral("name"), info.fileName()},
            {QStringLiteral("path"), folderPath},
            {QStringLiteral("kind"), QStringLiteral("folder")},
            {QStringLiteral("ext"), QStringLiteral("文件夹")},
            {QStringLiteral("modified"), info.lastModified().toString(
                 QStringLiteral("yyyy-MM-dd HH:mm"))}
        });
    }

    QString parentPath;
    const int lastSlash = currentPath.lastIndexOf(QLatin1Char('/'));
    if (lastSlash >= 0)
        parentPath = currentPath.left(lastSlash);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("currentPath"), currentPath},
        {QStringLiteral("parentPath"), parentPath},
        {QStringLiteral("folders"), folders}
    };
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processFavoritesRequest(QTcpSocket *socket)
{
    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("文件存储目录不存在")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    // 每次读取都重新生成文件元数据，确保大小、修改时间和文件夹统计是最新的。
    rebuildFileSystemWatch();
    synchronizeItemOrder();
    synchronizeFavorites();

    QJsonArray allItems;
    appendDirectoryItems(rootDir, QString(), &allItems, m_itemOrder);
    QJsonArray favoriteItems;
    for (const QJsonValue &value : allItems) {
        QJsonObject object = value.toObject();
        const QString itemPath = object.value(QStringLiteral("path")).toString();
        const auto favoriteIt = m_favoriteTimes.constFind(itemPath);
        if (favoriteIt == m_favoriteTimes.constEnd())
            continue;

        const int pathSeparator = itemPath.lastIndexOf(QLatin1Char('/'));
        const QString parentPath = pathSeparator >= 0
            ? itemPath.left(pathSeparator) : QString();
        object.insert(QStringLiteral("favorite"), true);
        object.insert(QStringLiteral("favoriteTime"),
                      displayFavoriteTime(favoriteIt.value()));
        object.insert(QStringLiteral("location"), parentPath.isEmpty()
                      ? QStringLiteral("我的文件")
                      : QStringLiteral("我的文件 / ") + parentPath);
        favoriteItems.append(object);
    }

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("totalItems"), favoriteItems.size()},
        {QStringLiteral("items"), favoriteItems}
    };
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processFileRequest(QTcpSocket *socket, const QUrl &requestUrl)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    const QUrlQuery requestQuery(requestUrl);
    const QString requestedPath = requestQuery.queryItemValue(
        QStringLiteral("path"), QUrl::FullyDecoded);
    if (requestedPath.isEmpty()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("缺少文件路径"));
        return;
    }

    const QString relativePath = QDir::fromNativeSeparators(requestedPath);
    const QString cleanPath = QDir::cleanPath(relativePath);
    if (relativePath.contains(QLatin1Char('\0'))
        || QDir::isAbsolutePath(relativePath)
        || cleanPath == QStringLiteral(".")
        || cleanPath == QStringLiteral("..")
        || cleanPath.startsWith(QStringLiteral("../"))
        || cleanPath.startsWith(QLatin1Char('/'))) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("文件路径不安全"));
        return;
    }

    qint64 maxBytes = 0;
    const QString maxBytesText = requestQuery.queryItemValue(
        QStringLiteral("maxBytes"), QUrl::FullyDecoded);
    if (!maxBytesText.isEmpty()) {
        bool ok = false;
        maxBytes = maxBytesText.toLongLong(&ok);
        if (!ok || maxBytes <= 0) {
            sendError(400, QByteArrayLiteral("Bad Request"),
                      QStringLiteral("maxBytes 必须是正整数"));
            return;
        }
        // 单次分块最多返回 1 MB，正常图片和文档下载不携带 maxBytes。
        maxBytes = qMin(maxBytes, 1024LL * 1024LL);
    }

    qint64 offset = 0;
    const QString offsetText = requestQuery.queryItemValue(
        QStringLiteral("offset"), QUrl::FullyDecoded);
    if (!offsetText.isEmpty()) {
        bool ok = false;
        offset = offsetText.toLongLong(&ok);
        if (!ok || offset < 0) {
            sendError(400, QByteArrayLiteral("Bad Request"),
                      QStringLiteral("offset 必须是非负整数"));
            return;
        }
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件存储目录不存在"));
        return;
    }

    const QFileInfo fileInfo(rootDir.filePath(cleanPath));
    if (!fileInfo.exists() || !fileInfo.isFile() || fileInfo.isSymLink()) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件不存在"));
        return;
    }

    // 使用规范路径再次确认目标仍位于上传目录内，防止中间目录符号链接越界。
    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalFile = QDir::fromNativeSeparators(fileInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (canonicalRoot.isEmpty() || canonicalFile.isEmpty()
        || !canonicalFile.startsWith(rootPrefix)) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许访问上传目录之外的文件"));
        return;
    }

    QFile file(canonicalFile);
    if (!file.open(QIODevice::ReadOnly)) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法读取文件"));
        return;
    }

    QString mimeName = detectMimeType(fileInfo).name();
    if (mimeName.isEmpty())
        mimeName = QStringLiteral("application/octet-stream");
    const bool textContent = previewTypeForFile(fileInfo, mimeName) == QStringLiteral("text");

    QByteArray contentType = mimeName.toLatin1();
    if (textContent && mimeName == QStringLiteral("application/octet-stream"))
        contentType = QByteArrayLiteral("text/plain");
    if (textContent)
        contentType += "; charset=utf-8";

    const qint64 totalSize = file.size();
    if (offset > totalSize) {
        sendError(416, QByteArrayLiteral("Range Not Satisfiable"),
                  QStringLiteral("offset 超出文件大小"));
        return;
    }

    if (!file.seek(offset)) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法定位文件分块位置"));
        return;
    }

    QByteArray previewData;
    qint64 responseSize = totalSize - offset;
    if (maxBytes > 0)
        responseSize = qMin(responseSize, maxBytes);

    // 只有限制分块大小时才缓冲响应；完整图片、PDF、DOCX 仍使用流式发送。
    const bool bufferedResponse = maxBytes > 0;
    if (bufferedResponse) {
        previewData = file.read(responseSize);
        if (textContent)
            previewData = completeUtf8Prefix(previewData);
        responseSize = previewData.size();
    }

    // 下一个 offset 按实际返回字节计算。UTF-8 尾部不完整的字节会留给下一块，
    // 避免 QML 在分块边界看到乱码或重复字符。
    const qint64 nextOffset = offset + responseSize;
    const bool truncated = nextOffset < totalSize;

    QByteArray response = QByteArrayLiteral("HTTP/1.1 200 OK\r\n");
    response += "Content-Type: " + contentType + "\r\n";
    response += "Content-Length: " + QByteArray::number(responseSize) + "\r\n";
    response += "Cache-Control: private, no-cache\r\n";
    response += "X-Content-Type-Options: nosniff\r\n";
    response += "X-Preview-Truncated: " + QByteArray(truncated ? "1" : "0") + "\r\n";
    response += "X-Preview-Offset: " + QByteArray::number(offset) + "\r\n";
    response += "X-Preview-Next-Offset: " + QByteArray::number(nextOffset) + "\r\n";
    response += "X-Preview-Total-Size: " + QByteArray::number(totalSize) + "\r\n";
    response += "Connection: close\r\n\r\n";
    socket->write(response);

    if (bufferedResponse) {
        if (!previewData.isEmpty() && socket->write(previewData) < 0)
            return;
    } else {
        // 完整文件分块写入，避免额外生成一个与完整文件等大的 QByteArray。
        qint64 remaining = responseSize;
        while (remaining > 0) {
            const QByteArray data = file.read(qMin<qint64>(remaining, 64 * 1024));
            if (data.isEmpty() || socket->write(data) < 0)
                return;
            remaining -= data.size();
        }
    }
    socket->flush();
    socket->disconnectFromHost();
}

void LocalUploadServer::processCreateFolderRequest(QTcpSocket *socket,
                                                   const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QJsonObject requestObject = document.object();
    const QString folderName = requestObject.value(QStringLiteral("name"))
                               .toString().trimmed();
    QString validationError;
    if (!validateFolderName(folderName, &validationError)) {
        sendError(400, QByteArrayLiteral("Bad Request"), validationError);
        return;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        QDir appDir(QCoreApplication::applicationDirPath());
        if (!appDir.mkpath(QStringLiteral("uploaded_files"))) {
            sendError(500, QByteArrayLiteral("Internal Server Error"),
                      QStringLiteral("无法创建文件存储目录"));
            return;
        }
        rootDir = QDir(uploadedFilesPath());
    }

    const QString requestedParentPath = requestObject.value(QStringLiteral("path")).toString();
    QDir parentDir;
    QString parentPath;
    QString pathError;
    if (!resolveCloudDirectory(rootDir, requestedParentPath,
                               &parentDir, &parentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    const QFileInfo targetInfo(parentDir.filePath(folderName));
    if (targetInfo.exists() || targetInfo.isSymLink()) {
        sendError(409, QByteArrayLiteral("Conflict"),
                  QStringLiteral("已存在同名文件或文件夹，请更换名称"));
        return;
    }

    // 只创建一级目录，不使用 mkpath，避免文件夹名称被解释为嵌套路径。
    if (!parentDir.mkdir(folderName)) {
        const QFileInfo conflictInfo(parentDir.filePath(folderName));
        if (conflictInfo.exists() || conflictInfo.isSymLink()) {
            sendError(409, QByteArrayLiteral("Conflict"),
                      QStringLiteral("已存在同名文件或文件夹，请更换名称"));
        } else {
            sendError(500, QByteArrayLiteral("Internal Server Error"),
                      QStringLiteral("无法创建文件夹，请检查目录写入权限"));
        }
        return;
    }

    const QFileInfo folderInfo(parentDir.filePath(folderName));
    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalFolder = QDir::fromNativeSeparators(folderInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (!folderInfo.isDir() || folderInfo.isSymLink()
        || canonicalRoot.isEmpty() || canonicalFolder.isEmpty()
        || !canonicalFolder.startsWith(rootPrefix)) {
        parentDir.rmdir(folderName);
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许在上传目录之外创建文件夹"));
        return;
    }

    const QString folderPath = parentPath.isEmpty()
        ? folderName : parentPath + QLatin1Char('/') + folderName;
    registerItemOrder(folderPath);

    const QJsonObject folderObject{
        {QStringLiteral("name"), folderName},
        {QStringLiteral("path"), folderPath},
        {QStringLiteral("kind"), QStringLiteral("folder")},
        {QStringLiteral("ext"), QStringLiteral("文件夹")},
        {QStringLiteral("modified"), folderInfo.lastModified().toString(
             QStringLiteral("yyyy-MM-dd HH:mm"))},
        {QStringLiteral("size"), QStringLiteral("0 个文件")},
        {QStringLiteral("fileCount"), 0},
        {QStringLiteral("status"), QStringLiteral("已同步")},
        {QStringLiteral("iconBg"), QStringLiteral("#FFF5E3")},
        {QStringLiteral("iconColor"), QStringLiteral("#E9AD4E")}
    };
    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("message"), QStringLiteral("文件夹创建成功")},
        {QStringLiteral("name"), folderName},
        {QStringLiteral("path"), folderPath},
        {QStringLiteral("folder"), folderObject}
    };

    qInfo().noquote() << QStringLiteral("新建文件夹成功：%1").arg(canonicalFolder);
    queueFileChange(folderPath);
    sendJson(socket, 201, QByteArrayLiteral("Created"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processRenameRequest(QTcpSocket *socket, const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QJsonObject requestObject = document.object();
    const QString requestedPath = requestObject.value(QStringLiteral("path")).toString();
    const QString newName = requestObject.value(QStringLiteral("newName")).toString().trimmed();
    if (requestedPath.isEmpty()) {
        sendError(400, QByteArrayLiteral("Bad Request"), QStringLiteral("缺少原文件路径"));
        return;
    }

    QString sourcePath;
    QString pathError;
    if (!cleanCloudPath(requestedPath, &sourcePath, &pathError) || sourcePath.isEmpty()) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  sourcePath.isEmpty() && pathError.isEmpty()
                      ? QStringLiteral("不能重命名文件存储根目录") : pathError);
        return;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"), QStringLiteral("文件存储目录不存在"));
        return;
    }

    const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
    const QString requestedParentPath = pathSeparator >= 0
        ? sourcePath.left(pathSeparator) : QString();
    const QString oldName = pathSeparator >= 0
        ? sourcePath.mid(pathSeparator + 1) : sourcePath;

    QDir parentDir;
    QString parentPath;
    if (!resolveCloudDirectory(rootDir, requestedParentPath,
                               &parentDir, &parentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    const QString sourceAbsolutePath = parentDir.filePath(oldName);
    const QFileInfo sourceInfo(sourceAbsolutePath);
    if (!sourceInfo.exists() || sourceInfo.isSymLink()
        || (!sourceInfo.isFile() && !sourceInfo.isDir())) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("原文件或文件夹不存在，或不可重命名"));
        return;
    }

    const QString itemType = sourceInfo.isDir()
        ? QStringLiteral("文件夹") : QStringLiteral("文件");
    QString validationError;
    if (!validateItemName(newName, itemType, &validationError)) {
        sendError(400, QByteArrayLiteral("Bad Request"), validationError);
        return;
    }

    // 规范路径校验用于阻止中间目录符号链接或部署目录配置造成的越界访问。
    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalSource = QDir::fromNativeSeparators(sourceInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (canonicalRoot.isEmpty() || canonicalSource.isEmpty()
        || !canonicalSource.startsWith(rootPrefix)) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许重命名上传目录之外的内容"));
        return;
    }

    const QString targetAbsolutePath = parentDir.filePath(newName);
    const QString targetPath = parentPath.isEmpty()
        ? newName : parentPath + QLatin1Char('/') + newName;

    auto sendSuccess = [this, socket](const QString &oldPath,
                                      const QString &newPath,
                                      const QString &name,
                                      const QFileInfo &itemInfo) {
        const QJsonObject responseObject{
            {QStringLiteral("success"), true},
            {QStringLiteral("message"), QStringLiteral("重命名成功")},
            {QStringLiteral("oldPath"), oldPath},
            {QStringLiteral("newPath"), newPath},
            {QStringLiteral("path"), newPath},
            {QStringLiteral("name"), name},
            {QStringLiteral("kind"), itemInfo.isDir()
                 ? QStringLiteral("folder") : QStringLiteral("file")},
            {QStringLiteral("modified"), itemInfo.lastModified().toString(
                 QStringLiteral("yyyy-MM-dd HH:mm"))}
        };
        sendJson(socket, 200, QByteArrayLiteral("OK"),
                 QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
    };

    if (newName == oldName) {
        sendSuccess(sourcePath, sourcePath, oldName, sourceInfo);
        return;
    }

    const QFileInfo targetInfo(targetAbsolutePath);
    bool targetIsSource = false;
    if (targetInfo.exists() && !targetInfo.isSymLink()) {
        targetIsSource = QDir::fromNativeSeparators(targetInfo.canonicalFilePath())
                         == canonicalSource;
    }
    if ((targetInfo.exists() || targetInfo.isSymLink()) && !targetIsSource) {
        sendError(409, QByteArrayLiteral("Conflict"),
                  QStringLiteral("已存在同名文件或文件夹，请更换名称"));
        return;
    }

    if (!QFile::rename(sourceAbsolutePath, targetAbsolutePath)) {
        const QFileInfo conflictInfo(targetAbsolutePath);
        if ((conflictInfo.exists() || conflictInfo.isSymLink()) && !targetIsSource) {
            sendError(409, QByteArrayLiteral("Conflict"),
                      QStringLiteral("已存在同名文件或文件夹，请更换名称"));
        } else {
            sendError(500, QByteArrayLiteral("Internal Server Error"),
                      QStringLiteral("重命名失败，请检查文件是否被占用以及目录写入权限"));
        }
        return;
    }

    const QFileInfo renamedInfo(targetAbsolutePath);
    moveItemOrder(sourcePath, targetPath);
    moveFavorites(sourcePath, targetPath);
    qInfo().noquote() << QStringLiteral("重命名成功：%1 -> %2")
                             .arg(sourceAbsolutePath, targetAbsolutePath);
    queueFileChange(sourcePath);
    queueFileChange(targetPath);
    sendSuccess(sourcePath, targetPath, newName, renamedInfo);
}

void LocalUploadServer::processMoveRequest(QTcpSocket *socket, const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QJsonObject requestObject = document.object();
    const QString requestedPath = requestObject.value(QStringLiteral("path")).toString();
    const QString requestedDestination = requestObject.value(
        QStringLiteral("destinationPath")).toString();
    if (requestedPath.isEmpty()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("缺少要移动的文件或文件夹路径"));
        return;
    }

    QString sourcePath;
    QString destinationPath;
    QString pathError;
    if (!cleanCloudPath(requestedPath, &sourcePath, &pathError) || sourcePath.isEmpty()) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  sourcePath.isEmpty() && pathError.isEmpty()
                      ? QStringLiteral("不能移动文件存储根目录") : pathError);
        return;
    }
    if (!cleanCloudPath(requestedDestination, &destinationPath, &pathError)) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("目标文件夹路径不安全"));
        return;
    }

    // 字符串检查可在目标尚不存在时也明确拒绝自身/后代路径。
    if (destinationPath == sourcePath
        || destinationPath.startsWith(sourcePath + QLatin1Char('/'))) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("不能将文件夹移动到自身或其子文件夹中"));
        return;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件存储目录不存在"));
        return;
    }

    const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
    const QString requestedParentPath = pathSeparator >= 0
        ? sourcePath.left(pathSeparator) : QString();
    const QString itemName = pathSeparator >= 0
        ? sourcePath.mid(pathSeparator + 1) : sourcePath;

    QDir sourceParentDir;
    QString sourceParentPath;
    if (!resolveCloudDirectory(rootDir, requestedParentPath,
                               &sourceParentDir, &sourceParentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    const QString sourceAbsolutePath = sourceParentDir.filePath(itemName);
    const QFileInfo sourceInfo(sourceAbsolutePath);
    if (!sourceInfo.exists() || sourceInfo.isSymLink()
        || (!sourceInfo.isFile() && !sourceInfo.isDir())) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("原文件或文件夹不存在，或不可移动"));
        return;
    }

    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalSource = QDir::fromNativeSeparators(
        sourceInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (canonicalRoot.isEmpty() || canonicalSource.isEmpty()
        || !canonicalSource.startsWith(rootPrefix, fileSystemCaseSensitivity())) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许移动上传目录之外的内容"));
        return;
    }

    QDir destinationDir;
    QString resolvedDestinationPath;
    if (!resolveCloudDirectory(rootDir, destinationPath,
                               &destinationDir, &resolvedDestinationPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("目标文件夹不存在或不可访问"));
        return;
    }
    destinationPath = resolvedDestinationPath;

    if (sourceInfo.isDir()) {
        const QString canonicalDestination = QDir::fromNativeSeparators(
            destinationDir.canonicalPath());
        if (canonicalDestination.isEmpty()
            || isSameOrDescendantPath(canonicalDestination, canonicalSource)) {
            sendError(400, QByteArrayLiteral("Bad Request"),
                      QStringLiteral("不能将文件夹移动到自身或其子文件夹中"));
            return;
        }
    }

    const QString targetAbsolutePath = destinationDir.filePath(itemName);
    const QString targetPath = destinationPath.isEmpty()
        ? itemName : destinationPath + QLatin1Char('/') + itemName;

    auto sendSuccess = [this, socket](const QString &oldPath,
                                      const QString &newPath,
                                      const QString &destination,
                                      const QString &name,
                                      const QFileInfo &itemInfo) {
        const QJsonObject responseObject{
            {QStringLiteral("success"), true},
            {QStringLiteral("message"), QStringLiteral("移动成功")},
            {QStringLiteral("oldPath"), oldPath},
            {QStringLiteral("newPath"), newPath},
            {QStringLiteral("path"), newPath},
            {QStringLiteral("destinationPath"), destination},
            {QStringLiteral("name"), name},
            {QStringLiteral("kind"), itemInfo.isDir()
                 ? QStringLiteral("folder") : QStringLiteral("file")},
            {QStringLiteral("modified"), itemInfo.lastModified().toString(
                 QStringLiteral("yyyy-MM-dd HH:mm"))}
        };
        sendJson(socket, 200, QByteArrayLiteral("OK"),
                 QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
    };

    // 目标就是当前父目录时无需改动，也不能误报同名冲突。
    if (sourceParentPath == destinationPath) {
        sendSuccess(sourcePath, sourcePath, destinationPath, itemName, sourceInfo);
        return;
    }

    const QFileInfo targetInfo(targetAbsolutePath);
    bool targetIsSource = false;
    if (targetInfo.exists() && !targetInfo.isSymLink()) {
        targetIsSource = QDir::fromNativeSeparators(targetInfo.canonicalFilePath())
                             .compare(canonicalSource, fileSystemCaseSensitivity()) == 0;
    }
    if ((targetInfo.exists() || targetInfo.isSymLink()) && !targetIsSource) {
        sendError(409, QByteArrayLiteral("Conflict"),
                  QStringLiteral("目标文件夹中已存在同名文件或文件夹，未覆盖任何内容"));
        return;
    }
    if (targetIsSource) {
        sendSuccess(sourcePath, targetPath, destinationPath, itemName, sourceInfo);
        return;
    }

    QString moveError;
    if (!moveFileOrDirectory(sourceAbsolutePath, targetAbsolutePath, &moveError)) {
        // 跨卷复制已经提交、但源项目清理失败时，目标可能真实存在；
        // 主动广播实际变化，避免其他客户端继续显示旧目录结构。
        if (QFileInfo::exists(targetAbsolutePath)) {
            synchronizeItemOrder();
            queueFileChange(sourcePath);
            queueFileChange(targetPath);
        }
        sendError(500, QByteArrayLiteral("Internal Server Error"), moveError);
        return;
    }

    const QFileInfo movedInfo(targetAbsolutePath);
    moveItemOrder(sourcePath, targetPath);
    moveFavorites(sourcePath, targetPath);
    qInfo().noquote() << QStringLiteral("移动成功：%1 -> %2")
                             .arg(sourceAbsolutePath, targetAbsolutePath);
    queueFileChange(sourcePath);
    queueFileChange(targetPath);
    sendSuccess(sourcePath, targetPath, destinationPath, itemName, movedInfo);
}

void LocalUploadServer::processTrashRequest(QTcpSocket *socket)
{
    QList<QJsonObject> trashItems;
    const QDir trashRoot(trashFilesPath());
    if (trashRoot.exists()) {
        const QFileInfoList entries = trashRoot.entryInfoList(
            QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable, QDir::NoSort);
        for (const QFileInfo &entryInfo : entries) {
            if (entryInfo.isSymLink())
                continue;

            const QString trashId = entryInfo.fileName();
            const QDir entryDir(entryInfo.absoluteFilePath());
            QFile metadataFile(entryDir.filePath(QStringLiteral("info.json")));
            if (!metadataFile.open(QIODevice::ReadOnly))
                continue;

            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(
                metadataFile.readAll(), &parseError);
            if (parseError.error != QJsonParseError::NoError || !document.isObject())
                continue;

            const QJsonObject metadata = document.object();
            QString originalPath;
            QString pathError;
            if (!cleanCloudPath(metadata.value(QStringLiteral("originalPath")).toString(),
                                &originalPath, &pathError) || originalPath.isEmpty()) {
                continue;
            }

            const QFileInfo payloadInfo(entryDir.filePath(QStringLiteral("payload")));
            if (!payloadInfo.exists() || payloadInfo.isSymLink()
                || (!payloadInfo.isFile() && !payloadInfo.isDir())) {
                continue;
            }

            QString name = metadata.value(QStringLiteral("name")).toString();
            if (name.isEmpty())
                name = QFileInfo(originalPath).fileName();
            if (name.isEmpty())
                continue;

            const bool isDirectory = payloadInfo.isDir();
            // 实际内容统一命名为 payload，扩展名必须从原文件名而不是 payload 中取得。
            const QString originalSuffix = QFileInfo(name).suffix();
            const QString extension = isDirectory
                ? QStringLiteral("文件夹")
                : (originalSuffix.isEmpty()
                       ? QStringLiteral("FILE") : originalSuffix.toUpper());
            QString iconBg;
            QString iconColor;
            fileIconColors(extension, &iconBg, &iconColor);

            QString sizeText;
            int fileCount = 0;
            if (isDirectory) {
                QJsonArray descendants;
                const QHash<QString, quint64> noItemOrder;
                fileCount = appendDirectoryItems(QDir(payloadInfo.absoluteFilePath()), QString(),
                                                 &descendants, noItemOrder);
                sizeText = QStringLiteral("%1 个文件").arg(fileCount);
                iconBg = QStringLiteral("#FFF5E3");
                iconColor = QStringLiteral("#E9AD4E");
            } else {
                sizeText = formatFileSize(payloadInfo.size());
            }

            const int pathSeparator = originalPath.lastIndexOf(QLatin1Char('/'));
            const QString originalParentPath = pathSeparator >= 0
                ? originalPath.left(pathSeparator) : QString();
            const QString deletedAt = metadata.value(QStringLiteral("deletedAt")).toString(
                metadata.value(QStringLiteral("deletedTime")).toString());
            const QString deletedTime = displayFavoriteTime(deletedAt);

            trashItems.append(QJsonObject{
                {QStringLiteral("id"), trashId},
                {QStringLiteral("trashId"), trashId},
                // 回收站操作使用唯一 ID，不能使用可能重复的原文件名作为标识。
                {QStringLiteral("path"), trashId},
                {QStringLiteral("originalPath"), originalPath},
                {QStringLiteral("name"), name},
                {QStringLiteral("kind"), isDirectory
                     ? QStringLiteral("folder") : QStringLiteral("file")},
                {QStringLiteral("ext"), extension},
                {QStringLiteral("modified"), deletedTime},
                {QStringLiteral("deletedAt"), deletedAt},
                {QStringLiteral("deletedTime"), deletedTime},
                {QStringLiteral("size"), sizeText},
                {QStringLiteral("fileCount"), fileCount},
                {QStringLiteral("status"), QStringLiteral("已删除")},
                {QStringLiteral("iconBg"), iconBg},
                {QStringLiteral("iconColor"), iconColor},
                {QStringLiteral("location"), originalParentPath.isEmpty()
                     ? QStringLiteral("我的文件")
                     : QStringLiteral("我的文件 / ") + originalParentPath}
            });
        }
    }

    std::sort(trashItems.begin(), trashItems.end(),
              [](const QJsonObject &left, const QJsonObject &right) {
        const QString leftTime = left.value(QStringLiteral("deletedAt")).toString();
        const QString rightTime = right.value(QStringLiteral("deletedAt")).toString();
        if (leftTime != rightTime)
            return leftTime > rightTime;
        return left.value(QStringLiteral("id")).toString()
               < right.value(QStringLiteral("id")).toString();
    });

    QJsonArray items;
    for (const QJsonObject &item : std::as_const(trashItems))
        items.append(item);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("totalItems"), items.size()},
        {QStringLiteral("items"), items}
    };
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processMoveToTrashRequest(QTcpSocket *socket, const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QString requestedPath = document.object().value(QStringLiteral("path")).toString();
    if (requestedPath.isEmpty()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("缺少要删除的文件或文件夹路径"));
        return;
    }

    QString sourcePath;
    QString pathError;
    if (!cleanCloudPath(requestedPath, &sourcePath, &pathError) || sourcePath.isEmpty()) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  sourcePath.isEmpty() && pathError.isEmpty()
                      ? QStringLiteral("不能删除文件存储根目录") : pathError);
        return;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件存储目录不存在"));
        return;
    }

    const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
    const QString requestedParentPath = pathSeparator >= 0
        ? sourcePath.left(pathSeparator) : QString();
    const QString itemName = pathSeparator >= 0
        ? sourcePath.mid(pathSeparator + 1) : sourcePath;

    QDir sourceParentDir;
    QString sourceParentPath;
    if (!resolveCloudDirectory(rootDir, requestedParentPath,
                               &sourceParentDir, &sourceParentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    const QString sourceAbsolutePath = sourceParentDir.filePath(itemName);
    const QFileInfo sourceInfo(sourceAbsolutePath);
    if (!sourceInfo.exists() || sourceInfo.isSymLink()
        || (!sourceInfo.isFile() && !sourceInfo.isDir())) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件或文件夹不存在，或不可删除"));
        return;
    }

    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalSource = QDir::fromNativeSeparators(sourceInfo.canonicalFilePath());
    const QString rootPrefix = canonicalRoot.endsWith(QLatin1Char('/'))
        ? canonicalRoot : canonicalRoot + QLatin1Char('/');
    if (canonicalRoot.isEmpty() || canonicalSource.isEmpty()
        || !canonicalSource.startsWith(rootPrefix, fileSystemCaseSensitivity())) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许删除上传目录之外的内容"));
        return;
    }

    QDir appDir(QCoreApplication::applicationDirPath());
    if (!appDir.mkpath(QStringLiteral("uploaded_files_trash"))) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法创建回收站目录，请检查应用目录写入权限"));
        return;
    }

    QDir trashRoot(trashFilesPath());
    const QString canonicalTrashRoot = QDir::fromNativeSeparators(trashRoot.canonicalPath());
    if (canonicalTrashRoot.isEmpty()
        || isSameOrDescendantPath(canonicalTrashRoot, canonicalRoot)) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("回收站目录配置不安全"));
        return;
    }

    // 每个删除项目使用独立目录，避免同名文件或不同时期删除的文件夹互相覆盖。
    const QString trashId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (!trashRoot.mkdir(trashId)) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法创建回收站条目，请检查目录写入权限"));
        return;
    }

    const QString entryAbsolutePath = trashRoot.filePath(trashId);
    const QString payloadAbsolutePath = QDir(entryAbsolutePath).filePath(
        QStringLiteral("payload"));
    QString moveError;
    if (!moveFileOrDirectory(sourceAbsolutePath, payloadAbsolutePath, &moveError)) {
        // 如果跨卷复制已经生成了目标内容，保留现场用于恢复，不能直接清理造成数据丢失。
        if (!QFileInfo::exists(payloadAbsolutePath))
            QDir(entryAbsolutePath).removeRecursively();
        else
            qCritical().noquote() << QStringLiteral("移入回收站时源目录清理不完整：%1 -> %2；%3")
                                         .arg(sourceAbsolutePath, payloadAbsolutePath, moveError);
        sendError(500, QByteArrayLiteral("Internal Server Error"), moveError);
        return;
    }

    const QFileInfo payloadInfo(payloadAbsolutePath);
    const QString deletedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    const QJsonObject metadata{
        {QStringLiteral("version"), 1},
        {QStringLiteral("id"), trashId},
        {QStringLiteral("originalPath"), sourcePath},
        {QStringLiteral("originalParentPath"), sourceParentPath},
        {QStringLiteral("name"), itemName},
        {QStringLiteral("kind"), payloadInfo.isDir()
             ? QStringLiteral("folder") : QStringLiteral("file")},
        {QStringLiteral("deletedAt"), deletedAt}
    };
    const QByteArray metadataData = QJsonDocument(metadata).toJson(QJsonDocument::Compact);
    const QString metadataPath = QDir(entryAbsolutePath).filePath(QStringLiteral("info.json"));

    QString metadataError;
    QSaveFile metadataFile(metadataPath);
    if (!metadataFile.open(QIODevice::WriteOnly)) {
        metadataError = metadataFile.errorString();
    } else if (metadataFile.write(metadataData) != metadataData.size()) {
        metadataError = metadataFile.errorString();
    } else if (!metadataFile.commit()) {
        metadataError = metadataFile.errorString();
    }

    if (!metadataError.isEmpty()) {
        // 元数据保存失败时尽量把项目放回原位置；回滚失败也保留 payload，不永久删除数据。
        QString rollbackError;
        const bool rolledBack = !QFileInfo::exists(sourceAbsolutePath)
            && moveFileOrDirectory(payloadAbsolutePath, sourceAbsolutePath, &rollbackError);
        if (rolledBack) {
            QDir(entryAbsolutePath).removeRecursively();
        } else {
            qCritical().noquote() << QStringLiteral("回收站元数据写入失败且无法回滚：%1；%2")
                                         .arg(metadataError, rollbackError);
        }

        QString message = QStringLiteral("无法保存回收站记录：%1").arg(metadataError);
        if (!rolledBack)
            message += QStringLiteral("；项目已保留在回收站暂存目录，请检查磁盘权限后再处理");
        sendError(500, QByteArrayLiteral("Internal Server Error"), message);
        return;
    }

    qInfo().noquote() << QStringLiteral("已移入回收站：%1 -> %2")
                             .arg(sourceAbsolutePath, payloadAbsolutePath);
    queueFileChange(sourcePath);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("message"), QStringLiteral("已移入回收站")},
        {QStringLiteral("oldPath"), sourcePath},
        {QStringLiteral("originalPath"), sourcePath},
        {QStringLiteral("trashId"), trashId},
        {QStringLiteral("id"), trashId},
        {QStringLiteral("path"), trashId},
        {QStringLiteral("name"), itemName},
        {QStringLiteral("kind"), payloadInfo.isDir()
             ? QStringLiteral("folder") : QStringLiteral("file")},
        {QStringLiteral("deletedAt"), deletedAt},
        {QStringLiteral("deletedTime"), displayFavoriteTime(deletedAt)}
    };
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processAddFavoriteRequest(QTcpSocket *socket,
                                                  const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QJsonObject requestObject = document.object();
    const QString requestedPath = requestObject.value(QStringLiteral("path")).toString();
    const bool recursive = requestObject.value(QStringLiteral("recursive")).toBool(true);
    QString sourcePath;
    QString pathError;
    if (requestedPath.isEmpty()
        || !cleanCloudPath(requestedPath, &sourcePath, &pathError)
        || sourcePath.isEmpty()) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  pathError.isEmpty() ? QStringLiteral("收藏路径不能为空或根目录") : pathError);
        return;
    }

    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        sendError(404, QByteArrayLiteral("Not Found"), QStringLiteral("文件存储目录不存在"));
        return;
    }

    const int pathSeparator = sourcePath.lastIndexOf(QLatin1Char('/'));
    const QString requestedParentPath = pathSeparator >= 0
        ? sourcePath.left(pathSeparator) : QString();
    const QString itemName = pathSeparator >= 0
        ? sourcePath.mid(pathSeparator + 1) : sourcePath;

    QDir parentDir;
    QString parentPath;
    if (!resolveCloudDirectory(rootDir, requestedParentPath,
                               &parentDir, &parentPath, &pathError)) {
        sendError(404, QByteArrayLiteral("Not Found"), pathError);
        return;
    }

    const QFileInfo sourceInfo(parentDir.filePath(itemName));
    if (!sourceInfo.exists() || sourceInfo.isSymLink()
        || (!sourceInfo.isFile() && !sourceInfo.isDir())) {
        sendError(404, QByteArrayLiteral("Not Found"),
                  QStringLiteral("文件或文件夹不存在，或不能收藏"));
        return;
    }

    const QString canonicalRoot = QDir::fromNativeSeparators(rootDir.canonicalPath());
    const QString canonicalSource = QDir::fromNativeSeparators(
        sourceInfo.canonicalFilePath());
    if (canonicalRoot.isEmpty() || canonicalSource.isEmpty()
        || !isSameOrDescendantPath(canonicalSource, canonicalRoot)
        || canonicalSource.compare(canonicalRoot, fileSystemCaseSensitivity()) == 0) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  QStringLiteral("不允许收藏上传目录之外的内容"));
        return;
    }

    // 先完整收集再一次性保存，避免大型文件夹产生大量 HTTP 请求或重复收藏项。
    QStringList collectedPaths;
    std::function<bool(const QFileInfo &, const QString &)> collect =
        [&](const QFileInfo &info, const QString &cloudPath) {
        // 与文件列表一致，不跟随符号链接，避免越界和目录循环。
        if (info.isSymLink())
            return true;
        if (!info.isFile() && !info.isDir())
            return true;

        collectedPaths.append(cloudPath);
        if (!info.isDir() || !recursive)
            return true;

        const QFileInfoList entries = QDir(info.absoluteFilePath()).entryInfoList(
            QDir::AllEntries | QDir::NoDotAndDotDot, QDir::NoSort);
        for (const QFileInfo &childInfo : entries) {
            const QString childPath = cloudPath + QLatin1Char('/') + childInfo.fileName();
            if (!collect(childInfo, childPath))
                return false;
        }
        return true;
    };
    if (!collect(sourceInfo, sourcePath)) {
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("扫描文件夹内容失败"));
        return;
    }

    const auto previousFavorites = m_favoriteTimes;
    const QString favoriteTime = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    int addedCount = 0;
    int alreadyFavoriteCount = 0;
    for (const QString &path : std::as_const(collectedPaths)) {
        if (m_favoriteTimes.contains(path)) {
            ++alreadyFavoriteCount;
            continue;
        }
        m_favoriteTimes.insert(path, favoriteTime);
        ++addedCount;
    }

    if (addedCount > 0 && !saveFavorites()) {
        m_favoriteTimes = previousFavorites;
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法保存收藏记录，请检查应用目录写入权限"));
        return;
    }

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("message"), addedCount > 0
             ? QStringLiteral("收藏成功") : QStringLiteral("所选内容均已在收藏夹中")},
        {QStringLiteral("path"), sourcePath},
        {QStringLiteral("addedCount"), addedCount},
        {QStringLiteral("alreadyFavoriteCount"), alreadyFavoriteCount},
        {QStringLiteral("favoriteCount"), m_favoriteTimes.size()}
    };

    qInfo().noquote() << QStringLiteral("收藏成功：%1，新增 %2 项，重复 %3 项")
                             .arg(sourcePath).arg(addedCount).arg(alreadyFavoriteCount);
    if (addedCount > 0)
        broadcastFavoritesChanged(sourcePath);
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processRemoveFavoriteRequest(QTcpSocket *socket,
                                                     const QByteArray &body)
{
    auto sendError = [this, socket](int statusCode, const QByteArray &reason,
                                    const QString &message) {
        sendJson(socket, statusCode, reason,
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), message}
                 }).toJson(QJsonDocument::Compact));
    };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(400, QByteArrayLiteral("Bad Request"),
                  QStringLiteral("请求体不是有效的 JSON 对象"));
        return;
    }

    const QJsonObject requestObject = document.object();
    const QString requestedPath = requestObject.value(QStringLiteral("path")).toString();
    const bool recursive = requestObject.value(QStringLiteral("recursive")).toBool(true);
    QString sourcePath;
    QString pathError;
    if (requestedPath.isEmpty()
        || !cleanCloudPath(requestedPath, &sourcePath, &pathError)
        || sourcePath.isEmpty()) {
        sendError(403, QByteArrayLiteral("Forbidden"),
                  pathError.isEmpty() ? QStringLiteral("收藏路径不能为空或根目录") : pathError);
        return;
    }

    const auto previousFavorites = m_favoriteTimes;
    const QString sourcePrefix = sourcePath + QLatin1Char('/');
    int removedCount = 0;
    for (auto it = m_favoriteTimes.begin(); it != m_favoriteTimes.end();) {
        if (it.key() == sourcePath || (recursive && it.key().startsWith(sourcePrefix))) {
            it = m_favoriteTimes.erase(it);
            ++removedCount;
        } else {
            ++it;
        }
    }

    if (removedCount > 0 && !saveFavorites()) {
        m_favoriteTimes = previousFavorites;
        sendError(500, QByteArrayLiteral("Internal Server Error"),
                  QStringLiteral("无法保存收藏记录，请检查应用目录写入权限"));
        return;
    }

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("message"), removedCount > 0
             ? QStringLiteral("已取消收藏") : QStringLiteral("该项目原本就不在收藏夹中")},
        {QStringLiteral("path"), sourcePath},
        {QStringLiteral("removedCount"), removedCount},
        {QStringLiteral("favoriteCount"), m_favoriteTimes.size()}
    };
    if (removedCount > 0)
        broadcastFavoritesChanged(sourcePath);
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::processRequest(QTcpSocket *socket,
                                       const QUrl &requestUrl,
                                       const QByteArray &headerBlock,
                                       const QByteArray &body)
{
    const QList<QByteArray> lines = headerBlock.split('\n');
    const QByteArray requestLine = lines.isEmpty() ? QByteArray() : lines.first().trimmed();
    if (!requestLine.startsWith(QByteArrayLiteral("POST /upload "))
        && !requestLine.startsWith(QByteArrayLiteral("POST /upload?"))) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("接口不存在，请使用 POST /upload")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    QByteArray contentType;
    for (const QByteArray &line : lines) {
        const QByteArray trimmed = line.trimmed();
        if (trimmed.toLower().startsWith(QByteArrayLiteral("content-type:"))) {
            contentType = trimmed.mid(trimmed.indexOf(':') + 1).trimmed();
            break;
        }
    }

    const QRegularExpression boundaryExpression(
        QStringLiteral("boundary=(?:\"([^\"]+)\"|([^;\\s]+))"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch boundaryMatch = boundaryExpression.match(
        QString::fromLatin1(contentType));
    if (!boundaryMatch.hasMatch()) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("multipart boundary 无效")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const QByteArray boundary = (boundaryMatch.captured(1).isEmpty()
                                     ? boundaryMatch.captured(2)
                                     : boundaryMatch.captured(1)).toLatin1();
    const QByteArray separator = QByteArrayLiteral("\r\n\r\n");
    const int partHeaderEnd = body.indexOf(separator);
    if (partHeaderEnd < 0) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("multipart 内容格式错误")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const QByteArray partHeaders = body.left(partHeaderEnd);
    const QByteArray delimiter = QByteArrayLiteral("\r\n--") + boundary;
    const int dataStart = partHeaderEnd + separator.size();
    const int dataEnd = body.indexOf(delimiter, dataStart);
    if (dataEnd < dataStart) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("没有找到文件数据")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    QString fileName;
    const QString partHeaderText = QString::fromLatin1(partHeaders);
    const QRegularExpression utf8NameExpression(
        QStringLiteral("filename\\*\\s*=\\s*UTF-8''([^;\\r\\n]+)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch utf8NameMatch = utf8NameExpression.match(partHeaderText);
    if (utf8NameMatch.hasMatch()) {
        fileName = QUrl::fromPercentEncoding(utf8NameMatch.captured(1).toLatin1());
    } else {
        const QRegularExpression nameExpression(
            QStringLiteral("filename\\s*=\\s*\"([^\"]*)\""),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch nameMatch = nameExpression.match(partHeaderText);
        if (nameMatch.hasMatch())
            fileName = nameMatch.captured(1);
    }

    fileName = QFileInfo(fileName).fileName();
    if (fileName.isEmpty())
        fileName = QStringLiteral("upload_%1.bin").arg(
            QUuid::createUuid().toString(QUuid::WithoutBraces));

    // 测试服务端额外清理 Windows/Linux 文件名中的非法字符。
    for (int i = 0; i < fileName.size(); ++i) {
        if (QStringLiteral("<>:\"/\\|?*").contains(fileName.at(i)))
            fileName[i] = QLatin1Char('_');
    }

    const QByteArray fileData = body.mid(dataStart, dataEnd - dataStart);
    QDir rootDir(uploadedFilesPath());
    if (!rootDir.exists()) {
        QDir appDir(QCoreApplication::applicationDirPath());
        if (!appDir.mkpath(QStringLiteral("uploaded_files"))) {
            sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                     QJsonDocument(QJsonObject{
                         {QStringLiteral("success"), false},
                         {QStringLiteral("message"), QStringLiteral("无法创建上传目录")}
                     }).toJson(QJsonDocument::Compact));
            return;
        }
        rootDir = QDir(uploadedFilesPath());
    }

    const QString requestedDirectory = QUrlQuery(requestUrl).queryItemValue(
        QStringLiteral("path"), QUrl::FullyDecoded);
    QDir outputDir;
    QString directoryPath;
    QString pathError;
    if (!resolveCloudDirectory(rootDir, requestedDirectory,
                               &outputDir, &directoryPath, &pathError)) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), pathError}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const QString originalName = fileName;
    const QFileInfo nameInfo(fileName);
    QString saveName = fileName;
    if (QFileInfo::exists(outputDir.filePath(saveName))) {
        const QString suffix = nameInfo.suffix();
        const QString base = nameInfo.completeBaseName();
        saveName = QStringLiteral("%1_%2%3")
                       .arg(base)
                       .arg(QUuid::createUuid().toString(QUuid::WithoutBraces).left(8))
                       .arg(suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix);
    }

    QFile outputFile(outputDir.filePath(saveName));
    if (!outputFile.open(QIODevice::WriteOnly)) {
        sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("无法写入上传文件")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const qint64 written = outputFile.write(fileData);
    outputFile.close();
    if (written != fileData.size()) {
        outputFile.remove();
        sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("文件写入不完整")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    qInfo().noquote() << QStringLiteral("接收成功：%1（%2 bytes）")
                             .arg(originalName)
                             .arg(fileData.size());

    const QString savedPath = directoryPath.isEmpty()
        ? saveName : directoryPath + QLatin1Char('/') + saveName;
    registerItemOrder(savedPath);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("fileName"), originalName},
        {QStringLiteral("savedAs"), saveName},
        {QStringLiteral("path"), savedPath},
        {QStringLiteral("directory"), directoryPath},
        {QStringLiteral("size"), static_cast<double>(fileData.size())}
    };
    queueFileChange(savedPath);
    sendJson(socket, 200, QByteArrayLiteral("OK"),
             QJsonDocument(responseObject).toJson(QJsonDocument::Compact));
}

void LocalUploadServer::sendJson(QTcpSocket *socket, int statusCode,
                                 const QByteArray &reason,
                                 const QByteArray &jsonBody)
{
    if (!socket || socket->state() == QAbstractSocket::UnconnectedState)
        return;

    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(statusCode) + " " + reason + "\r\n";
    response += "Content-Type: application/json; charset=utf-8\r\n";
    response += "Content-Length: " + QByteArray::number(jsonBody.size()) + "\r\n";
    response += "Cache-Control: no-store\r\n";
    response += "Connection: close\r\n\r\n";
    response += jsonBody;
    socket->write(response);
    socket->flush();
    socket->disconnectFromHost();
}
