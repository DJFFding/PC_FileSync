#include "LocalUploadServer.h"

#include <QCoreApplication>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    LocalUploadServer server;
    if (!server.listen(8080))
        return 1;

    return app.exec();
}
