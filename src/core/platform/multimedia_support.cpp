#include "multimedia_support.h"

#include <QCoreApplication>
#include <QDir>
#include <QLibraryInfo>
#include <QPluginLoader>

namespace Zalos::Core::Platform::MultimediaSupport {

namespace {

struct Probe {
    bool available{false};
    QString reason;
};

Probe probe() {
    Probe result;
    QStringList roots = QCoreApplication::libraryPaths();
    roots << QLibraryInfo::path(QLibraryInfo::PluginsPath);
    roots.removeDuplicates();
    bool sawPlugin = false;
    for (const QString& root : std::as_const(roots)) {
        const QDir dir(QDir(root).filePath(QStringLiteral("multimedia")));
        for (const QString& file : dir.entryList({QStringLiteral("*.so")}, QDir::Files)) {
            sawPlugin = true;
            QPluginLoader loader(dir.filePath(file));
            if (loader.load()) {
                result.available = true;
                return result;
            }
            if (result.reason.isEmpty()) result.reason = file + QStringLiteral(": ") + loader.errorString();
        }
    }
    if (!sawPlugin) result.reason = QStringLiteral("no Qt Multimedia backend plugin");
    return result;
}

const Probe& cached() {
    static const Probe value = probe();
    return value;
}

}

bool available() {
    if (qEnvironmentVariableIsSet("ZALOS_NO_MULTIMEDIA")) return false;
    return cached().available;
}

QString unavailableReason() {
    if (qEnvironmentVariableIsSet("ZALOS_NO_MULTIMEDIA")) return QStringLiteral("disabled by ZALOS_NO_MULTIMEDIA");
    return cached().reason;
}

}
