#pragma once

#include <QStringList>

namespace Zalos::Core::Platform::DependencyReport {

struct Line {
    QString key;
    QString value;
    bool essential{false};
    bool ok{true};
};

QList<Line> collect();
int run();

}
