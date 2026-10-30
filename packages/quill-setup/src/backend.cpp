#include "backend.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <algorithm>

namespace {
const char *kDefaultGroupsDir = "/usr/share/quill-setup/groups";
const char *kDefaultHelper = "/usr/libexec/quill-setup-helper";
// pkexec exits with these when the user dismisses or fails the password prompt.
const int kPkexecNotAuthorized = 127;
const int kPkexecDismissed = 126;
}

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    loadGroups();
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_buffer += m_process.readAllStandardOutput();
        int nl;
        while ((nl = m_buffer.indexOf('\n')) >= 0) {
            handleLine(m_buffer.left(nl));
            m_buffer.remove(0, nl + 1);
        }
    });
    connect(&m_process, &QProcess::finished, this, &Backend::handleFinished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_error = tr("Could not start the installer.");
            emit errorChanged();
            setBusy(false);
        }
    });
}

void Backend::loadGroups()
{
    // QUILL_SETUP_GROUPS lets tests and screenshots point at other definitions.
    const QString dir = qEnvironmentVariable("QUILL_SETUP_GROUPS", kDefaultGroupsDir);
    QList<QVariantMap> groups;
    const auto files = QDir(dir).entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : files) {
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        if (o.value(QStringLiteral("id")).toString().isEmpty())
            continue;
        QVariantMap g;
        g[QStringLiteral("id")] = o.value(QStringLiteral("id")).toString();
        g[QStringLiteral("name")] = o.value(QStringLiteral("name")).toString();
        g[QStringLiteral("description")] = o.value(QStringLiteral("description")).toString();
        g[QStringLiteral("order")] = o.value(QStringLiteral("order")).toInt();
        g[QStringLiteral("count")] = o.value(QStringLiteral("rpm")).toArray().size()
            + o.value(QStringLiteral("flatpak")).toArray().size();
        groups.append(g);
    }
    std::sort(groups.begin(), groups.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value(QStringLiteral("order")).toInt() < b.value(QStringLiteral("order")).toInt();
    });
    for (const QVariantMap &g : groups)
        m_groups.append(g);
}

QString Backend::markerPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation) + QStringLiteral("/done");
}

bool Backend::alreadyDone() const
{
    return QFile::exists(markerPath());
}

void Backend::markDone()
{
    QDir().mkpath(QFileInfo(markerPath()).absolutePath());
    QFile f(markerPath());
    if (f.open(QIODevice::WriteOnly))
        f.close();
}

void Backend::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void Backend::install(const QStringList &groupIds)
{
    if (m_busy || groupIds.isEmpty())
        return;
    // The helper validates too; refusing here just keeps junk out of the argument list.
    static const QRegularExpression valid(QStringLiteral("^[a-z][a-z0-9-]*$"));
    for (const QString &id : groupIds) {
        if (!valid.match(id).hasMatch())
            return;
    }

    m_log.clear();
    m_error.clear();
    m_stage = tr("Waiting for authorization…");
    m_progress = 0;
    m_sawDone = false;
    m_buffer.clear();
    emit logChanged();
    emit errorChanged();
    emit stageChanged();
    emit progressChanged();
    setBusy(true);

    // QUILL_SETUP_HELPER_CMD replaces "pkexec <helper>" in tests, e.g. with a dry run.
    QStringList cmd = qEnvironmentVariableIsSet("QUILL_SETUP_HELPER_CMD")
        ? qEnvironmentVariable("QUILL_SETUP_HELPER_CMD").split(QLatin1Char(' '), Qt::SkipEmptyParts)
        : QStringList{QStringLiteral("pkexec"), QString::fromLatin1(kDefaultHelper)};
    const QString program = cmd.takeFirst();
    cmd << QStringLiteral("install") << groupIds;
    m_process.setProcessChannelMode(QProcess::SeparateChannels);
    m_process.start(program, cmd);
}

void Backend::handleLine(const QByteArray &line)
{
    const QJsonObject o = QJsonDocument::fromJson(line).object();
    if (o.isEmpty())
        return;
    const QString event = o.value(QStringLiteral("event")).toString();
    if (event == QLatin1String("step")) {
        m_stage = o.value(QStringLiteral("name")).toString();
        m_progress = o.value(QStringLiteral("fraction")).toDouble();
        emit stageChanged();
        emit progressChanged();
    } else if (event == QLatin1String("log")) {
        m_log += o.value(QStringLiteral("line")).toString() + QLatin1Char('\n');
        emit logChanged();
    } else if (event == QLatin1String("done")) {
        m_sawDone = true;
        m_progress = 1;
        emit progressChanged();
    } else if (event == QLatin1String("error")) {
        m_error = o.value(QStringLiteral("message")).toString();
        emit errorChanged();
    }
}

void Backend::handleFinished(int exitCode, QProcess::ExitStatus status)
{
    setBusy(false);
    if (status == QProcess::NormalExit && exitCode == 0 && m_sawDone) {
        markDone();
        m_stage = tr("All done");
        m_finished = true;
        emit stageChanged();
        emit finishedChanged();
        return;
    }
    if (m_error.isEmpty()) {
        m_error = (exitCode == kPkexecDismissed || exitCode == kPkexecNotAuthorized)
            ? tr("Authorization was cancelled, so nothing was installed.")
            : tr("The installation did not finish (exit code %1).").arg(exitCode);
        emit errorChanged();
    }
}

void Backend::skip()
{
    markDone();
    quit();
}

void Backend::quit()
{
    QCoreApplication::quit();
}
