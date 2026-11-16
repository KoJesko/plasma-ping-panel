import QtQuick
import org.kde.notification

/*
 * Optional desktop notification for pings that appeared since the last poll.
 * Off by default — Discord already notifies; this is for people who run the
 * client with its own notifications suppressed.
 */
Item {
    id: notifier

    required property var applet

    Notification {
        id: note
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "ping-panel"
        flags: Notification.DefaultEvent
        // defaultAction is a NotificationAction object, not a string.
        defaultAction: NotificationAction {
            label: i18n("Open")
            onActivated: notifier.applet.expanded = true
        }
    }

    // The notification server interprets body markup (links, images; the
    // title is plain text per the spec, so it is left alone), and
    // every field here comes from a message someone else wrote. Escape it so a
    // ping is always shown as the literal text that was sent.
    function esc(s) {
        return String(s === undefined || s === null ? "" : s)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function notify(pings) {
        if (!pings || pings.length === 0) return;
        if (pings.length === 1) {
            const p = pings[0];
            note.title = i18n("%1 in %2", p.authorName,
                              p.guildId ? p.guildName : p.channelName);
            note.text = esc(p.content);
        } else {
            note.title = i18n("%1 new Discord pings", pings.length);
            note.text = pings.slice(0, 3)
                .map(p => esc(p.authorName) + ": " + esc(p.content))
                .join("\n");
        }
        note.sendEvent();
    }
}
