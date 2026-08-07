# Publishing a release

Two places: **GitHub** (source + the release archive) and the **KDE Store**
(what "Get New Widgets" searches). The KDE Store upload has to be done by hand
in a browser — it needs your account, and there is no CLI for it.

Deliberately **not** published: the BetterDiscord plugin store. The bridge and
the widget share a state-file format and are versioned together; see the README
for why splitting them would only create broken installs.

## 1. Bump the version

Two files, and they must match — the widget compares them to decide whether the
bridge in BetterDiscord is out of date:

- `package/metadata.json` → `KPlugin.Version`
- `package/contents/bridge/PingBridge.plugin.js` → the `@version` header line

Semantic versioning; the KDE Store sorts updates by it.

## 2. Build

```bash
dpings package        # or ./tools/package.sh
```

That runs both test suites, syntax-checks the bridge, refuses to build if the
applet ID is back in the `org.kde` namespace, and writes
`dist/discordpings-<version>.tar.gz`.

It then does a throwaway `kpackagetool6 --install` into a temp prefix. If that
step passes, Plasma will accept the archive — which is the failure the store
otherwise surfaces only as "invalid package" *after* someone downloads it.

Install it locally once before shipping:

```bash
kpackagetool6 --type Plasma/Applet --install dist/discordpings-1.0.0.tar.gz
```

Test it as a **store user would**: no `install.sh`, no `dpings`. Remove the
bridge from BetterDiscord first (`rm ~/.config/BetterDiscord/plugins/PingBridge.plugin.js`),
open the popup, and confirm the **Install bridge plugin** button appears and
works. That path is the entire first-run experience for most people and it is
the easiest one to break, because nothing in the dev setup exercises it.

## 3. GitHub release

```bash
git tag -a v1.0.0 -m "Discord Pings 1.0.0"
git push origin main --tags
gh release create v1.0.0 dist/discordpings-1.0.0.tar.gz \
  --title "Discord Pings 1.0.0" \
  --notes "..."
```

Attaching the archive matters: it's the install route for anyone who doesn't
want to go through the store.

> **Don't rename it to `.plasmoid`.** KPackage picks its reader from the file
> extension, not the contents: `.tar.gz` must be a gzipped tar and `.plasmoid`
> must be a ZIP. A tarball named `.plasmoid` fails with "Could not open package
> file" despite being a perfectly valid archive.

## 4. KDE Store

<https://store.kde.org> — the storefront for [Pling](https://www.pling.com);
one account covers both. Sign in with your KDE Identity / OpenDesktop account.

**First upload** — *Add Product*:

| Field | Value |
|---|---|
| Category | **Plasma 6 Add-Ons → Plasma 6 Applets** (id 706) |
| Title | Discord Pings |
| Version | matches `metadata.json` |
| License | GPL-3.0-or-later |
| Homepage | `https://github.com/KoJesko/plasma-discord-pings` |
| File | `dist/discordpings-<version>.tar.gz` |

Category matters more than it looks: "Get New Widgets" inside Plasma queries
specific category IDs, so a widget filed under a Plasma **5** category is
invisible to Plasma 6 users even though the store page works fine. You can
change it later yourself via *Edit* on the product page.

At least one **screenshot** is required for the listing to look like anything.
Good set:

1. The popup open over a panel, with a few pings visible
2. The compact panel icon with its unread badge
3. The settings dialog's Filters page

```bash
spectacle -b -n -f -o ~/Pictures/discordpings-1.png
```

Description: paste the README's intro plus the Keys table. Say **BetterDiscord
is required** in the first two lines — someone installing from inside Plasma has
no idea this needs a second piece, and "it doesn't work" reviews come from
exactly that gap.

**Updates** — *Edit* the existing product, add a new file, bump Version. Don't
create a second product; Plasma matches updates by product, so a new entry
orphans everyone who already installed it.

## 5. After publishing

Confirm the round trip from a user's side: Add Widgets → Get New Widgets →
search *Discord Pings* → Install. It can take a few minutes to appear.

If it installs but doesn't show up in the widget list, the archive almost
certainly has a directory at its root instead of `metadata.json` — `package.sh`
checks for this, so only a hand-built tarball should ever hit it.
