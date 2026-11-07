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
#include <QTemporaryFile>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QXmlStreamReader>

#include <zlib.h>

namespace {

quint16 readLittleEndian16(const QByteArray &data, int offset)
{
    const auto *bytes = reinterpret_cast<const unsigned char *>(data.constData() + offset);
    return static_cast<quint16>(bytes[0] | (bytes[1] << 8));
}

quint32 readLittleEndian32(const QByteArray &data, int offset)
{
    const auto *bytes = reinterpret_cast<const unsigned char *>(data.constData() + offset);
    return static_cast<quint32>(bytes[0])
           | (static_cast<quint32>(bytes[1]) << 8)
           | (static_cast<quint32>(bytes[2]) << 16)
           | (static_cast<quint32>(bytes[3]) << 24);
}

struct ZipEntry
{
    quint16 flags = 0;
    quint16 compression = 0;
    quint32 compressedSize = 0;
    quint32 uncompressedSize = 0;
    quint32 localOffset = 0;
};

QByteArray inflateRawDeflate(const QByteArray &compressed,
                             quint32 expectedSize,
                             QString *error)
{
    QByteArray output;
    output.resize(static_cast<int>(qMax<quint32>(expectedSize, 1)));

    z_stream stream{};
    stream.next_in = reinterpret_cast<Bytef *>(
        const_cast<char *>(compressed.constData()));
    stream.avail_in = static_cast<uInt>(compressed.size());
    stream.next_out = reinterpret_cast<Bytef *>(output.data());
    stream.avail_out = static_cast<uInt>(output.size());

    const int initResult = inflateInit2(&stream, -MAX_WBITS);
    if (initResult != Z_OK) {
        *error = QStringLiteral("无法初始化 DOCX 解压器");
        return {};
    }

    const int inflateResult = inflate(&stream, Z_FINISH);
    const QString zlibMessage = stream.msg ? QString::fromLatin1(stream.msg) : QString();
    inflateEnd(&stream);

    if (inflateResult != Z_STREAM_END
        || (expectedSize > 0 && stream.total_out != expectedSize)) {
        *error = zlibMessage.isEmpty()
            ? QStringLiteral("DOCX 中的 document.xml 解压失败")
            : QStringLiteral("DOCX 解压失败：%1").arg(zlibMessage);
        return {};
    }

    output.resize(static_cast<int>(stream.total_out));
    return output;
}

bool readDocxDocumentXml(QFile &file, QByteArray *xmlData, QString *error)
{
    constexpr qint64 maxXmlSize = 64LL * 1024LL * 1024LL;
    constexpr qint64 maxCentralDirectorySize = 32LL * 1024LL * 1024LL;

    const qint64 fileSize = file.size();
    if (fileSize < 22) {
        *error = QStringLiteral("DOCX 文件过小，不是有效的 ZIP 文档");
        return false;
    }

    // EOCD 位于文件末尾，最长包含 65535 字节注释。
    const int tailSize = static_cast<int>(qMin<qint64>(fileSize, 22 + 65535));
    if (!file.seek(fileSize - tailSize)) {
        *error = QStringLiteral("无法定位 DOCX 的 ZIP 目录");
        return false;
    }
    const QByteArray tail = file.read(tailSize);

    int eocdOffset = -1;
    for (int i = tail.size() - 22; i >= 0; --i) {
        if (readLittleEndian32(tail, i) == 0x06054b50U) {
            eocdOffset = i;
            break;
        }
    }
    if (eocdOffset < 0) {
        *error = QStringLiteral("DOCX 缺少 ZIP 结束目录，文件可能已损坏");
        return false;
    }

    const quint16 entryCount = readLittleEndian16(tail, eocdOffset + 10);
    const quint32 centralSize = readLittleEndian32(tail, eocdOffset + 12);
    const quint32 centralOffset = readLittleEndian32(tail, eocdOffset + 16);
    if (entryCount == 0xffffU || centralSize == 0xffffffffU
        || centralOffset == 0xffffffffU) {
        *error = QStringLiteral("暂不支持 ZIP64 格式的超大 DOCX 文件");
        return false;
    }
    if (centralSize > maxCentralDirectorySize
        || static_cast<quint64>(centralOffset) + centralSize > static_cast<quint64>(fileSize)) {
        *error = QStringLiteral("DOCX 的 ZIP 中央目录无效");
        return false;
    }

    if (!file.seek(centralOffset)) {
        *error = QStringLiteral("无法读取 DOCX 的 ZIP 中央目录");
        return false;
    }
    const QByteArray central = file.read(static_cast<qint64>(centralSize));
    if (central.size() != static_cast<int>(centralSize)) {
        *error = QStringLiteral("DOCX 的 ZIP 中央目录不完整");
        return false;
    }

    ZipEntry targetEntry;
    bool foundDocument = false;
    int position = 0;
    for (quint16 index = 0; index < entryCount; ++index) {
        if (position + 46 > central.size()
            || readLittleEndian32(central, position) != 0x02014b50U) {
            *error = QStringLiteral("DOCX 的 ZIP 条目头无效");
            return false;
        }

        const quint16 nameLength = readLittleEndian16(central, position + 28);
        const quint16 extraLength = readLittleEndian16(central, position + 30);
        const quint16 commentLength = readLittleEndian16(central, position + 32);
        const int nextPosition = position + 46 + nameLength + extraLength + commentLength;
        if (nextPosition > central.size()) {
            *error = QStringLiteral("DOCX 的 ZIP 条目不完整");
            return false;
        }

        const QByteArray name = central.mid(position + 46, nameLength);
        if (name == QByteArrayLiteral("word/document.xml")) {
            targetEntry.flags = readLittleEndian16(central, position + 8);
            targetEntry.compression = readLittleEndian16(central, position + 10);
            targetEntry.compressedSize = readLittleEndian32(central, position + 20);
            targetEntry.uncompressedSize = readLittleEndian32(central, position + 24);
            targetEntry.localOffset = readLittleEndian32(central, position + 42);
            foundDocument = true;
            break;
        }
        position = nextPosition;
    }

    if (!foundDocument) {
        *error = QStringLiteral("DOCX 中不存在 word/document.xml");
        return false;
    }
    if ((targetEntry.flags & 0x1U) != 0) {
        *error = QStringLiteral("暂不支持加密的 DOCX 文件");
        return false;
    }
    if (targetEntry.compression != 0 && targetEntry.compression != 8) {
        *error = QStringLiteral("DOCX 使用了暂不支持的 ZIP 压缩方式");
        return false;
    }
    if (targetEntry.uncompressedSize > maxXmlSize) {
        *error = QStringLiteral("DOCX 的正文 XML 超过 64 MB，已停止解析");
        return false;
    }
    if (targetEntry.localOffset == 0xffffffffU
        || static_cast<quint64>(targetEntry.localOffset) + 30 > static_cast<quint64>(fileSize)) {
        *error = QStringLiteral("DOCX 的正文条目位置无效");
        return false;
    }

    if (!file.seek(targetEntry.localOffset)) {
        *error = QStringLiteral("无法定位 DOCX 正文数据");
        return false;
    }
    const QByteArray localHeader = file.read(30);
    if (localHeader.size() != 30
        || readLittleEndian32(localHeader, 0) != 0x04034b50U) {
        *error = QStringLiteral("DOCX 的正文 ZIP 条目头无效");
        return false;
    }

    const quint16 localNameLength = readLittleEndian16(localHeader, 26);
    const quint16 localExtraLength = readLittleEndian16(localHeader, 28);
    const quint64 dataOffset = static_cast<quint64>(targetEntry.localOffset)
                               + 30 + localNameLength + localExtraLength;
    if (dataOffset + targetEntry.compressedSize > static_cast<quint64>(fileSize)) {
        *error = QStringLiteral("DOCX 的正文压缩数据不完整");
        return false;
    }

    if (!file.seek(static_cast<qint64>(dataOffset))) {
        *error = QStringLiteral("无法读取 DOCX 正文数据");
        return false;
    }
    const QByteArray compressed = file.read(targetEntry.compressedSize);
    if (compressed.size() != static_cast<int>(targetEntry.compressedSize)) {
        *error = QStringLiteral("DOCX 的正文压缩数据读取不完整");
        return false;
    }

    if (targetEntry.compression == 0) {
        if (compressed.size() != static_cast<int>(targetEntry.uncompressedSize)) {
            *error = QStringLiteral("DOCX 正文大小校验失败");
            return false;
        }
        *xmlData = compressed;
    } else {
        *xmlData = inflateRawDeflate(compressed, targetEntry.uncompressedSize, error);
        if (xmlData->isEmpty() && targetEntry.uncompressedSize > 0)
            return false;
    }
    return true;
}

QString docxFileToHtml(const QString &filePath, QString *error)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("无法打开已下载的 DOCX 文件");
        return {};
    }

    QByteArray xmlData;
    if (!readDocxDocumentXml(file, &xmlData, error))
        return {};

    QXmlStreamReader xml(xmlData);
    QString html = QStringLiteral(
        "<html><head><meta charset=\"utf-8\"></head>"
        "<body style=\"font-family:'Microsoft YaHei',sans-serif;"
        "font-size:16px;color:#202124;\">");

    bool sawBody = false;
    bool inParagraph = false;
    bool paragraphHasContent = false;
    bool inTextNode = false;
    bool hasText = false;

    while (!xml.atEnd()) {
        const QXmlStreamReader::TokenType token = xml.readNext();
        if (token == QXmlStreamReader::StartElement) {
            if (xml.name() == QStringLiteral("body")) {
                sawBody = true;
            } else if (xml.name() == QStringLiteral("p")) {
                if (inParagraph)
                    html += QStringLiteral("</p>");
                html += QStringLiteral("<p style=\"margin:0 0 10px 0;\">");
                inParagraph = true;
                paragraphHasContent = false;
            } else if (xml.name() == QStringLiteral("t")) {
                inTextNode = true;
            } else if (xml.name() == QStringLiteral("tab")) {
                if (!inParagraph) {
                    html += QStringLiteral("<p>");
                    inParagraph = true;
                }
                html += QStringLiteral("&nbsp;&nbsp;&nbsp;&nbsp;");
                paragraphHasContent = true;
            } else if (xml.name() == QStringLiteral("br")
                       || xml.name() == QStringLiteral("cr")) {
                if (!inParagraph) {
                    html += QStringLiteral("<p>");
                    inParagraph = true;
                }
                html += QStringLiteral("<br>");
                paragraphHasContent = true;
            }
        } else if (token == QXmlStreamReader::Characters && inTextNode) {
            if (!inParagraph) {
                html += QStringLiteral("<p style=\"margin:0 0 10px 0;\">");
                inParagraph = true;
            }
            const QString text = xml.text().toString();
            if (!text.isEmpty()) {
                html += text.toHtmlEscaped();
                paragraphHasContent = true;
                hasText = hasText || !text.trimmed().isEmpty();
            }
        } else if (token == QXmlStreamReader::EndElement) {
            if (xml.name() == QStringLiteral("t")) {
                inTextNode = false;
            } else if (xml.name() == QStringLiteral("p") && inParagraph) {
                if (!paragraphHasContent)
                    html += QStringLiteral("<br>");
                html += QStringLiteral("</p>");
                inParagraph = false;
            }
        }
    }

    if (xml.hasError()) {
        *error = QStringLiteral("DOCX 正文 XML 解析失败：%1（第 %2 行）")
                     .arg(xml.errorString())
                     .arg(xml.lineNumber());
        return {};
    }
    if (!sawBody) {
        *error = QStringLiteral("DOCX 正文中缺少 body 节点");
        return {};
    }
    if (inParagraph)
        html += QStringLiteral("</p>");
    if (!hasText) {
        html += QStringLiteral(
            "<p style=\"color:#777;\">未提取到可显示的文本。"
            "图片、文本框样式和复杂排版不会在此文本模式中还原。</p>");
    }
    html += QStringLiteral("</body></html>");
    return html;
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

QString UploadManager::serverUrl() const { return m_serverUrl; }
bool UploadManager::uploading() const { return m_uploading; }
bool UploadManager::loadingFiles() const { return m_loadingFiles; }
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

        if (m_documentExtension == QStringLiteral("pdf")) {
            QString error;
            const int pageCount = MuPdfRenderer::pageCount(info.absoluteFilePath(), &error);
            if (pageCount <= 0 || !error.isEmpty()) {
                failDocumentPreview(requestId,
                                    error.isEmpty() ? QStringLiteral("PDF 中没有可显示的页面")
                                                    : error);
                return;
            }
            emit pdfPreviewReady(requestId,
                                 QUrl::fromLocalFile(info.absoluteFilePath())
                                     .toString(QUrl::FullyEncoded),
                                 pageCount);
            return;
        }

        QString error;
        const QString html = docxFileToHtml(info.absoluteFilePath(), &error);
        if (!error.isEmpty()) {
            failDocumentPreview(requestId, error);
            return;
        }
        emit docxPreviewReady(requestId, html);
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
    if (m_documentExtension == QStringLiteral("pdf")) {
        QString error;
        const int pageCount = MuPdfRenderer::pageCount(filePath, &error);
        if (pageCount <= 0 || !error.isEmpty()) {
            failDocumentPreview(requestId,
                                error.isEmpty() ? QStringLiteral("PDF 中没有可显示的页面")
                                                : error);
            return;
        }

        // 临时文件由 UploadManager 持有，关闭预览时再删除，确保 MuPDF 可持续按需翻页。
        emit pdfPreviewReady(requestId,
                             QUrl::fromLocalFile(filePath).toString(QUrl::FullyEncoded),
                             pageCount);
        return;
    }

    QString error;
    const QString html = docxFileToHtml(filePath, &error);
    delete m_documentFile;
    m_documentFile = nullptr;

    if (!error.isEmpty()) {
        failDocumentPreview(requestId, error);
        return;
    }
    emit docxPreviewReady(requestId, html);
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

    delete m_documentFile;
    m_documentFile = nullptr;
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
