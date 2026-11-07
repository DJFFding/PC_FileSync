#pragma once

#include <QImage>
#include <QString>

// 每次调用使用独立的 fz_context，因而可由 QQuickImageProvider 的渲染线程并行调用。
// 文件先由 QFile 读入内存，避免 MuPDF 直接处理 Windows 中文路径。
namespace MuPdfRenderer
{
int pageCount(const QString &filePath, QString *error = nullptr);
QImage renderPage(const QString &filePath,
                  int pageIndex,
                  int targetWidth,
                  QString *error = nullptr);
void clearCache();
}
