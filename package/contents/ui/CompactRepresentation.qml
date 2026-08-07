import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    // ids don't cross QML files, so main.qml hands us the PlasmoidItem here.
    required property var applet

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int badge: applet ? applet.unread : 0

    Layout.minimumWidth: vertical ? 0 : Kirigami.Units.iconSizes.small
    Layout.minimumHeight: vertical ? Kirigami.Units.iconSizes.small : 0

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) compact.applet.markAllRead();
        else compact.applet.expanded = !compact.applet.expanded;
    }

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: "ping-panel"
        active: compact.containsMouse
        // Dim when the bridge isn't reporting, so a dead bridge looks different
        // from "you have no pings".
        opacity: compact.applet && compact.applet.bridgeUp ? 1.0 : 0.45
    }

    Rectangle {
        id: badgeRect
        visible: Plasmoid.configuration.showBadge && compact.badge > 0
        // Kept inside the icon's bounds: overhanging looks fine mid-panel but
        // gets clipped by the panel edge when the widget is the last item.
        anchors {
            right: icon.right
            bottom: icon.bottom
        }
        // Size flows label -> rect only. Deriving the font size from the rect's
        // height as well would close the loop: rect.implicitHeight ->
        // label.implicitHeight -> label.font.pixelSize -> rect.height.
        implicitWidth: Math.max(implicitHeight, badgeLabel.implicitWidth + Kirigami.Units.smallSpacing)
        implicitHeight: Math.round(badgeLabel.implicitHeight + 2)
        radius: height / 2
        color: Kirigami.Theme.negativeTextColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)

        PlasmaComponents.Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: compact.badge > 99 ? "99+" : compact.badge
            color: "white"
            // Pinned to Kirigami units, not to badgeRect, to keep sizing acyclic.
            font.pixelSize: Math.max(8, Math.round(Kirigami.Units.iconSizes.small * 0.55))
            font.weight: Font.Bold
        }
    }
}
