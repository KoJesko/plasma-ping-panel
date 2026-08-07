import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_showDirect: showDirect.checked
    property alias cfg_showDMs: showDMs.checked
    property alias cfg_showReplies: showReplies.checked
    property alias cfg_showRoles: showRoles.checked
    property alias cfg_showEveryone: showEveryone.checked
    property alias cfg_showKeywords: showKeywords.checked
    property alias cfg_mutedGuilds: mutedGuilds.text

    QQC2.CheckBox {
        id: showDirect
        Kirigami.FormData.label: i18n("Include:")
        text: i18n("Direct @mentions")
    }
    QQC2.CheckBox {
        id: showDMs
        text: i18n("DMs and group DMs")
    }
    QQC2.CheckBox {
        id: showReplies
        text: i18n("Replies to your messages")
    }
    QQC2.CheckBox {
        id: showRoles
        text: i18n("@role pings")
    }
    QQC2.CheckBox {
        id: showEveryone
        text: i18n("@everyone and @here")
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("On busy servers @everyone will bury everything else. Off by default.")
    }
    QQC2.CheckBox {
        id: showKeywords
        text: i18n("Keyword matches")
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Keywords themselves are configured in the PingBridge plugin's settings inside Discord, since that's what decides which messages get captured at all.")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.TextField {
        id: mutedGuilds
        Kirigami.FormData.label: i18n("Muted server IDs:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        placeholderText: i18n("comma-separated")
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Pings from these servers never appear. Enable Developer Mode in Discord, then right-click a server → Copy Server ID.")
    }
}
