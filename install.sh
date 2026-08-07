#!/usr/bin/env bash
# Install both halves of Ping Panel: the Plasma applet and the BetterDiscord
# bridge plugin. Safe to re-run.
#
#   ./install.sh            normal install
#   ./install.sh --link     develop against the repo (applet is symlinked)
#   ./install.sh --uninstall
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/common.sh
source "$REPO/bin/common.sh"

LINK=0
UNINSTALL=0
case "${1:-}" in
  --link)      LINK=1 ;;
  --uninstall) UNINSTALL=1 ;;
  "")          ;;
  *)           die "unknown option '$1' (expected --link or --uninstall)" ;;
esac

restart_plasmashell() {
  if command -v kquitapp6 >/dev/null 2>&1 && pgrep -x plasmashell >/dev/null; then
    say "Restarting plasmashell"
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    sleep 2
    (setsid plasmashell >/dev/null 2>&1 &)
  else
    warn "plasmashell not running; skipping restart"
  fi
}

# --- uninstall ---------------------------------------------------------------
if (( UNINSTALL )); then
  say "Removing applet"
  rm -rf "$PLASMOID_DIR"
  kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID" >/dev/null 2>&1 || true
  while read -r bd; do
    rm -f "$bd/PingBridge.plugin.js" && say "Removed $bd/PingBridge.plugin.js"
  done < <(bd_plugin_dirs || true)
  rm -f "$HOME/.local/bin/dpings"
  restart_plasmashell
  cat <<EOF

Uninstalled. Your ping history is left alone at:
  $BRIDGE_DIR
Delete it yourself if you want it gone.
EOF
  exit 0
fi

# --- migrate installs made under an older ID ---------------------------------
# The ID *is* the install directory, so an old copy left behind shows up as a
# second, broken entry in the widget list. See LEGACY_APPLET_IDS in common.sh
# for why each one changed.
for legacy in "${LEGACY_APPLET_IDS[@]}"; do
  LEGACY_DIR="$DATA_HOME/plasma/plasmoids/$legacy"
  # -e follows symlinks, so it is FALSE for a dangling one. A --link install
  # whose repo has since moved leaves exactly that, and testing -e alone would
  # silently skip it — hence -L as well.
  [[ -e "$LEGACY_DIR" || -L "$LEGACY_DIR" ]] || continue
  say "Removing older install ($legacy)"
  rm -rf "$LEGACY_DIR"
  kpackagetool6 --type Plasma/Applet --remove "$legacy" >/dev/null 2>&1 || true
  MIGRATED=1
done

# --- plasma applet -----------------------------------------------------------
command -v kpackagetool6 >/dev/null 2>&1 || die "kpackagetool6 not found — this needs Plasma 6."

if (( LINK )); then
  say "Linking applet into $PLASMOID_DIR"
  mkdir -p "$(dirname "$PLASMOID_DIR")"
  rm -rf "$PLASMOID_DIR"
  ln -sfn "$REPO/package" "$PLASMOID_DIR"
elif kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
  say "Upgrading applet $APPLET_ID"
  kpackagetool6 --type Plasma/Applet --upgrade "$REPO/package"
else
  say "Installing applet $APPLET_ID"
  kpackagetool6 --type Plasma/Applet --install "$REPO/package"
fi

# --- helper command ----------------------------------------------------------
# Always a symlink: dpings resolves the repo from its own path at runtime, so a
# link keeps working even if the repo moves.
BIN_DIR="$HOME/.local/bin"
say "Linking dpings into $BIN_DIR"
mkdir -p "$BIN_DIR"
ln -sfn "$REPO/bin/dpings" "$BIN_DIR/dpings"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on PATH; add it to use \`dpings\`" ;;
esac

# --- bridge plugin -----------------------------------------------------------
# Missing BetterDiscord is not fatal. The applet is useful to install now and
# the widget itself can install the bridge later, once BetterDiscord exists.
mkdir -p "$BRIDGE_DIR/commands"
BD_FOUND=0
while read -r bd; do
  # Always a real copy, never a symlink even under --link: BetterDiscord's
  # addon scanner does not reliably pick up symlinked plugin files. Use
  # `dpings sync` to push repo edits across.
  install -m 0644 "$REPO/$BRIDGE_SRC_REL" "$bd/PingBridge.plugin.js"
  say "Installed PingBridge into $bd"
  BD_FOUND=1
done < <(bd_plugin_dirs || true)

restart_plasmashell

# --- what's left to do -------------------------------------------------------
echo
if (( BD_FOUND )); then
  cat <<EOF
Done.

  1. Discord -> Settings -> BetterDiscord -> Plugins -> enable "PingBridge"
  2. Right-click your panel -> Add Widgets -> "Ping Panel"
  3. Press Meta+Shift+D
EOF
else
  cat <<EOF
Applet installed. BetterDiscord was not found, so the bridge was skipped.

  1. Install BetterDiscord:  https://betterdiscord.app
  2. Re-run ./install.sh (or press "Install bridge plugin" in the widget)
  3. Discord -> Settings -> BetterDiscord -> Plugins -> enable "PingBridge"
  4. Right-click your panel -> Add Widgets -> "Ping Panel"
EOF
fi

if [[ -n "${MIGRATED:-}" ]]; then
  echo
  warn "The widget ID changed in 1.0.0, so your old panel instance is gone."
  warn "Re-add it: right-click the panel -> Add Widgets -> Ping Panel."
fi

echo
echo "Bridge state lives in: $BRIDGE_DIR/pings.json"
echo "Run \`dpings doctor\` if anything looks wrong."
