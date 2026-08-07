#!/usr/bin/env bash
# Install both halves of Discord Pings: the BetterDiscord bridge plugin and the
# Plasma applet. Safe to re-run; use --link during development so edits in this
# repo take effect without reinstalling.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APPLET_ID="org.kde.plasma.discordpings"
BRIDGE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/discord-pings"
PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$APPLET_ID"

LINK=0
[[ "${1:-}" == "--link" ]] && LINK=1

say() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- locate BetterDiscord ----------------------------------------------------
# Checked in preference order; the first existing one wins.
BD_CANDIDATES=(
  "$HOME/.config/BetterDiscord/plugins"
  "$HOME/.var/app/com.discordapp.Discord/config/BetterDiscord/plugins"
  "${XDG_CONFIG_HOME:-$HOME/.config}/BetterDiscord/plugins"
)
BD_PLUGINS=""
for candidate in "${BD_CANDIDATES[@]}"; do
  [[ -d "$candidate" ]] && { BD_PLUGINS="$candidate"; break; }
done
[[ -n "$BD_PLUGINS" ]] || die "Could not find a BetterDiscord plugins folder. Install BetterDiscord first."

# --- bridge plugin -----------------------------------------------------------
say "Installing PingBridge into $BD_PLUGINS"
mkdir -p "$BRIDGE_DIR/commands"
if (( LINK )); then
  ln -sfn "$REPO/betterdiscord/PingBridge.plugin.js" "$BD_PLUGINS/PingBridge.plugin.js"
else
  install -m 0644 "$REPO/betterdiscord/PingBridge.plugin.js" "$BD_PLUGINS/PingBridge.plugin.js"
fi

# --- plasma applet -----------------------------------------------------------
if (( LINK )); then
  say "Linking applet into $PLASMOID_DIR"
  mkdir -p "$(dirname "$PLASMOID_DIR")"
  rm -rf "$PLASMOID_DIR"
  ln -sfn "$REPO/package" "$PLASMOID_DIR"
else
  if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
    say "Upgrading applet $APPLET_ID"
    kpackagetool6 --type Plasma/Applet --upgrade "$REPO/package"
  else
    say "Installing applet $APPLET_ID"
    kpackagetool6 --type Plasma/Applet --install "$REPO/package"
  fi
fi

# --- reload ------------------------------------------------------------------
if command -v kquitapp6 >/dev/null 2>&1 && pgrep -x plasmashell >/dev/null; then
  say "Restarting plasmashell"
  kquitapp6 plasmashell >/dev/null 2>&1 || true
  sleep 2
  (setsid plasmashell >/dev/null 2>&1 &)
else
  warn "plasmashell not running; skipping restart"
fi

cat <<EOF

Done.

Next steps:
  1. In Discord: Settings -> BetterDiscord -> Plugins -> enable "PingBridge".
  2. Right-click your panel -> Add Widgets -> "Discord Pings".
  3. Press Meta+Shift+D to open it. Rebind under widget settings -> Shortcuts.

Bridge state lives in: $BRIDGE_DIR/pings.json
EOF
