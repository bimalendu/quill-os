#include "backend.h"

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#include <unistd.h>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("quill-setup"));
    app.setOrganizationName(QStringLiteral("quill-os"));
    app.setDesktopFileName(QStringLiteral("quill-setup"));

    QCommandLineParser parser;
    parser.addHelpOption();
    QCommandLineOption autostart(QStringLiteral("autostart"),
                                 QStringLiteral("Started at login: exit quietly if setup is already done."));
    QCommandLineOption screenshot(QStringLiteral("screenshot"),
                                  QStringLiteral("Save a screenshot of the window to FILE and exit (testing)."),
                                  QStringLiteral("FILE"));
    QCommandLineOption preselect(QStringLiteral("preselect"),
                                 QStringLiteral("Comma separated group ids to tick (testing)."),
                                 QStringLiteral("IDS"));
    QCommandLineOption autoinstall(QStringLiteral("autoinstall"),
                                   QStringLiteral("Install the preselected groups right after start (testing)."));
    parser.addOptions({autostart, screenshot, preselect, autoinstall});
    parser.process(app);

    // Use the Plasma-integrated style when available; Basic otherwise (headless tests).
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    Backend backend;
    // At login, show the screen once, and only to a regular user: Plasma's own
    // first-boot session runs as a system user, before the account exists.
    if (parser.isSet(autostart) && (backend.alreadyDone() || getuid() < 1000))
        return 0;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("preselectedIds"),
                                             parser.value(preselect).split(QLatin1Char(','), Qt::SkipEmptyParts));
    engine.loadFromModule("QuillSetup", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;

    if (parser.isSet(autoinstall)) {
        const QStringList ids = parser.value(preselect).split(QLatin1Char(','), Qt::SkipEmptyParts);
        QTimer::singleShot(300, &app, [&backend, ids] { backend.install(ids); });
    }

    if (parser.isSet(screenshot)) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        const QString path = parser.value(screenshot);
        QTimer::singleShot(qEnvironmentVariableIntValue("QUILL_SETUP_SHOT_DELAY_MS") > 0
                               ? qEnvironmentVariableIntValue("QUILL_SETUP_SHOT_DELAY_MS") : 1500,
                           &app, [window, path] {
            const bool ok = window && window->grabWindow().save(path);
            QCoreApplication::exit(ok ? 0 : 3);
        });
    }
    return app.exec();
}
