#!/usr/bin/env bash
# Build the distributable archive for store.kde.org.
#
# Two things Plasma is strict about, both of which fail only at install time —
# long after upload — so they are checked here instead:
#
#   1. metadata.json must be at the archive ROOT, not inside a containing
#      directory. An extra top-level folder is the most common reason a store
#      upload lands as "invalid package".
#   2. KPackage picks its reader from the FILE EXTENSION, not the contents.
#      `.tar.gz` must be a gzipped tar; `.plasmoid` must be a ZIP. A gzipped
#      tar named `.plasmoid` is rejected with "Could not open package file"
#      even though the bytes are perfectly good. We ship .tar.gz because that
#      is what tar produces and what the store already carries.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bin/common.sh
source "$REPO/bin/common.sh"

command -v jq >/dev/null 2>&1 \
  && VERSION="$(jq -r '.KPlugin.Version' "$REPO/package/metadata.json")" \
  || VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO/package/metadata.json")"
[[ -n "$VERSION" ]] || die "could not read Version from package/metadata.json"

OUT_DIR="$REPO/dist"
OUT="$OUT_DIR/discordpings-$VERSION.tar.gz"
mkdir -p "$OUT_DIR"
rm -f "$OUT"

say "Packaging $APPLET_ID $VERSION"

# --- sanity checks before anyone downloads this -------------------------------
[[ -f "$REPO/$BRIDGE_SRC_REL" ]] \
  || die "$BRIDGE_SRC_REL missing — a store install would have no bridge to offer"
grep -q "\"Id\": \"$APPLET_ID\"" "$REPO/package/metadata.json" \
  || die "metadata.json Id does not match $APPLET_ID"
grep -q '"Id": "org\.kde\.' "$REPO/package/metadata.json" \
  && die "the org.kde namespace is reserved for KDE's own widgets; do not publish under it"

# The bridge is JavaScript that Discord executes; a syntax error ships silently
# because BetterDiscord reports load failures only inside its own settings UI.
if command -v node >/dev/null 2>&1; then
  node --check "$REPO/$BRIDGE_SRC_REL" >/dev/null || die "bridge plugin has a syntax error"
  say "Running test suites"
  node "$REPO/tests/model-test.mjs"  >/dev/null || die "model tests failed"
  node "$REPO/tests/bridge-test.mjs" >/dev/null || die "bridge tests failed"
else
  warn "node not found; skipping syntax check and tests"
fi

# --- build --------------------------------------------------------------------
# -C package . so metadata.json lands at the archive root.
# --exclude-vcs and the sort keep the output byte-stable across rebuilds.
tar czf "$OUT" \
  --exclude-vcs \
  --exclude='*.swp' \
  --exclude='.DS_Store' \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  -C "$REPO/package" .

# --- verify -------------------------------------------------------------------
tar tzf "$OUT" | grep -qx './metadata.json' \
  || die "metadata.json is not at the archive root — Plasma will reject this"

if command -v kpackagetool6 >/dev/null 2>&1; then
  # --install into a throwaway prefix proves Plasma accepts the archive without
  # touching the real install.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  if kpackagetool6 --type Plasma/Applet --install "$OUT" --packageroot "$TMP" >/dev/null 2>&1; then
    say "kpackagetool6 accepts the archive"
  else
    die "kpackagetool6 refused the archive"
  fi
fi

printf '\n'
say "Built $OUT ($(du -h "$OUT" | cut -f1))"
cat <<EOF

Upload it at https://store.kde.org  ->  Add Product
  Category: Plasma 6 Add-Ons -> Plasma 6 Applets
  Version:  $VERSION
See docs/PUBLISHING.md for the rest.
EOF
