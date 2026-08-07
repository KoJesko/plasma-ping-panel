.pragma library

/*
 * Pure logic for turning the bridge's pings.json into the list the widget
 * renders. Deliberately free of QML types so it can be exercised outside
 * Plasma — see tests/model-test.mjs, which strips the pragma above and
 * evaluates this file in a VM context (it's a QML .js library, so it has no
 * module.exports and can't simply be require()d).
 *
 *     node tests/model-test.mjs
 */

/** Display metadata per ping kind. Colour names resolve against Kirigami.Theme. */
var KIND_META = {
    dm:       { label: "DM",        icon: "mail-message",            rank: 0 },
    direct:   { label: "mentioned you", icon: "mail-mark-important", rank: 1 },
    reply:    { label: "replied",   icon: "mail-replied",            rank: 2 },
    keyword:  { label: "keyword",   icon: "edit-find",               rank: 3 },
    role:     { label: "role ping", icon: "system-users",            rank: 4 },
    everyone: { label: "@everyone", icon: "irc-channel-active",      rank: 5 }
};

function kindMeta(kind) {
    return KIND_META[kind] || { label: kind || "ping", icon: "dialog-information", rank: 9 };
}

/** Parse the bridge state file. Never throws; returns a shape the UI can render. */
function parseState(text) {
    if (!text || !text.trim()) {
        return { ok: false, bridgeUp: false, error: "", pings: [], updatedAt: 0, self: null };
    }
    try {
        var raw = JSON.parse(text);
        return {
            ok: true,
            bridgeUp: raw.bridgeUp !== false,
            error: raw.error || "",
            updatedAt: raw.updatedAt || 0,
            self: raw.self || null,
            pings: Array.isArray(raw.pings) ? raw.pings : []
        };
    } catch (e) {
        return { ok: false, bridgeUp: false, error: "Bridge file is not valid JSON: " + e, pings: [], updatedAt: 0, self: null };
    }
}

/* ------------------------------------------------------------- bridge setup
 * The widget can install its own bridge plugin, because a KDE Store install
 * ships nothing but this package — no install.sh, no dpings. It asks
 * contents/bridge/setup.sh what's on disk and gets three lines back; these two
 * functions turn that into a state the popup can switch on.
 */

/** Compare dotted numeric versions. Returns <0 / 0 / >0 like a sort comparator. */
function compareVersions(a, b) {
    var x = String(a || "").split("."), y = String(b || "").split(".");
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
        // parseInt so a "1.0.0-rc1" segment still compares as 0 rather than NaN.
        var d = (parseInt(x[i], 10) || 0) - (parseInt(y[i], 10) || 0);
        if (d !== 0) return d;
    }
    return 0;
}

/**
 * Parse `setup.sh probe`: BetterDiscord dir, installed @version, bundled
 * @version — one per line, any of which may be empty.
 *
 * state is one of:
 *   "no-betterdiscord"  BetterDiscord isn't installed, so there's nowhere to put it
 *   "not-installed"     BetterDiscord is there but has no PingBridge
 *   "outdated"          the copy in BetterDiscord is older than the bundled one
 *   "ok"                installed and current (it may still be disabled in Discord)
 */
function parseProbe(text) {
    var lines = String(text || "").split("\n");
    var r = {
        bdDir: (lines[0] || "").trim(),
        installed: (lines[1] || "").trim(),
        bundled: (lines[2] || "").trim()
    };
    if (!r.bdDir) r.state = "no-betterdiscord";
    else if (!r.installed) r.state = "not-installed";
    // Only *older* counts. A newer installed copy means hand-edits, and
    // clobbering someone's own changes to nag about a version is worse than
    // leaving it be.
    else if (compareVersions(r.installed, r.bundled) < 0) r.state = "outdated";
    else r.state = "ok";
    return r;
}

/** Config-driven visibility. Returns true when this ping should be listed. */
function passesFilters(ping, cfg) {
    if (cfg.mutedGuilds && ping.guildId) {
        var muted = String(cfg.mutedGuilds).split(",").map(function (s) { return s.trim(); });
        if (muted.indexOf(ping.guildId) !== -1) return false;
    }
    switch (ping.kind) {
        case "dm":       return cfg.showDMs;
        case "direct":   return cfg.showDirect;
        case "reply":    return cfg.showReplies;
        case "role":     return cfg.showRoles;
        case "everyone": return cfg.showEveryone;
        case "keyword":  return cfg.showKeywords;
        default:         return true;
    }
}

/* ============================================================================
 * TODO(you): implement the ordering rule.
 *
 * This is the one genuinely opinionated decision in the whole widget, and it's
 * the difference between a list that's useful at a glance and one you have to
 * read top to bottom. Everything else is plumbing.
 *
 * Return a NUMBER — higher sorts first. `buildList` sorts descending on it.
 *
 * Inputs:
 *   ping.kind       "dm" | "direct" | "reply" | "keyword" | "role" | "everyone"
 *   ping.timestamp  epoch ms
 *   ping.read       true once you've acked it (or read it in the client)
 *   ping.guildName  server name, or "Direct Messages"
 *   now             epoch ms, passed in so sorting is deterministic
 *   kindMeta(k).rank  0 = most important (dm) ... 5 = least (@everyone)
 *
 * The trade-off worth thinking about: pure recency (`return ping.timestamp`)
 * is predictable — the list never reorders under you, and position 3 stays
 * position 3 — but a two-minute-old @everyone from a server you ignore will
 * outrank a DM from an hour ago. Pure importance (`return -kindMeta(...).rank`)
 * fixes that but makes the list jump around as things arrive, which is rough
 * when you're navigating it by number key.
 *
 * A middle path is to bucket by importance and sort by time *within* bucket,
 * e.g. `-rank * 1e12 + ping.timestamp`, optionally decaying old pings or
 * sinking already-read ones. Your call — you know your servers.
 *
 * ~5-10 lines. Replace the body below.
 * ==========================================================================*/
function scorePing(ping, now) {
    // Placeholder: strict recency, so the widget is usable before you decide.
    return ping.timestamp || 0;
}

/** Filter + sort + cap. This is what the ListView's model is built from. */
function buildList(pings, cfg, now) {
    var out = [];
    for (var i = 0; i < pings.length; i++) {
        if (passesFilters(pings[i], cfg)) out.push(pings[i]);
    }
    out.sort(function (a, b) {
        var d = scorePing(b, now) - scorePing(a, now);
        // Message IDs are snowflakes, so they break ties in true arrival order.
        return d !== 0 ? d : String(b.id).localeCompare(String(a.id));
    });
    var max = cfg.maxItems > 0 ? cfg.maxItems : 50;
    return out.slice(0, max);
}

function unreadCount(list) {
    var n = 0;
    for (var i = 0; i < list.length; i++) if (!list[i].read) n++;
    return n;
}

/** "3m", "2h", "4d" — compact enough for a narrow popup. */
function relativeTime(ts, now) {
    var s = Math.max(0, Math.floor((now - ts) / 1000));
    if (s < 60) return s + "s";
    var m = Math.floor(s / 60);
    if (m < 60) return m + "m";
    var h = Math.floor(m / 60);
    if (h < 24) return h + "h";
    var d = Math.floor(h / 24);
    if (d < 7) return d + "d";
    return Math.floor(d / 7) + "w";
}

/** discord://-/channels/... navigates the running client to the message. */
function deepLink(ping, target) {
    var guild = ping.guildId || "@me";
    var tail = "channels/" + guild + "/" + ping.channelId + "/" + ping.id;
    return target === "web" ? "https://discord.com/" + tail : "discord://-/" + tail;
}
