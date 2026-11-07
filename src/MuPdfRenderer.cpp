#include "MuPdfRenderer.h"

#include <mupdf/fitz.h>

#include <QCache>
#include <QFile>
#include <QFileInfo>
#include <QGlobalStatic>
#include <QMutex>
#include <QMutexLocker>

#include <algorithm>
#include <cstring>
#include <limits>

namespace
{
constexpr int kMaximumCacheCostMB = 384;
constexpr int kMuPdfStoreBytes = 64 * 1024 * 1024;

struct PdfDataCache
{
    QMutex mutex;
    QCache<QString, QByteArray> files;

    PdfDataCache()
    {
        files.setMaxCost(kMaximumCacheCostMB);
    }
};

Q_GLOBAL_STATIC(PdfDataCache, g_pdfDataCache)

QString cacheKey(const QFileInfo &info)
{
    return QStringLiteral("%1|%2|%3")
        .arg(info.absoluteFilePath())
        .arg(info.size())
        .arg(info.lastModified().toMSecsSinceEpoch());
}

QByteArray readPdfData(const QString &filePath, QString *error)
{
    const QFileInfo info(filePath);
    if (!info.exists() || !info.isFile() || !info.isReadable()) {
        if (error)
            *error = QStringLiteral("PDF 文件不存在或无法读取");
        return {};
    }

    const QString key = cacheKey(info);
    if (g_pdfDataCache) {
        QMutexLocker locker(&g_pdfDataCache->mutex);
        if (const QByteArray *cached = g_pdfDataCache->files.object(key))
            return *cached;
    }

    QFile file(info.absoluteFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) {
            *error = QStringLiteral("无法打开 PDF：%1").arg(file.errorString());
        }
        return {};
    }

    QByteArray data = file.readAll();
    if (data.isEmpty()) {
        if (error) {
            *error = file.error() != QFileDevice::NoError
                ? QStringLiteral("读取 PDF 失败：%1").arg(file.errorString())
                : QStringLiteral("PDF 文件为空");
        }
        return {};
    }

    const qsizetype size = data.size();
    const qsizetype costMB = std::max<qsizetype>(
        1, (size + 1024 * 1024 - 1) / (1024 * 1024));
    if (g_pdfDataCache && costMB <= kMaximumCacheCostMB
        && costMB <= std::numeric_limits<int>::max()) {
        QMutexLocker locker(&g_pdfDataCache->mutex);
        g_pdfDataCache->files.insert(
            key, new QByteArray(data), static_cast<int>(costMB));
    }
    return data;
}

QString caughtMessage(fz_context *context, const QString &fallback)
{
    const char *message = fz_caught_message(context);
    return message && *message
        ? QString::fromUtf8(message)
        : fallback;
}

class PdfSession final
{
public:
    PdfSession() = default;
    ~PdfSession()
    {
        if (m_context) {
            fz_drop_document(m_context, m_document);
            fz_drop_context(m_context);
        }
    }

    PdfSession(const PdfSession &) = delete;
    PdfSession &operator=(const PdfSession &) = delete;

    bool initialize(QString *error)
    {
        m_context = fz_new_context(nullptr, nullptr, kMuPdfStoreBytes);
        if (!m_context) {
            if (error)
                *error = QStringLiteral("无法创建 MuPDF 上下文");
            return false;
        }

        bool registered = false;
        fz_var(registered);
        fz_try(m_context)
        {
            fz_register_document_handlers(m_context);
            registered = true;
        }
        fz_catch(m_context)
        {
            if (error) {
                *error = QStringLiteral("MuPDF 初始化失败：%1")
                    .arg(caughtMessage(m_context, QStringLiteral("未知错误")));
            }
        }
        return registered;
    }

    bool open(const QByteArray &data, QString *error)
    {
        if (!m_context || data.isEmpty())
            return false;

        // 成员数据在析构函数释放 fz_document/fz_context 之后才会销毁。
        m_data = data;

        fz_stream *stream = nullptr;
        fz_document *document = nullptr;
        fz_var(stream);
        fz_var(document);

        fz_try(m_context)
        {
            stream = fz_open_memory(
                m_context,
                reinterpret_cast<const unsigned char *>(m_data.constData()),
                static_cast<size_t>(m_data.size()));
            document = fz_open_document_with_stream(
                m_context, "application/pdf", stream);
        }
        fz_catch(m_context)
        {
            if (error) {
                *error = QStringLiteral("PDF 解析失败：%1")
                    .arg(caughtMessage(m_context, QStringLiteral("未知错误")));
            }
        }

        // fz_document 自己持有流引用；这里释放调用方的引用。
        fz_drop_stream(m_context, stream);
        if (!document)
            return false;

        m_document = document;
        return true;
    }

    int pageCount(QString *error) const
    {
        if (!m_document)
            return 0;

        int count = 0;
        bool passwordRequired = false;
        fz_var(count);
        fz_var(passwordRequired);
        fz_try(m_context)
        {
            passwordRequired = fz_needs_password(m_context, m_document) != 0;
            if (!passwordRequired)
                count = fz_count_pages(m_context, m_document);
        }
        fz_catch(m_context)
        {
            if (error) {
                *error = QStringLiteral("读取 PDF 页数失败：%1")
                    .arg(caughtMessage(m_context, QStringLiteral("未知错误")));
            }
            return 0;
        }

        if (passwordRequired) {
            if (error)
                *error = QStringLiteral("暂不支持需要密码的 PDF");
            return 0;
        }
        if (count <= 0 && error)
            *error = QStringLiteral("PDF 中没有可显示的页面");
        return count;
    }

    QImage renderPage(int pageIndex, int targetWidth, QString *error) const
    {
        if (!m_document)
            return {};

        fz_page *page = nullptr;
        fz_pixmap *pixmap = nullptr;
        fz_var(page);
        fz_var(pixmap);
        bool invalidPage = false;
        bool invalidBounds = false;
        fz_var(invalidPage);
        fz_var(invalidBounds);

        fz_try(m_context)
        {
            const int count = fz_count_pages(m_context, m_document);
            if (pageIndex < 0 || pageIndex >= count) {
                invalidPage = true;
            } else {
                page = fz_load_page(m_context, m_document, pageIndex);
                const fz_rect bounds = fz_bound_page(m_context, page);
                const float pageWidth = bounds.x1 - bounds.x0;
                const float pageHeight = bounds.y1 - bounds.y0;
                if (pageWidth <= 0.0f || pageHeight <= 0.0f) {
                    invalidBounds = true;
                } else {
                    const float scale = static_cast<float>(targetWidth) / pageWidth;
                    pixmap = fz_new_pixmap_from_page(
                        m_context, page, fz_scale(scale, scale),
                        fz_device_rgb(m_context), 0);
                }
            }
        }
        fz_catch(m_context)
        {
            if (error) {
                *error = QStringLiteral("PDF 第 %1 页渲染失败：%2")
                    .arg(pageIndex + 1)
                    .arg(caughtMessage(m_context, QStringLiteral("未知错误")));
            }
        }

        QImage image;
        if (pixmap && pixmap->w > 0 && pixmap->h > 0
            && pixmap->n >= 3 && pixmap->samples) {
            image = QImage(pixmap->w, pixmap->h, QImage::Format_RGB888);
            if (image.isNull()) {
                if (error)
                    *error = QStringLiteral("无法分配 PDF 页面图像内存");
            } else {
                for (int y = 0; y < pixmap->h; ++y) {
                    std::memcpy(image.scanLine(y),
                                pixmap->samples + y * pixmap->stride,
                                static_cast<size_t>(pixmap->w) * 3);
                }
            }
        } else if (!invalidPage && !invalidBounds && error && error->isEmpty()) {
            *error = QStringLiteral("PDF 第 %1 页没有渲染结果").arg(pageIndex + 1);
        }

        fz_drop_pixmap(m_context, pixmap);
        fz_drop_page(m_context, page);

        if (invalidPage && error)
            *error = QStringLiteral("PDF 页码超出范围");
        else if (invalidBounds && error)
            *error = QStringLiteral("PDF 第 %1 页尺寸无效").arg(pageIndex + 1);
        return image;
    }

private:
    fz_context *m_context = nullptr;
    fz_document *m_document = nullptr;
    QByteArray m_data;
};

bool openSession(const QString &filePath, PdfSession *session, QString *error)
{
    const QByteArray data = readPdfData(filePath, error);
    return !data.isEmpty() && session->initialize(error) && session->open(data, error);
}
}

int MuPdfRenderer::pageCount(const QString &filePath, QString *error)
{
    if (error)
        error->clear();

    PdfSession session;
    if (!openSession(filePath, &session, error))
        return 0;

    return session.pageCount(error);
}

QImage MuPdfRenderer::renderPage(const QString &filePath,
                                 int pageIndex,
                                 int targetWidth,
                                 QString *error)
{
    if (error)
        error->clear();

    PdfSession session;
    if (!openSession(filePath, &session, error))
        return {};

    const int boundedWidth = std::clamp(targetWidth, 256, 4096);
    return session.renderPage(pageIndex, boundedWidth, error);
}

void MuPdfRenderer::clearCache()
{
    if (g_pdfDataCache) {
        QMutexLocker locker(&g_pdfDataCache->mutex);
        g_pdfDataCache->files.clear();
    }
}
