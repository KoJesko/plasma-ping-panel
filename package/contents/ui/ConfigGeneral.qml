import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_bridgeDir: bridgeDir.text
    property alias cfg_refreshInterval: refreshInterval.value
    property alias cfg_maxItems: maxItems.value
    property alias cfg_markReadOnOpen: markReadOnOpen.checked
    property alias cfg_dismissOnOpen: dismissOnOpen.checked
    property alias cfg_notifyNew: notifyNew.checked
    property alias cfg_showBadge: showBadge.checked
    property alias cfg_hideWhenEmpty: hideWhenEmpty.checked
    property alias cfg_showAvatars: showAvatars.checked
    property string cfg_openTarget: "app"

    QQC2.TextField {
        id: bridgeDir
        Kirigami.FormData.label: i18n("Bridge directory:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Where the BetterDiscord PingBridge plugin writes pings.json. $HOME is expanded.")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.SpinBox {
        id: refreshInterval
        Kirigami.FormData.label: i18n("Re-read every:")
        from: 1
        to: 120
        textFromValue: (v) => i18np("%1 second", "%1 seconds", v)
        valueFromText: (t) => parseInt(t)
    }
    QQC2.SpinBox {
        id: maxItems
        Kirigami.FormData.label: i18n("Show at most:")
        from: 5
        to: 200
        stepSize: 5
        textFromValue: (v) => i18np("%1 ping", "%1 pings", v)
        valueFromText: (t) => parseInt(t)
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Open pings in:")
        model: [
            { key: "app", label: i18n("Discord app") },
            { key: "web", label: i18n("Browser") }
        ]
        textRole: "label"
        valueRole: "key"
        currentIndex: page.cfg_openTarget === "web" ? 1 : 0
        onActivated: page.cfg_openTarget = currentValue
    }

    QQC2.CheckBox {
        id: markReadOnOpen
        Kirigami.FormData.label: i18n("When opening a ping:")
        text: i18n("Mark it as read")
    }
    QQC2.CheckBox {
        id: dismissOnOpen
        text: i18n("Remove it from the list")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: showBadge
        Kirigami.FormData.label: i18n("Panel icon:")
        text: i18n("Show unread count badge")
    }
    QQC2.CheckBox {
        id: hideWhenEmpty
        text: i18n("Hide the widget when there are no pings")
    }
    QQC2.CheckBox {
        id: showAvatars
        text: i18n("Show avatars in the list")
    }
    QQC2.CheckBox {
        id: notifyNew
        text: i18n("Send a desktop notification for new pings")
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Leave off unless you've muted Discord's own notifications — otherwise you'll get each ping twice.")
    }
}
