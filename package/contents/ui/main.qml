pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "PingModel.js" as PingModel

PlasmoidItem {
    id: root

    // ------------------------------------------------------------------ state
    property var allPings: []          // everything the bridge knows about
    property var visiblePings: []      // after filters + sort, what we render
    property bool bridgeUp: false
    property string bridgeError: ""
    property double lastUpdate: 0
    property double now: Date.now()
    property string selfName: ""
    property int unread: PingModel.unreadCount(visiblePings)

    readonly property string bridgeDir: Plasmoid.configuration.bridgeDir || "$HOME/.local/share/discord-pings"

    // Rebuilt whenever data or any filter changes.
    function rebuild() {
        const cfg = {
            showDMs: Plasmoid.configuration.showDMs,
            showDirect: Plasmoid.configuration.showDirect,
            showReplies: Plasmoid.configuration.showReplies,
            showRoles: Plasmoid.configuration.showRoles,
            showEveryone: Plasmoid.configuration.showEveryone,
            showKeywords: Plasmoid.configuration.showKeywords,
            mutedGuilds: Plasmoid.configuration.mutedGuilds,
            maxItems: Plasmoid.configuration.maxItems
        };
        visiblePings = PingModel.buildList(allPings, cfg, now);
    }

    // ------------------------------------------------------------- plasma glue
    switchWidth: Kirigami.Units.gridUnit * 16
    switchHeight: Kirigami.Units.gridUnit * 16
    preferredRepresentation: compactRepresentation

    Plasmoid.status: {
        if (!bridgeUp) return PlasmaCore.Types.PassiveStatus;
        if (unread > 0) return PlasmaCore.Types.ActiveStatus;
        if (Plasmoid.configuration.hideWhenEmpty && visiblePings.length === 0)
            return PlasmaCore.Types.HiddenStatus;
        return PlasmaCore.Types.PassiveStatus;
    }

    toolTipMainText: i18n("Discord Pings")
    toolTipSubText: {
        if (bridgeError) return bridgeError;
        if (!bridgeUp) return i18n("Bridge offline — is Discord running with the PingBridge plugin enabled?");
        if (visiblePings.length === 0) return i18n("No pings");
        return i18n("%1 ping(s), %2 unread", visiblePings.length, unread);
    }

    // `applet: root` is bound here, in main.qml's scope, because a QML id is
    // not visible inside the representation's own file.
    compactRepresentation: CompactRepresentation { applet: root }
    fullRepresentation: FullRepresentation { applet: root }

    /** Re-stamp the clock the relative-time labels read from. */
    function tick() { now = Date.now(); }

    // ------------------------------------------------------------------- shell
    // Plasma has no file-read QML API, so we shell out. Commands are wrapped in
    // `sh -c` specifically so $HOME in the configured path expands.
    Plasma5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
            if (source === root.readCommand) root.applyState(data["stdout"] || "");
        }
        function exec(cmd) {
            connectSource(cmd);
        }
    }

    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    readonly property string readCommand:
        "sh -c " + shQuote('cat -- "' + bridgeDir + '/pings.json" 2>/dev/null')

    function reload() {
        now = Date.now();
        shell.exec(readCommand);
    }

    function applyState(text) {
        const state = PingModel.parseState(text);
        bridgeUp = state.bridgeUp;
        bridgeError = state.error;
        lastUpdate = state.updatedAt;
        selfName = state.self ? state.self.name : "";

        const previousIds = allPings.map(p => p.id);
        allPings = state.pings;
        rebuild();

        if (Plasmoid.configuration.notifyNew && previousIds.length > 0) {
            const fresh = visiblePings.filter(p => !p.read && previousIds.indexOf(p.id) === -1);
            if (fresh.length > 0) notifier.notify(fresh);
        }
    }

    // ---------------------------------------------------------------- commands
    // Each command is a JSON file the bridge picks up, executes, and deletes.
    // Written to .tmp then moved so the bridge never reads a partial file.
    property int commandSeq: 0
    function sendCommand(obj) {
        commandSeq += 1;
        const name = Date.now() + "-" + commandSeq + ".json";
        const dir = bridgeDir + "/commands";
        const payload = JSON.stringify(obj);
        const script =
            'mkdir -p "' + dir + '" && ' +
            'printf %s ' + shQuote(payload) + ' > "' + dir + '/.' + name + '" && ' +
            'mv -- "' + dir + '/.' + name + '" "' + dir + '/' + name + '"';
        shell.exec("sh -c " + shQuote(script));
    }

    function openPing(ping) {
        if (!ping) return;
        const url = PingModel.deepLink(ping, Plasmoid.configuration.openTarget);
        shell.exec("xdg-open " + shQuote(url));
        if (Plasmoid.configuration.markReadOnOpen) markRead(ping);
        if (Plasmoid.configuration.dismissOnOpen) dismiss(ping);
        root.expanded = false;
    }

    function markRead(ping) {
        if (!ping) return;
        // Optimistic local update so the UI reacts instantly; the bridge
        // confirms it on the next poll.
        for (let i = 0; i < allPings.length; i++) {
            if (allPings[i].id === ping.id) allPings[i].read = true;
        }
        rebuild();
        sendCommand({ op: "ack", messageId: ping.id, channelId: ping.channelId });
    }

    function dismiss(ping) {
        if (!ping) return;
        allPings = allPings.filter(p => p.id !== ping.id);
        rebuild();
        sendCommand({ op: "dismiss", messageId: ping.id, channelId: ping.channelId });
    }

    function markAllRead() {
        for (let i = 0; i < allPings.length; i++) allPings[i].read = true;
        rebuild();
        sendCommand({ op: "ackAll" });
    }

    function refreshFromDiscord() {
        sendCommand({ op: "refresh" });
        reloadTimer.restart();
    }

    // ------------------------------------------------------------------ timers
    Timer {
        id: reloadTimer
        interval: Math.max(1, Plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.reload()
    }

    // Keeps the "3m ago" labels honest without re-reading the file.
    Timer {
        interval: 30000
        running: root.expanded
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Notifier { id: notifier; applet: root }

    // ------------------------------------------------------------ config hooks
    Connections {
        target: Plasmoid.configuration
        function onShowDMsChanged() { root.rebuild(); }
        function onShowDirectChanged() { root.rebuild(); }
        function onShowRepliesChanged() { root.rebuild(); }
        function onShowRolesChanged() { root.rebuild(); }
        function onShowEveryoneChanged() { root.rebuild(); }
        function onShowKeywordsChanged() { root.rebuild(); }
        function onMutedGuildsChanged() { root.rebuild(); }
        function onMaxItemsChanged() { root.rebuild(); }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Mark all as read")
            icon.name: "mail-mark-read"
            enabled: root.unread > 0
            onTriggered: root.markAllRead()
        },
        PlasmaCore.Action {
            text: i18n("Refresh from Discord")
            icon.name: "view-refresh"
            onTriggered: root.refreshFromDiscord()
        }
    ]

    Component.onCompleted: {
        // Set the default shortcut exactly once, so a rebind in the config
        // dialog isn't clobbered on every login.
        // Plasma 6 persists KConfigPropertyMap writes itself — there is no
        // writeConfig() on it, so assignment alone is the whole operation.
        if (!Plasmoid.configuration.shortcutInitialized) {
            Plasmoid.globalShortcut = "Meta+Shift+D";
            Plasmoid.configuration.shortcutInitialized = true;
        }
        reload();
    }
}
