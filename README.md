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

## Requirements

- **Plasma 6** (Wayland or X11)
- **Discord desktop app** with **[BetterDiscord](https://betterdiscord.app)**

Discord has no plugin API and no read-only "give me my mentions" endpoint for
normal accounts, so reading your pings means running code inside the client.
BetterDiscord is how that's done without a bot.

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
client already makes when you open the Inbox.

**There is no account token anywhere in this project**, and nothing logs in on
its own. That is deliberate: driving the Discord API with a user token is the
classic self-bot pattern and the thing accounts actually get banned for.

Consequence: pings are captured while Discord is running. The list persists
across restarts (it's a file), and `r` backfills recent mentions from the Inbox
when the client comes back.

## Install

### From the KDE Store (easiest)

Right-click your panel → **Add Widgets** → **Get New Widgets** → **Download New
Plasma Widgets** → search *Discord Pings* → Install. Then add it to the panel.

The store only ships the widget, so the first time you open it, it will offer an
**Install bridge plugin** button — that copies the bundled `PingBridge` into
BetterDiscord for you. After that:

> Discord → Settings → BetterDiscord → Plugins → enable **PingBridge**

### From a release file

Download `discordpings-<version>.tar.gz` from
[Releases](https://github.com/KoJesko/plasma-discord-pings/releases), then:

```bash
kpackagetool6 --type Plasma/Applet --install discordpings-1.0.0.tar.gz
```

Same first-run flow as the store — press **Install bridge plugin** in the popup.

### From source

```bash
git clone https://github.com/KoJesko/plasma-discord-pings
cd plasma-discord-pings
./install.sh              # or ./install.sh --link to develop against the repo
```

This installs the applet, copies the bridge into BetterDiscord, and links the
`dpings` helper into `~/.local/bin`. Nothing is hardcoded to a clone location —
put the repo wherever you like.

Then:

1. Discord → Settings → BetterDiscord → Plugins → enable **PingBridge**
2. Right-click the panel → Add Widgets → **Discord Pings**
3. Press `Meta+Shift+D`

`./install.sh --uninstall` reverses all of it and leaves your ping history alone.

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

`install.sh` links `bin/dpings` into `~/.local/bin`. It resolves the repo from
its own path, so it works from any directory and survives the repo being moved
(set `DPINGS_REPO` to override).

| Command | Does |
|---------|------|
| `dpings doctor` | check every part of the install and say what's broken |
| `dpings status` | bridge up/down, ping count, breakdown by kind |
| `dpings clear` | empty the list — **run this before enabling PingBridge for real**, or leftover fixtures persist into your real pings |
| `dpings mock` | write fake pings to test the UI with Discord closed |
| `dpings watch` | fake pings + print every command the widget sends (verifies `x` / `d` / `a` land) |
| `dpings sync` | push repo edits to the bridge into BetterDiscord |
| `dpings inject` | re-inject BetterDiscord after a Discord update |
| `dpings sort` | print the current `scorePing()` ordering |
| `dpings test` | run both test suites |
| `dpings reload` | restart plasmashell to pick up QML changes |
| `dpings edit` | open `PingModel.js` in `$EDITOR` |
| `dpings package` | build the store archive |

`dpings doctor` walks the chain in dependency order — applet, BetterDiscord,
injection, bridge state, URL handler — so the **first** FAIL is the real cause.

## Layout

```
package/                             everything the KDE Store ships
  metadata.json                      applet id, version, license
  contents/bridge/
    PingBridge.plugin.js             capture + ack + backfill, writes the state file
    setup.sh                         finds BetterDiscord, installs the plugin
  contents/ui/
    main.qml                         state, polling, commands, bridge setup
    CompactRepresentation.qml        panel icon + unread badge
    FullRepresentation.qml           popup, search, all keyboard handling
    PingDelegate.qml                 one row
    PingModel.js                     filter / sort / format  ← scorePing lives here
    Config*.qml                      settings pages
bin/dpings, bin/common.sh            helper CLI
tools/package.sh                     builds the store archive
tools/mock-bridge.mjs                fake bridge for UI testing
tests/*.mjs                          model + bridge test suites
docs/PUBLISHING.md                   how to cut a release
```

The bridge lives **inside** `package/` on purpose: a KDE Store install delivers
that directory and nothing else, so anything outside it may as well not exist
for most users.

## Why this isn't on the BetterDiscord plugin store

The bridge isn't a Discord plugin in any useful sense — on its own it writes a
JSON file nobody reads. It's one half of a widget, and the two halves share a
state-file format that changes together. Listing it separately would let people
install a version of the plugin that doesn't match their widget, which is a
support problem with no upside.

It ships inside the widget package instead, and the widget installs it. If you
want the plugin by itself, take
[`package/contents/bridge/PingBridge.plugin.js`](package/contents/bridge/PingBridge.plugin.js)
and drop it in your plugins folder.

## Troubleshooting

Start with `dpings doctor`. Beyond that:

**Icon is dimmed / "Bridge offline"** — Discord isn't running, or PingBridge is
disabled. The widget dims rather than showing an empty list so a dead bridge
doesn't look like "no pings".

**"Bridge error"** — PingBridge couldn't resolve a Discord internal module
(Discord changed its internals). The specific module names are in the message
and in Discord's console (`Ctrl+Shift+I`).

**`Enter` doesn't jump to the message** — check `xdg-mime query default
x-scheme-handler/discord` returns `discord.desktop`.

**The widget vanished after upgrading to 1.0.0** — the applet ID changed (see
below). Re-add it: right-click the panel → Add Widgets → Discord Pings.

### The applet ID changed in 1.0.0

Before 1.0.0 this used `org.kde.plasma.discordpings`. That namespace is reserved
for widgets shipped by KDE itself, and the ID doubles as the install directory,
so publishing under it would collide with KDE's own packages. It's now
`com.github.kojesko.discordpings`.

`install.sh` removes the old copy automatically. Because Plasma tracks panel
contents by ID, your old panel instance disappears with it and has to be
re-added once. Settings and shortcut are re-applied on first run.

### When Discord updates and BetterDiscord disappears

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

### BetterDiscord's require() is not Node's

`betterdiscord.js` implements `require` as a switch over a fixed list:

```
request  https  original-fs  fs  path  events
electron  process  vm  module  buffer  crypto
```

Anything else falls through to its file loader, which resolves the name as a
path relative to the plugins folder. So `require("os")` becomes
`realpathSync("~/.config/BetterDiscord/plugins/os")` and throws
`ENOENT: no such file or directory, lstat` — **at load time**, which BD reports
only as the generic "An error was encountered while trying to load this plugin",
with no stack in the console or `debug.log`.

There is no `os`, so use `process.env.HOME` rather than `os.homedir()`.
`tests/bridge-test.mjs` asserts this; run `dpings test` after touching imports.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
