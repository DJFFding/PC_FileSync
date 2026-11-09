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
 *   GET  /folders?path= 返回指定目录的直接子文件夹，供移动目标选择器使用
 *   POST /rename      接收 JSON { "path": "原云端路径", "newName": "新名称" }
 *   POST /move        接收 JSON { "path": "原云端路径", "destinationPath": "目标文件夹" }
 *   GET  /favorites   返回真实收藏列表；文件夹及其后代分别作为独立收藏项
 *   POST /favorites   接收 JSON { "path": "云端路径", "recursive": true }
 *   POST /favorites/remove 取消指定路径收藏；recursive 为 true 时同时取消后代
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

    // 每个条目在首次上传/创建时获得固定顺序号；重命名或移动只修改路径键，不修改顺序号。
    // 顺序表保存在应用目录中，服务重启后仍可恢复原有展示顺序。
    void loadItemOrder();
    void synchronizeItemOrder();
    void saveItemOrder() const;
    void registerItemOrder(const QString &cloudPath);
    void moveItemOrder(const QString &oldCloudPath, const QString &newCloudPath);

    // 收藏只保存云端相对路径和收藏时间，元数据文件不放在 uploaded_files 内。
    void loadFavorites();
    bool saveFavorites() const;
    void synchronizeFavorites();
    void moveFavorites(const QString &oldCloudPath, const QString &newCloudPath);
    void broadcastFavoritesChanged(const QString &cloudPath);

    void readRequest(QTcpSocket *socket);
    void processRequest(QTcpSocket *socket,
                        const QUrl &requestUrl,
                        const QByteArray &headerBlock,
                        const QByteArray &body);
    void processFilesRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processFoldersRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processFileRequest(QTcpSocket *socket, const QUrl &requestUrl);
    void processCreateFolderRequest(QTcpSocket *socket, const QByteArray &body);
    void processRenameRequest(QTcpSocket *socket, const QByteArray &body);
    void processMoveRequest(QTcpSocket *socket, const QByteArray &body);
    void processFavoritesRequest(QTcpSocket *socket);
    void processAddFavoriteRequest(QTcpSocket *socket, const QByteArray &body);
    void processRemoveFavoriteRequest(QTcpSocket *socket, const QByteArray &body);
    void processTrashRequest(QTcpSocket *socket);
    void processMoveToTrashRequest(QTcpSocket *socket, const QByteArray &body);
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
    QHash<QString, quint64> m_itemOrder;
    QHash<QString, QString> m_favoriteTimes;
    QString m_storageRoot;
    quint64 m_nextItemOrder = 1;
    quint64 m_revision = 0;
    bool m_watchInitialized = false;
};
