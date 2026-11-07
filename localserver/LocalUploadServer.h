#pragma once

#include <QObject>
#include <QHash>
#include <QTcpServer>

class QTcpSocket;
class QUrl;

/**
 * 仅用于本机联调的简易 HTTP 文件服务端。
 * 监听 127.0.0.1:8080：
 *   POST /upload      接收 multipart/form-data 文件并保存到程序目录/uploaded_files
 *   POST /folders     接收 JSON { "name": "文件夹名称" }，在上传根目录新建文件夹
 *   GET  /files       递归返回 uploaded_files 中的文件和目录清单
 *   GET  /file?path=  返回指定文件内容，供 QML 图片/文本/文档预览使用
 *                      可选 offset/maxBytes 用于文本分块加载
 *
 * 注意：此示例将上传请求体暂存在内存中，不适合直接用于生产环境或超大文件。
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
    void processFilesRequest(QTcpSocket *socket);
    void processFileRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processCreateFolderRequest(QTcpSocket *socket, const QByteArray &body);
    void sendJson(QTcpSocket *socket, int statusCode,
                  const QByteArray &reason,
                  const QByteArray &jsonBody);

    QTcpServer m_server;
    QHash<QTcpSocket *, QByteArray> m_buffers;
};
