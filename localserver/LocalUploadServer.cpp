#include "LocalUploadServer.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTcpSocket>
#include <QUrl>
#include <QUuid>

#include <QDebug>

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
        qInfo().noquote() << QStringLiteral("FileSync 本地上传测试服务已启动：http://127.0.0.1:%1/upload")
                                 .arg(m_server.serverPort());
        qInfo().noquote() << QStringLiteral("上传目录：%1")
                                 .arg(QDir(QCoreApplication::applicationDirPath())
                                          .filePath(QStringLiteral("uploaded_files")));
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
    const QRegularExpression lengthExpression(
        QStringLiteral("(?:^|\\r\\n)content-length\\s*:\\s*(\\d+)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch lengthMatch = lengthExpression.match(
        QString::fromLatin1(headerBlock));
    if (!lengthMatch.hasMatch()) {
        sendJson(socket, 411, QByteArrayLiteral("Length Required"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("缺少 Content-Length")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }

    bool lengthOk = false;
    const qint64 contentLength = lengthMatch.captured(1).toLongLong(&lengthOk);
    if (!lengthOk || contentLength < 0 || contentLength > 512LL * 1024LL * 1024LL) {
        sendJson(socket, 413, QByteArrayLiteral("Payload Too Large"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("测试服务端仅允许 512 MB 以内的文件")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }

    const qint64 bodyStart = headerEnd + 4;
    if (buffer.size() < bodyStart + contentLength)
        return;

    const QByteArray body = buffer.mid(static_cast<int>(bodyStart),
                                       static_cast<int>(contentLength));
    processRequest(socket, headerBlock, body);
}

void LocalUploadServer::processRequest(QTcpSocket *socket,
                                       const QByteArray &headerBlock,
                                       const QByteArray &body)
{
    const QList<QByteArray> lines = headerBlock.split('\n');
    if (lines.isEmpty() || !lines.first().trimmed().startsWith(QByteArrayLiteral("POST /upload "))) {
        sendJson(socket, 404, QByteArrayLiteral("Not Found"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("接口不存在，请使用 POST /upload")}})
                     .toJson(QJsonDocument::Compact));
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
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("multipart boundary 无效")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }

    const QByteArray boundary = (boundaryMatch.captured(1).isEmpty()
                                     ? boundaryMatch.captured(2)
                                     : boundaryMatch.captured(1)).toLatin1();
    const QByteArray separator = QByteArrayLiteral("\r\n\r\n");
    const int partHeaderEnd = body.indexOf(separator);
    if (partHeaderEnd < 0) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("multipart 内容格式错误")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }

    const QByteArray partHeaders = body.left(partHeaderEnd);
    const QByteArray delimiter = QByteArrayLiteral("\r\n--") + boundary;
    const int dataStart = partHeaderEnd + separator.size();
    const int dataEnd = body.indexOf(delimiter, dataStart);
    if (dataEnd < dataStart) {
        sendJson(socket, 400, QByteArrayLiteral("Bad Request"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("没有找到文件数据")}})
                     .toJson(QJsonDocument::Compact));
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
        fileName = QStringLiteral("upload_%1.bin").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));

    // 测试服务端额外清理 Windows/Linux 文件名中的非法字符。
    for (qsizetype i = 0; i < fileName.size(); ++i) {
        if (QStringLiteral("<>:\"/\\|?*").contains(fileName.at(i)))
            fileName[i] = QLatin1Char('_');
    }

    const QByteArray fileData = body.mid(dataStart, dataEnd - dataStart);
    QDir outputDir(QCoreApplication::applicationDirPath());
    if (!outputDir.mkpath(QStringLiteral("uploaded_files"))) {
        sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("无法创建上传目录")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }
    outputDir.cd(QStringLiteral("uploaded_files"));

    const QString originalName = fileName;
    QFileInfo nameInfo(fileName);
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
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("无法写入上传文件")}})
                     .toJson(QJsonDocument::Compact));
        return;
    }
    const qint64 written = outputFile.write(fileData);
    outputFile.close();
    if (written != fileData.size()) {
        outputFile.remove();
        sendJson(socket, 500, QByteArrayLiteral("Internal Server Error"),
                 QJsonDocument(QJsonObject{{QStringLiteral("success"), false},
                                           {QStringLiteral("message"), QStringLiteral("文件写入不完整")}})
                     .toJson(QJsonDocument::Compact));
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
