import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root

    title: qsTr("Quill Setup")
    width: Kirigami.Units.gridUnit * 38
    height: Kirigami.Units.gridUnit * 36
    minimumWidth: Kirigami.Units.gridUnit * 28
    minimumHeight: Kirigami.Units.gridUnit * 26
    visible: true

    // The group ids the user has ticked. Nothing is ticked by default.
    property var chosen: preselectedIds.slice()
    readonly property bool working: backend.busy
    readonly property bool failed: backend.error.length > 0 && !backend.busy
    readonly property bool showStatus: backend.busy || backend.finished || failed

    function toggle(id) {
        const i = chosen.indexOf(id)
        const next = chosen.slice()
        if (i >= 0)
            next.splice(i, 1)
        else
            next.push(id)
        chosen = next
    }

    pageStack.initialPage: Kirigami.Page {
        title: root.title
        padding: Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "quill-logo-icon"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Kirigami.Heading {
                        level: 1
                        text: qsTr("Welcome to Quill OS")
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: qsTr("Choose extra software to install now. You can run Quill Setup again later from the application menu.")
                        wrapMode: Text.WordWrap
                        opacity: 0.75
                        Layout.fillWidth: true
                    }
                }
            }

            QQC2.ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.showStatus
                contentWidth: availableWidth

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: backend.groups
                        delegate: Kirigami.AbstractCard {
                            required property var modelData
                            Layout.fillWidth: true
                            showClickFeedback: true
                            onClicked: root.toggle(modelData.id)

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing
                                QQC2.CheckBox {
                                    checked: root.chosen.indexOf(modelData.id) >= 0
                                    onToggled: root.toggle(modelData.id)
                                    Accessible.name: modelData.name
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Label {
                                        text: modelData.name
                                        font.bold: true
                                        Layout.fillWidth: true
                                    }
                                    QQC2.Label {
                                        text: modelData.description
                                        wrapMode: Text.WordWrap
                                        opacity: 0.75
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Progress, result and details, shown once an install has started.
            ColumnLayout {
                visible: root.showStatus
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                // A plain themed bar: the same on every Qt Quick style, so progress is
                // always visible whatever style the session uses.
                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
                    visible: backend.busy
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: qsTr("Installation progress")

                    Rectangle {
                        width: track.width * Math.max(0.03, Math.min(1, backend.progress))
                        height: parent.height
                        radius: parent.radius
                        color: Kirigami.Theme.highlightColor
                        Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration } }
                    }
                }
                QQC2.Label {
                    text: root.failed ? qsTr("Something went wrong") : backend.stage
                    font.bold: true
                    Layout.fillWidth: true
                }
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.failed
                    type: Kirigami.MessageType.Error
                    text: backend.error
                }
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: backend.finished
                    type: Kirigami.MessageType.Positive
                    text: qsTr("The selected software is installed. You can find it in the application menu.")
                }
                QQC2.Button {
                    id: detailsButton
                    checkable: true
                    text: checked ? qsTr("Hide details") : qsTr("Show details")
                }
                QQC2.ScrollView {
                    visible: detailsButton.checked
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    QQC2.TextArea {
                        readOnly: true
                        text: backend.log
                        wrapMode: TextEdit.NoWrap
                        font.family: "monospace"
                    }
                }
                Item {
                    Layout.fillHeight: true
                    visible: !detailsButton.checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    visible: !root.showStatus
                    text: root.chosen.length === 0
                          ? qsTr("Nothing selected")
                          : root.chosen.length === 1
                            ? qsTr("1 group selected")
                            : qsTr("%1 groups selected").arg(root.chosen.length)
                    opacity: 0.75
                }
                Item { Layout.fillWidth: true }

                QQC2.Button {
                    text: qsTr("Skip for now")
                    visible: !backend.finished
                    enabled: !backend.busy
                    onClicked: backend.skip()
                }
                QQC2.Button {
                    text: root.failed ? qsTr("Try again") : qsTr("Install selected")
                    icon.name: "run-install"
                    visible: !backend.finished
                    enabled: root.chosen.length > 0 && !backend.busy
                    highlighted: true
                    onClicked: backend.install(root.chosen)
                }
                QQC2.Button {
                    text: qsTr("Close")
                    visible: backend.finished
                    highlighted: true
                    onClicked: backend.quit()
                }
            }
        }
    }
}
