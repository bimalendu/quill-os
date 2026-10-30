#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>

// Everything the QML window needs: the list of package groups, and a runner
// that asks the privileged helper (via pkexec) to install the chosen ones.
// The UI only ever names group IDs; package names stay inside the helper.
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList groups READ groups CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool finished READ finished NOTIFY finishedChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY stageChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    QVariantList groups() const { return m_groups; }
    bool busy() const { return m_busy; }
    bool finished() const { return m_finished; }
    double progress() const { return m_progress; }
    QString stage() const { return m_stage; }
    QString log() const { return m_log; }
    QString error() const { return m_error; }

    // True once the user has installed or skipped; the autostart entry then does nothing.
    bool alreadyDone() const;

    Q_INVOKABLE void install(const QStringList &groupIds);
    Q_INVOKABLE void skip();
    Q_INVOKABLE void quit();

signals:
    void busyChanged();
    void finishedChanged();
    void progressChanged();
    void stageChanged();
    void logChanged();
    void errorChanged();

private:
    void loadGroups();
    QString markerPath() const;
    void markDone();
    void handleLine(const QByteArray &line);
    void handleFinished(int exitCode, QProcess::ExitStatus status);
    void setBusy(bool busy);

    QVariantList m_groups;
    QProcess m_process;
    QByteArray m_buffer;
    bool m_busy = false;
    bool m_finished = false;
    bool m_sawDone = false;
    double m_progress = 0;
    QString m_stage;
    QString m_log;
    QString m_error;
};
