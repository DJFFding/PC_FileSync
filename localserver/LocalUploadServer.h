#pragma once

#include <QObject>
#include <QFileSystemWatcher>
#include <QHash>
#include <QList>
#include <QSet>
#include <QTcpServer>
#include <QTimer>
#include <QWebSocketServer>

class QTcpSocket;
class QUrl;
class QWebSocket;

/**
 * 仅用于本机联调的简易文件服务端。
 *
 * HTTP 默认监听 127.0.0.1:8080，负责文件内容和列表传输：
 *   POST /upload?path= 接收 multipart/form-data 文件并保存到指定云端目录
 *   POST /folders     接收 JSON { "name": "文件夹名称", "path": "父目录" }
 *   GET  /files?path= 返回指定目录的直接子项，以及该目录的递归文件统计
 *   GET  /file?path=  返回指定文件内容，供 QML 图片/文本/文档预览使用
 *                      可选 offset/maxBytes 用于文本分块加载
 *
 * WebSocket 默认监听 127.0.0.1:8081/events，主动推送：
 *   { "type": "filesChanged", "revision": 1, "paths": ["dir/a.txt"] }
 * 服务器递归监听上传目录，因此直接修改服务器目录中的文件也会触发通知。
 *
 * 注意：此示例将上传请求体暂存在内存中，不适合直接用于生产环境或超大文件。
 */
class LocalUploadServer final : public QObject
{
    Q_OBJECT
public:
    explicit LocalUploadServer(QObject *parent = nullptr);

    // eventPort 为 0 时使用 port + 1，例如 HTTP 8080、WebSocket 8081。
    bool listen(quint16 port = 8080, quint16 eventPort = 0);

private:
    void handleEventConnection();
    void rebuildFileSystemWatch();
    void queueFileChange(const QString &cloudPath);
    void broadcastFileChanges();
    QString cloudPathForFileName(const QString &absolutePath) const;

    void readRequest(QTcpSocket *socket);
    void processRequest(QTcpSocket *socket,
                        const QUrl &requestUrl,
                        const QByteArray &headerBlock,
                        const QByteArray &body);
    void processFilesRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processFileRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processCreateFolderRequest(QTcpSocket *socket, const QByteArray &body);
    void sendJson(QTcpSocket *socket, int statusCode,
                  const QByteArray &reason,
                  const QByteArray &jsonBody);

    QTcpServer m_server;
    QHash<QTcpSocket *, QByteArray> m_buffers;

    QWebSocketServer m_eventServer;
    QList<QWebSocket *> m_eventClients;
    QFileSystemWatcher m_fileWatcher;
    QTimer m_changeTimer;
    QSet<QString> m_knownPaths;
    QSet<QString> m_pendingChanges;
    QString m_storageRoot;
    quint64 m_revision = 0;
    bool m_watchInitialized = false;
};
