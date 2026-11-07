#pragma once

#include <QQuickImageProvider>

// 在 main.cpp 创建 QQmlApplicationEngine 后、加载 QML 前注册：
// engine.addImageProvider(QStringLiteral("mupdf"), new MuPdfImageProvider);
// QQmlEngine 会接管 provider 的所有权。
class MuPdfImageProvider final : public QQuickImageProvider
{
public:
    MuPdfImageProvider();

    QImage requestImage(const QString &id,
                        QSize *size,
                        const QSize &requestedSize) override;
};
