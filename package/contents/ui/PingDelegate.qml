import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "PingModel.js" as PingModel

PlasmaComponents.ItemDelegate {
    id: delegate

    required property var ping
    // Named `position`, not `index`: ListView injects an `index` property into
    // delegates, and a same-named property here would shadow/conflict with it.
    required property int position
    // Passed down rather than read off the applet, so the "3m ago" labels all
    // tick from one clock instead of each delegate calling Date.now().
    required property double now
    property bool selected: false

    signal activated()
    signal readRequested()
    signal dismissRequested()

    readonly property var meta: PingModel.kindMeta(ping.kind)

    highlighted: selected
    hoverEnabled: true
    onClicked: delegate.activated()

    implicitHeight: layout.implicitHeight + Kirigami.Units.smallSpacing * 2

    contentItem: RowLayout {
        id: layout
        spacing: Kirigami.Units.smallSpacing

        // Unread marker — a thin accent bar reads better than a dot at this size.
        Rectangle {
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 2
            radius: 1.5
            color: Kirigami.Theme.highlightColor
            opacity: delegate.ping.read ? 0 : 1
        }

        // Position number, so "press 3" is discoverable rather than folklore.
        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit
            visible: delegate.position < 9
            text: delegate.position + 1
            font: Kirigami.Theme.smallFont
            opacity: 0.45
            horizontalAlignment: Text.AlignHCenter
        }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            visible: Plasmoid.configuration.showAvatars
            source: delegate.ping.avatarUrl || delegate.meta.icon
            fallback: delegate.meta.icon
            roundToIconSize: false
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    Layout.maximumWidth: delegate.width * 0.4
                    // PlainText on everything that comes from a message: the
                    // default AutoText renders anything that looks like HTML as
                    // rich text, so a ping containing <img src="https://…">
                    // would make the panel fetch a URL chosen by the sender.
                    textFormat: Text.PlainText
                    text: delegate.ping.authorName
                    font.weight: delegate.ping.read ? Font.Normal : Font.DemiBold
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: delegate.meta.label
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: PingModel.relativeTime(delegate.ping.timestamp, delegate.now)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: delegate.ping.content || i18n("(no text)")
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                opacity: 0.85
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: delegate.ping.guildId
                    ? delegate.ping.guildName + " · " + delegate.ping.channelName
                    : delegate.ping.channelName
                font: Kirigami.Theme.smallFont
                opacity: 0.55
                elide: Text.ElideRight
            }
        }

        // Hover actions, so the widget is usable with the mouse too.
        PlasmaComponents.ToolButton {
            icon.name: "mail-mark-read"
            visible: delegate.hovered && !delegate.ping.read
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Mark as read")
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            onClicked: delegate.readRequested()
        }
        PlasmaComponents.ToolButton {
            icon.name: "window-close"
            visible: delegate.hovered
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Dismiss")
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            onClicked: delegate.dismissRequested()
        }
    }
}
