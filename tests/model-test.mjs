#!/usr/bin/env node
/*
 * Exercises PingModel.js outside Plasma so you can tune scorePing() without
 * restarting plasmashell. Run:  node tests/model-test.mjs
 *
 * PingModel.js is a QML .js library (`.pragma library`, no module.exports), so
 * we strip the pragma and evaluate it in a VM context to get at its functions.
 */
import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const SRC = new URL("../package/contents/ui/PingModel.js", import.meta.url);
const code = fs.readFileSync(SRC, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = vm.createContext({});
vm.runInContext(code, M);

// --- fixtures ---------------------------------------------------------------
const NOW = 1_700_000_000_000;
const min = (n) => NOW - n * 60_000;

const PINGS = [
    { id: "106", kind: "everyone", timestamp: min(2),    read: false, authorName: "raidbot",  guildName: "Big Server",  channelName: "#announce", content: "@everyone event starting" },
    { id: "105", kind: "role",     timestamp: min(9),    read: false, authorName: "mod",      guildName: "Big Server",  channelName: "#general",  content: "@devs standup" },
    { id: "104", kind: "direct",   timestamp: min(35),   read: false, authorName: "sam",      guildName: "Work",        channelName: "#backend",  content: "@you can you look at this" },
    { id: "103", kind: "dm",       timestamp: min(70),   read: false, authorName: "alex",     guildName: "Direct Messages", channelName: "Direct Message", content: "hey, free tonight?" },
    { id: "102", kind: "reply",    timestamp: min(120),  read: true,  authorName: "jordan",   guildName: "Work",        channelName: "#backend",  content: "yeah that works" },
    { id: "101", kind: "keyword",  timestamp: min(300),  read: false, authorName: "ci",       guildName: "Work",        channelName: "#builds",   content: "deploy finished" },
];

const ALL_ON = {
    showDMs: true, showDirect: true, showReplies: true, showRoles: true,
    showEveryone: true, showKeywords: true, mutedGuilds: "", maxItems: 50,
};

// --- assertions -------------------------------------------------------------
let failures = 0;
function check(name, fn) {
    try { fn(); console.log(`  ok   ${name}`); }
    catch (e) { failures++; console.log(`  FAIL ${name}\n       ${e.message}`); }
}

console.log("\nfilters");
check("everything on keeps all pings", () => {
    assert.equal(M.buildList(PINGS, ALL_ON, NOW).length, PINGS.length);
});
check("showEveryone:false drops @everyone", () => {
    const out = M.buildList(PINGS, { ...ALL_ON, showEveryone: false }, NOW);
    assert.ok(!out.some(p => p.kind === "everyone"));
    assert.equal(out.length, PINGS.length - 1);
});
check("showDMs:false drops DMs", () => {
    const out = M.buildList(PINGS, { ...ALL_ON, showDMs: false }, NOW);
    assert.ok(!out.some(p => p.kind === "dm"));
});
check("maxItems caps the list", () => {
    assert.equal(M.buildList(PINGS, { ...ALL_ON, maxItems: 3 }, NOW).length, 3);
});
check("mutedGuilds filters by guild id", () => {
    const withGuild = PINGS.map(p => ({ ...p, guildId: p.guildName === "Work" ? "G_WORK" : "G_OTHER" }));
    const out = M.buildList(withGuild, { ...ALL_ON, mutedGuilds: "G_WORK" }, NOW);
    assert.ok(!out.some(p => p.guildId === "G_WORK"));
});

console.log("\nsort stability");
check("ordering is deterministic across runs", () => {
    const a = M.buildList(PINGS, ALL_ON, NOW).map(p => p.id).join(",");
    const b = M.buildList([...PINGS].reverse(), ALL_ON, NOW).map(p => p.id).join(",");
    assert.equal(a, b, `input order changed the result:\n  ${a}\n  ${b}`);
});

console.log("\nhelpers");
check("relativeTime", () => {
    assert.equal(M.relativeTime(min(3), NOW), "3m");
    assert.equal(M.relativeTime(min(150), NOW), "2h");
});
check("deepLink builds a guild url", () => {
    assert.equal(
        M.deepLink({ guildId: "1", channelId: "2", id: "3" }, "app"),
        "discord://-/channels/1/2/3");
});
check("deepLink uses @me for DMs", () => {
    assert.equal(
        M.deepLink({ guildId: null, channelId: "2", id: "3" }, "app"),
        "discord://-/channels/@me/2/3");
});

// --- the part you actually care about ---------------------------------------
console.log("\ncurrent ordering from scorePing():\n");
const ordered = M.buildList(PINGS, ALL_ON, NOW);
const pad = (s, n) => String(s).padEnd(n);
console.log("  " + pad("#", 3) + pad("kind", 10) + pad("age", 6) + pad("from", 10) + pad("read", 6) + "score");
for (let i = 0; i < ordered.length; i++) {
    const p = ordered[i];
    console.log("  " + pad(i + 1, 3) + pad(p.kind, 10)
        + pad(M.relativeTime(p.timestamp, NOW), 6)
        + pad(p.authorName, 10) + pad(p.read ? "yes" : "no", 6)
        + M.scorePing(p, NOW));
}

console.log(failures ? `\n${failures} check(s) failed\n` : "\nall checks passed\n");
process.exit(failures ? 1 : 0);
