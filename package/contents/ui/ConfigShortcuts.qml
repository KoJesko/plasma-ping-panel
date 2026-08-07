import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kquickcontrols as KQuickControls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Kirigami.FormLayout {
    id: page

    // The applet's global shortcut lives on Plasma::Applet, not in our config
    // group, so it's read/written directly rather than through cfg_ bindings.
    KQuickControls.KeySequenceItem {
        Kirigami.FormData.label: i18n("Open pings:")
        keySequence: Plasmoid.globalShortcut
        onCaptureFinished: Plasmoid.globalShortcut = keySequence
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Default is Meta+Shift+D. Avoid Meta+D — Plasma uses it for Show Desktop.")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Inside the popup:")
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.Wrap
        textFormat: Text.RichText
        text: "<table cellpadding='2'>"
            + "<tr><td><b>j</b> / <b>↓</b></td><td>" + i18n("next ping") + "</td></tr>"
            + "<tr><td><b>k</b> / <b>↑</b></td><td>" + i18n("previous ping") + "</td></tr>"
            + "<tr><td><b>Enter</b></td><td>" + i18n("open in Discord") + "</td></tr>"
            + "<tr><td><b>1</b>–<b>9</b></td><td>" + i18n("jump to Nth ping and open") + "</td></tr>"
            + "<tr><td><b>x</b></td><td>" + i18n("mark as read") + "</td></tr>"
            + "<tr><td><b>d</b> / <b>Del</b></td><td>" + i18n("dismiss") + "</td></tr>"
            + "<tr><td><b>a</b></td><td>" + i18n("mark all as read") + "</td></tr>"
            + "<tr><td><b>r</b></td><td>" + i18n("refresh from Discord") + "</td></tr>"
            + "<tr><td><b>g</b> / <b>G</b></td><td>" + i18n("first / last") + "</td></tr>"
            + "<tr><td><b>/</b></td><td>" + i18n("search") + "</td></tr>"
            + "<tr><td><b>Esc</b></td><td>" + i18n("clear search, then close") + "</td></tr>"
            + "</table>"
    }
}
