# Shared helpers for install.sh and dpings. Sourced, never executed.
#
# Everything here is $HOME-relative and discovers its own paths, so the repo can
# be cloned anywhere on any machine and both scripts still work.

APPLET_ID="com.github.kojesko.pingpanel"
# IDs this widget has shipped under before, kept only so upgrades can clean them
# up. The ID doubles as the install directory, so a leftover copy shows up as a
# second entry in the widget list.
#   org.kde.plasma.discordpings      pre-1.0: org.kde is reserved for KDE's own
#   com.github.kojesko.discordpings  1.0.0 dev: named after Discord's trademark
LEGACY_APPLET_IDS=(
  "org.kde.plasma.discordpings"
  "com.github.kojesko.discordpings"
)

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# Deliberately NOT renamed alongside the widget. This is a private data path,
# not user-facing branding, and moving it would orphan everyone's ping history
# for no benefit.
BRIDGE_DIR="$DATA_HOME/discord-pings"
PLASMOID_DIR="$DATA_HOME/plasma/plasmoids/$APPLET_ID"
BRIDGE_SRC_REL="package/contents/bridge/PingBridge.plugin.js"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# Print every BetterDiscord plugins directory that exists, most conventional
# first. Prints nothing (and returns 1) when BetterDiscord is absent.
#
# Delegates to the copy of setup.sh inside the package, which is the same code
# the widget runs. Keeping one implementation matters because a store install
# has *only* that copy — if this list drifted, the widget and these scripts
# would disagree about where BetterDiscord lives.
bd_plugin_dirs() {
  local out
  out="$("${REPO:?}/package/contents/bridge/setup.sh" dirs)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
}

# Every discord_desktop_core directory, oldest app version first.
#
# betterdiscordctl hardcodes `discord_desktop_core-1`; Discord has shipped -2
# since 1.0.152 and will eventually ship -3, so the suffix is globbed. Stable,
# PTB, Canary and Flatpak all keep the same layout under different roots.
discord_core_dirs() {
  local root
  for root in "$HOME/.config/discord" \
              "$HOME/.config/discordptb" \
              "$HOME/.config/discordcanary" \
              "$HOME/.var/app/com.discordapp.Discord/config/discord"; do
    [[ -d "$root" ]] || continue
    ls -d "$root"/app-*/modules/discord_desktop_core-*/discord_desktop_core 2>/dev/null || true
  done | sort -V
}
