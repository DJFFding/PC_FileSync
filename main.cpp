#include "UploadManager.h"
#include "MuPdfImageProvider.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQmlContext>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    UploadManager uploadManager;
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.addImageProvider(QStringLiteral("mupdf"),
                            new MuPdfImageProvider);
    engine.rootContext()->setContextProperty(
        "uploadManager",
        &uploadManager
        );
    engine.loadFromModule("FileSync", "Main");
    return app.exec();
}
