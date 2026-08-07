# Discord Pings — Plasma 6 widget

Browse your Discord mentions from the panel, by keyboard. `Meta+Shift+D` opens
the list, `j`/`k` moves, `Enter` jumps straight to that message in Discord.

```
┌──────────────────────────────────────────┐
│ Search pings…              [✓ read] [⟳]  │
├──────────────────────────────────────────┤
│ ▎1  alex        DM              4m       │
│    hey, are you around later?            │
│    Direct Message                        │
├──────────────────────────────────────────┤
│ ▎2  sam         mentioned you   12m      │
│    @you can you take a look at…          │
│    Work · #backend                       │
└──────────────────────────────────────────┘
  j/k move · Enter open · x read · d dismiss
```

## How it works

Two halves talking through a file:

```
 Discord (running, BetterDiscord)
   └─ PingBridge.plugin.js
        subscribes to Flux: MESSAGE_CREATE, MESSAGE_ACK
        writes ──► ~/.local/share/discord-pings/pings.json
                                │
                     reads      │      writes commands/*.json
        Plasma widget ──────────┴──────────────► back to the bridge
                                │
                     Meta+Shift+D → popup → Enter → discord://…
```

The bridge reads Discord's **own in-memory stores**, so capturing a ping costs
zero network requests. Backfill and mark-as-read go through Discord's internal
HTTP module, meaning they ride the real client's session — the same requests the
client already makes when you open the Inbox. There is no account token stored
anywhere, and nothing logs in on its own.

Consequence: pings are captured while Discord is running. The list persists
across restarts (it's a file), and `r` backfills recent mentions from the Inbox
when the client comes back.

## Install

```bash
git clone <this repo> ~/GitHub/plasma-discord-pings
cd ~/GitHub/plasma-discord-pings
./install.sh          # or ./install.sh --link to develop against the repo
```

Then:

1. Discord → Settings → BetterDiscord → Plugins → enable **PingBridge**
2. Right-click the panel → Add Widgets → **Discord Pings**
3. Press `Meta+Shift+D`

Requires Plasma 6 and BetterDiscord. `install.sh` finds the BetterDiscord
plugins folder itself (native or Flatpak) and installs the applet with
`kpackagetool6`, so a fresh machine needs nothing but the clone.

## Keys

| Key | Action |
|-----|--------|
| `Meta+Shift+D` | open/close the list (rebindable: widget settings → Shortcuts) |
| `j` / `k`, `↓` / `↑` | next / previous ping |
| `Enter` | open in Discord |
| `1`–`9` | jump to the Nth ping and open it |
| `x` | mark read |
| `d` / `Del` | dismiss |
| `a` | mark all read |
| `r` | backfill from Discord's Inbox |
| `g` / `G` | first / last |
| `/` | search |
| `Esc` | clear search, then close |

Middle-click the panel icon marks everything read without opening anything.

`Meta+D` is deliberately *not* the default — Plasma uses it for Show Desktop.

## Configuring

Widget settings has three pages: **General** (poll interval, open in app vs
browser, badge, notifications), **Filters** (which ping kinds appear, muted
server IDs), **Shortcuts**.

Filters split by kind: direct `@you`, DMs, replies, `@role`, `@everyone`, and
keyword matches. `@everyone` is **off** by default — on a busy server it buries
everything that actually matters.

Keywords themselves are set in the PingBridge plugin's settings inside Discord,
since that's what decides which messages get captured at all. The widget's
keyword toggle only controls whether captured ones are shown.

## Tuning the sort order

`package/contents/ui/PingModel.js` → `scorePing()` decides the list order.
Higher sorts first. It ships as plain recency, which means a two-minute-old
`@everyone` outranks an hour-old DM.

Iterate without restarting plasmashell:

```bash
dpings sort     # just the resulting order
dpings test     # model + bridge test suites
```

## The `dpings` helper

`install.sh` links `bin/dpings` into `~/.local/bin`. It resolves the repo itself,
so it works from any directory (set `DPINGS_REPO` if the repo lives elsewhere).

| Command | Does |
|---------|------|
| `dpings status` | bridge up/down, ping count, breakdown by kind |
| `dpings clear` | empty the list — **run this before enabling PingBridge for real**, or leftover fixtures persist into your real pings |
| `dpings mock` | write fake pings to test the UI with Discord closed |
| `dpings watch` | fake pings + print every command the widget sends (verifies `x` / `d` / `a` land) |
| `dpings sort` | print the current `scorePing()` ordering |
| `dpings test` | run both test suites |
| `dpings reload` | restart plasmashell to pick up QML changes |
| `dpings edit` | open `PingModel.js` in `$EDITOR` |

The underlying scripts are `tools/mock-bridge.mjs` and `tests/*.mjs`; invoking
them with `node` directly only works from the repo root, which is why `dpings`
exists.

## Layout

```
betterdiscord/PingBridge.plugin.js   capture + ack + backfill, writes the state file
package/contents/ui/
  main.qml                           state, polling, commands, actions
  CompactRepresentation.qml          panel icon + unread badge
  FullRepresentation.qml             popup, search, all keyboard handling
  PingDelegate.qml                   one row
  PingModel.js                       filter / sort / format  ← scorePing lives here
  Config*.qml                        settings pages
tests/model-test.mjs                 PingModel checks
tools/mock-bridge.mjs                fake bridge for UI testing
```

## Troubleshooting

**Icon is dimmed / "Bridge offline"** — Discord isn't running, or PingBridge is
disabled. The widget dims rather than showing an empty list so a dead bridge
doesn't look like "no pings".

**"Bridge error"** — PingBridge couldn't resolve a Discord internal module
(Discord changed its internals). The specific module names are in the message
and in Discord's console (`Ctrl+Shift+I`).

**`Enter` doesn't jump to the message** — check `xdg-mime query default
x-scheme-handler/discord` returns `discord.desktop`.

## When Discord updates and BetterDiscord disappears

Discord overwrites `discord_desktop_core/index.js` on every update, which undoes
the BetterDiscord injection — and takes PingBridge with it. Symptom: the widget
dims and says "Bridge offline".

```bash
dpings inject     # then fully quit Discord (tray icon → Quit) and relaunch
```

`betterdiscordctl install` may fail here with:

```
ERROR: Directory 'discord_desktop_core' not found in: ~/.config/discord/app-X/modules
```

That's a bug in `betterdiscordctl`, not a broken Discord install — it hardcodes
`discord_desktop_core-1` while current Discord ships `discord_desktop_core-2`.
`dpings inject` globs the suffix instead, so it keeps working.
