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
#include <QMimeDatabase>
#include <QMimeType>
#include <QRegularExpression>
#include <QSet>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>

#include <QDebug>

namespace {

QString uploadedFilesPath()
{
    return QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("uploaded_files"));
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
                         QJsonArray *items)
{
    int fileCount = 0;
    const QFileInfoList entries = directory.entryInfoList(
        QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Readable,
        QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);

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
                QDir(info.absoluteFilePath()), relativePath, items);

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
}

bool LocalUploadServer::listen(quint16 port)
{
    const bool ok = m_server.listen(QHostAddress::LocalHost, port);
    if (ok) {
        qInfo().noquote() << QStringLiteral("FileSync 本地测试服务已启动：")
                          << QStringLiteral("http://127.0.0.1:%1/upload").arg(m_server.serverPort());
        qInfo().noquote() << QStringLiteral("文件列表接口：")
                          << QStringLiteral("http://127.0.0.1:%1/files").arg(m_server.serverPort());
        qInfo().noquote() << QStringLiteral("上传目录：%1").arg(uploadedFilesPath());
    } else {
        qCritical().noquote() << QStringLiteral("监听失败：%1").arg(m_server.errorString());
    }
    return ok;
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
        processFilesRequest(socket);
        return;
    }

    if (method == QByteArrayLiteral("GET") && requestPath == QStringLiteral("/file")) {
        processFileRequest(socket, requestUrl);
        return;
    }

    // 当前测试服务只支持 POST /upload、GET /files 和 GET /file。
    if (method != QByteArrayLiteral("POST") || requestPath != QStringLiteral("/upload")) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("接口不存在，请使用 GET /files、GET /file 或 POST /upload")}
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
                     {QStringLiteral("message"), QStringLiteral("测试服务端仅允许 512 MB 以内的文件")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }

    const qint64 bodyStart = headerEnd + 4;
    if (buffer.size() < bodyStart + contentLength)
        return;

    const QByteArray body = buffer.mid(static_cast<int>(bodyStart),
                                       static_cast<int>(contentLength));
    processRequest(socket, headerBlock, body);
}

void LocalUploadServer::processFilesRequest(QTcpSocket *socket)
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

    QJsonArray items;
    const int totalFiles = appendDirectoryItems(rootDir, QString(), &items);

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("totalFiles"), totalFiles},
        {QStringLiteral("totalItems"), items.size()},
        {QStringLiteral("items"), items}
    };

    qInfo().noquote() << QStringLiteral("文件列表查询成功：%1 个文件，%2 个条目")
                             .arg(totalFiles)
                             .arg(items.size());

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

void LocalUploadServer::processRequest(QTcpSocket *socket,
                                       const QByteArray &headerBlock,
                                       const QByteArray &body)
{
    const QList<QByteArray> lines = headerBlock.split('\n');
    if (lines.isEmpty() || !lines.first().trimmed().startsWith(QByteArrayLiteral("POST /upload "))) {
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
    QDir outputDir(QCoreApplication::applicationDirPath());
    if (!outputDir.mkpath(QStringLiteral("uploaded_files"))) {
        sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                 QJsonDocument(QJsonObject{
                     {QStringLiteral("success"), false},
                     {QStringLiteral("message"), QStringLiteral("无法创建上传目录")}
                 }).toJson(QJsonDocument::Compact));
        return;
    }
    outputDir.cd(QStringLiteral("uploaded_files"));

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

    const QJsonObject responseObject{
        {QStringLiteral("success"), true},
        {QStringLiteral("fileName"), originalName},
        {QStringLiteral("savedAs"), saveName},
        {QStringLiteral("size"), static_cast<double>(fileData.size())}
    };
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
    response += "Connection: close\r\n\r\n";
    response += jsonBody;
    socket->write(response);
    socket->flush();
    socket->disconnectFromHost();
}
