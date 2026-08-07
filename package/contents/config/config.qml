import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Filters")
        icon: "view-filter"
        source: "ConfigFilters.qml"
    }
    ConfigCategory {
        name: i18n("Shortcuts")
        icon: "input-keyboard"
        source: "ConfigShortcuts.qml"
    }
}
