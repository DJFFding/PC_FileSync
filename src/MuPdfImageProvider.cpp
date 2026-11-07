#include "MuPdfImageProvider.h"

#include "MuPdfRenderer.h"

#include <QDebug>
#include <QUrl>
#include <QUrlQuery>

MuPdfImageProvider::MuPdfImageProvider()
    : QQuickImageProvider(QQmlImageProviderBase::Image,
                          QQmlImageProviderBase::ForceAsynchronousImageLoading)
{
}

QImage MuPdfImageProvider::requestImage(const QString &id,
                                        QSize *size,
                                        const QSize &requestedSize)
{
    // QML 地址形式：
    // image://mupdf/render?source=<编码后的 file URL>&page=0&width=1600&request=1
    const QUrl requestUrl(QStringLiteral("image://mupdf/") + id);
    const QUrlQuery query(requestUrl);

    bool pageOk = false;
    bool widthOk = false;
    const int pageIndex = query.queryItemValue(QStringLiteral("page")).toInt(&pageOk);
    int targetWidth = query.queryItemValue(QStringLiteral("width")).toInt(&widthOk);
    if (!widthOk && requestedSize.width() > 0) {
        targetWidth = requestedSize.width();
        widthOk = true;
    }

    const QString source = query.queryItemValue(
        QStringLiteral("source"), QUrl::FullyDecoded);
    const QUrl sourceUrl(source);
    if (!pageOk || pageIndex < 0 || !widthOk || targetWidth <= 0
        || !sourceUrl.isValid() || !sourceUrl.isLocalFile()) {
        qWarning() << "Invalid MuPDF image request:" << id;
        return {};
    }

    QString error;
    QImage image = MuPdfRenderer::renderPage(
        sourceUrl.toLocalFile(), pageIndex, targetWidth, &error);
    if (image.isNull()) {
        qWarning() << "MuPDF page render failed:" << error;
        return {};
    }

    if (size)
        *size = image.size();
    return image;
}
