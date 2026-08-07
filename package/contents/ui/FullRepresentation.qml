pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: rep

    // ids don't cross QML files, so main.qml hands us the PlasmoidItem here.
    required property var applet

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    collapseMarginsHint: true
    focus: true

    property string filterText: ""

    // Local search on top of the already-filtered/sorted list from the applet.
    readonly property var items: {
        const source = applet ? applet.visiblePings : [];
        if (!filterText) return source;
        const needle = filterText.toLowerCase();
        return source.filter(p =>
            String(p.authorName).toLowerCase().indexOf(needle) !== -1
            || String(p.guildName).toLowerCase().indexOf(needle) !== -1
            || String(p.channelName).toLowerCase().indexOf(needle) !== -1
            || String(p.content).toLowerCase().indexOf(needle) !== -1);
    }

    function currentPing() {
        return list.currentIndex >= 0 && list.currentIndex < items.length
            ? items[list.currentIndex] : null;
    }

    // ------------------------------------------------------------------ actions
    function openCurrent() { const p = currentPing(); if (p) applet.openPing(p); }
    function readCurrent() { const p = currentPing(); if (p) applet.markRead(p); }
    function dismissCurrent() {
        const p = currentPing();
        if (!p) return;
        const wasAt = list.currentIndex;
        applet.dismiss(p);
        // items shrinks as a side effect, so clamp rather than keep the index.
        list.currentIndex = Math.min(wasAt, rep.items.length - 1);
    }
    function jumpTo(n) {
        if (n < 0 || n >= items.length) return;
        list.currentIndex = n;
        openCurrent();
    }

    // ------------------------------------------------------------------- header
    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Search pings…  (/ to focus)")
                text: rep.filterText
                onTextEdited: {
                    rep.filterText = text;
                    list.currentIndex = rep.items.length > 0 ? 0 : -1;
                }
                // The list owns the vim keys; only these three are ours.
                Keys.onEscapePressed: {
                    if (text.length > 0) { text = ""; rep.filterText = ""; }
                    list.forceActiveFocus();
                }
                Keys.onReturnPressed: { list.forceActiveFocus(); rep.openCurrent(); }
                Keys.onDownPressed: list.forceActiveFocus();
            }

            PlasmaComponents.ToolButton {
                icon.name: "mail-mark-read"
                enabled: rep.applet && rep.applet.unread > 0
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Mark all as read (a)")
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                onClicked: rep.applet.markAllRead()
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Refresh (r)")
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                onClicked: rep.applet.refreshFromDiscord()
            }
        }
    }

    // --------------------------------------------------------------------- list
    PlasmaComponents.ScrollView {
        anchors.fill: parent
        focus: true

        ListView {
            id: list
            focus: true
            model: rep.items
            currentIndex: 0
            highlightMoveDuration: Kirigami.Units.shortDuration
            keyNavigationEnabled: true

            // modelData/index are injected by ListView because they're declared
            // required here; ComponentBehavior: Bound makes that mandatory.
            delegate: PingDelegate {
                required property var modelData
                required property int index

                width: list.width
                ping: modelData
                position: index
                now: rep.applet ? rep.applet.now : 0
                selected: ListView.isCurrentItem
                onActivated: { list.currentIndex = index; rep.openCurrent(); }
                onReadRequested: { list.currentIndex = index; rep.readCurrent(); }
                onDismissRequested: { list.currentIndex = index; rep.dismissCurrent(); }
            }

            // ---------------------------------------------------------- keyboard
            Keys.onPressed: function (event) {
                switch (event.key) {
                case Qt.Key_J:
                    list.incrementCurrentIndex(); event.accepted = true; break;
                case Qt.Key_K:
                    list.decrementCurrentIndex(); event.accepted = true; break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    rep.openCurrent(); event.accepted = true; break;
                case Qt.Key_X:
                    rep.readCurrent(); event.accepted = true; break;
                case Qt.Key_D:
                case Qt.Key_Delete:
                    rep.dismissCurrent(); event.accepted = true; break;
                case Qt.Key_A:
                    rep.applet.markAllRead(); event.accepted = true; break;
                case Qt.Key_R:
                    rep.applet.refreshFromDiscord(); event.accepted = true; break;
                case Qt.Key_G:
                    // g = top, Shift+G = bottom, as in vim/less.
                    list.currentIndex = (event.modifiers & Qt.ShiftModifier)
                        ? rep.items.length - 1 : 0;
                    event.accepted = true; break;
                case Qt.Key_Slash:
                    searchField.forceActiveFocus();
                    searchField.selectAll();
                    event.accepted = true; break;
                case Qt.Key_Escape:
                    if (rep.filterText.length > 0) {
                        rep.filterText = "";
                        searchField.text = "";
                    } else {
                        rep.applet.expanded = false;
                    }
                    event.accepted = true; break;
                default:
                    // 1-9 jump straight to the Nth ping and open it.
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        rep.jumpTo(event.key - Qt.Key_1);
                        event.accepted = true;
                    }
                }
            }

            /*
             * Empty-list state. This is the entire first-run experience for
             * anyone who installed from the KDE Store — they have the widget
             * and nothing else — so it has to name the next concrete step at
             * every stage, not just say "offline".
             *
             * `phase` is evaluated once and the three visual properties read
             * it, so the message, icon and button can never disagree.
             */
            PlasmaExtras.PlaceholderMessage {
                id: placeholder
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: list.count === 0

                readonly property string phase: {
                    if (!rep.applet) return "offline";
                    if (rep.applet.setupError) return "setup-failed";
                    if (rep.applet.bridgeError) return "error";
                    if (rep.applet.bridgeSetup === "no-betterdiscord") return "no-betterdiscord";
                    if (rep.applet.bridgeSetup === "not-installed") return "not-installed";
                    // An outdated plugin still works, so only raise it when
                    // nothing else is happening — otherwise it would mask the
                    // more useful "Discord isn't running" message.
                    if (rep.applet.bridgeSetup === "outdated" && !rep.applet.bridgeUp) return "outdated";
                    if (!rep.applet.bridgeUp) return "offline";
                    return rep.filterText ? "no-matches" : "empty";
                }

                iconName: {
                    switch (phase) {
                    case "setup-failed":
                    case "error": return "dialog-error";
                    case "no-betterdiscord":
                    case "not-installed":
                    case "outdated": return "install";
                    case "offline": return "network-disconnect";
                    case "no-matches": return "edit-find";
                    default: return "mail-mark-read";
                    }
                }

                text: {
                    switch (phase) {
                    case "setup-failed": return i18n("Setup failed");
                    case "error": return i18n("Bridge error");
                    case "no-betterdiscord": return i18n("BetterDiscord is required");
                    case "not-installed": return i18n("Bridge plugin not installed");
                    case "outdated": return i18n("Bridge plugin is out of date");
                    case "offline": return i18n("Bridge offline");
                    case "no-matches": return i18n("No matches");
                    default: return i18n("No pings");
                    }
                }

                explanation: {
                    switch (phase) {
                    case "setup-failed": return rep.applet.setupError;
                    case "error": return rep.applet.bridgeError;
                    case "no-betterdiscord":
                        return i18n("Discord has no plugin API, so this widget reads your mentions through BetterDiscord. Install it, then reopen this popup.");
                    case "not-installed":
                        return i18n("BetterDiscord was found. Install the bridge plugin, then enable “PingBridge” in Discord → Settings → BetterDiscord → Plugins.");
                    case "outdated":
                        return i18n("The copy in BetterDiscord is older than the one shipped with this widget.");
                    case "offline":
                        return i18n("Start Discord and enable the PingBridge plugin in BetterDiscord's settings.");
                    case "no-matches": return i18n("Nothing matches “%1”.", rep.filterText);
                    default: return i18n("You're all caught up.");
                    }
                }

                helpfulAction: Kirigami.Action {
                    visible: placeholder.phase === "no-betterdiscord"
                        || placeholder.phase === "not-installed"
                        || placeholder.phase === "outdated"
                        || placeholder.phase === "setup-failed"
                    icon.name: placeholder.phase === "no-betterdiscord" ? "internet-services" : "install"
                    text: {
                        switch (placeholder.phase) {
                        case "no-betterdiscord": return i18n("Get BetterDiscord");
                        case "outdated": return i18n("Update bridge plugin");
                        case "setup-failed": return i18n("Try again");
                        default: return i18n("Install bridge plugin");
                        }
                    }
                    onTriggered: {
                        if (placeholder.phase === "no-betterdiscord") rep.applet.openUrl("https://betterdiscord.app");
                        else rep.applet.installBridge();
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------- footer
    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaComponents.ToolBar.Footer
        RowLayout {
            anchors.fill: parent
            PlasmaComponents.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("j/k move · Enter open · x read · d dismiss · 1-9 jump · / search")
            }
        }
    }

    // Grab focus each time the popup opens, or the first j goes nowhere.
    Connections {
        target: rep.applet
        function onExpandedChanged() {
            if (!rep.applet.expanded) return;
            rep.filterText = "";
            searchField.text = "";
            list.currentIndex = rep.items.length > 0 ? 0 : -1;
            list.forceActiveFocus();
            rep.applet.tick();
        }
    }

    Component.onCompleted: list.forceActiveFocus()
}
