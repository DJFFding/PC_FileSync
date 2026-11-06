#pragma once

#include <QObject>
#include <QHash>
#include <QTcpServer>

class QTcpSocket;

/**
 * 仅用于本机联调的简易 multipart 上传服务端。
 * 监听 127.0.0.1:8080，接收 POST /upload，并保存到程序目录/uploaded_files。
 * 注意：此示例将请求体暂存在内存中，不适合直接用于生产环境或超大文件。
 */
class LocalUploadServer final : public QObject
{
    Q_OBJECT
public:
    explicit LocalUploadServer(QObject *parent = nullptr);
    bool listen(quint16 port = 8080);

private:
    void readRequest(QTcpSocket *socket);
    void processRequest(QTcpSocket *socket,
                        const QByteArray &headerBlock,
                        const QByteArray &body);
    void sendJson(QTcpSocket *socket, int statusCode,
                  const QByteArray &reason,
                  const QByteArray &jsonBody);

    QTcpServer m_server;
    QHash<QTcpSocket *, QByteArray> m_buffers;
};
