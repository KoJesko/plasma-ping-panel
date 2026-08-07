#!/usr/bin/env sh
# Locate BetterDiscord and install the bridge plugin into it.
#
# This lives INSIDE the plasmoid package on purpose. A KDE Store install ships
# nothing but this package — no install.sh, no dpings — so the widget has to be
# able to set up its own bridge, and it shells out to this script to do it.
# bin/common.sh delegates here too, so the list of BetterDiscord locations
# exists exactly once.
#
#   setup.sh dirs      print every BetterDiscord plugins folder that exists
#   setup.sh probe     print the chosen folder (line 1) and the installed
#                      bridge's @version (line 2); both may be empty
#   setup.sh install   copy the sibling PingBridge.plugin.js into that folder
#
# POSIX sh, not bash: it runs from QML with no control over the shell.
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SRC="$HERE/PingBridge.plugin.js"

bd_dirs() {
  for d in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/BetterDiscord/plugins" \
    "$HOME/.config/BetterDiscord/plugins" \
    "$HOME/.var/app/com.discordapp.Discord/config/BetterDiscord/plugins" \
    "$HOME/.var/app/com.discordapp.DiscordCanary/config/BetterDiscord/plugins"
  do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}

# The header BetterDiscord itself parses: ` * @version 1.0.0`
# Always prints exactly one line, empty when the file is missing or unversioned,
# so `probe` can promise a fixed line count.
version_of() {
  v=''
  if [ -f "$1" ]; then
    v="$(sed -n 's/^[[:space:]]*\*[[:space:]]*@version[[:space:]]*//p' "$1" 2>/dev/null | head -n 1)"
  fi
  printf '%s\n' "$v"
}

case "${1:-}" in
  dirs)
    bd_dirs | awk '!seen[$0]++'
    ;;

  probe)
    # Always three lines, so the caller can split on newline without guessing:
    #   1. BetterDiscord plugins folder ("" if BetterDiscord is not installed)
    #   2. @version of the bridge installed there ("" if not installed)
    #   3. @version of the bridge bundled in this package
    dir="$(bd_dirs | head -n 1)"
    printf '%s\n' "$dir"
    version_of "$dir/PingBridge.plugin.js"
    version_of "$SRC"
    ;;

  install)
    [ -f "$SRC" ] || { echo "setup.sh: $SRC missing" >&2; exit 2; }
    n=0
    # A real copy, never a symlink: BetterDiscord's addon scanner does not
    # reliably pick up symlinked plugin files.
    for d in $(bd_dirs | awk '!seen[$0]++'); do
      cp -f -- "$SRC" "$d/PingBridge.plugin.js" || continue
      chmod 0644 "$d/PingBridge.plugin.js" 2>/dev/null || true
      echo "installed -> $d/PingBridge.plugin.js"
      n=$((n + 1))
    done
    [ "$n" -gt 0 ] || { echo "setup.sh: no BetterDiscord plugins folder found" >&2; exit 1; }
    ;;

  *)
    echo "usage: setup.sh {dirs|probe|install}" >&2
    exit 64
    ;;
esac
