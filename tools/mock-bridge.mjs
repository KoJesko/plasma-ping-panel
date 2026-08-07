#!/usr/bin/env node
/*
 * Writes a fake pings.json so the widget can be tested without Discord running.
 * Also drains commands/ and prints what the widget sent, which is the quickest
 * way to verify that x / d / a actually reach the bridge.
 *
 *   node tools/mock-bridge.mjs          # write fixtures, then watch commands
 *   node tools/mock-bridge.mjs --once   # write fixtures and exit
 *   node tools/mock-bridge.mjs --clear  # write an empty list
 */
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const DIR = path.join(os.homedir(), ".local", "share", "discord-pings");
const STATE = path.join(DIR, "pings.json");
const CMDS = path.join(DIR, "commands");

const now = Date.now();
const ago = (m) => now - m * 60_000;

const FIXTURES = [
    { kind: "dm",       min: 4,   author: "alex",   guild: null,          channel: "Direct Message", text: "hey, are you around later?" },
    { kind: "direct",   min: 12,  author: "sam",    guild: "Work",        channel: "#backend",       text: "@you can you take a look at the migration?" },
    { kind: "reply",    min: 26,  author: "jordan", guild: "Work",        channel: "#backend",       text: "yeah that fixed it, thanks" },
    { kind: "role",     min: 55,  author: "mod",    guild: "Big Server",  channel: "#general",       text: "@devs standup in 5" },
    { kind: "keyword",  min: 90,  author: "ci",     guild: "Work",        channel: "#builds",        text: "deploy to prod finished" },
    { kind: "everyone", min: 140, author: "raider", guild: "Big Server",  channel: "#announce",      text: "@everyone raid night tonight" },
];

const clear = process.argv.includes("--clear");

const pings = clear ? [] : FIXTURES.map((f, i) => ({
    id: String(900000000000000000 + i),
    channelId: String(700000000000000000 + i),
    guildId: f.guild ? String(800000000000000000 + i) : null,
    guildName: f.guild || "Direct Messages",
    channelName: f.channel,
    authorId: String(600000000000000000 + i),
    authorName: f.author,
    avatarUrl: "",
    content: f.text,
    timestamp: ago(f.min),
    kind: f.kind,
    read: i === 2,
}));

fs.mkdirSync(CMDS, { recursive: true });
fs.writeFileSync(STATE, JSON.stringify({
    version: 1, updatedAt: now, bridgeUp: true,
    self: { id: "1", name: "you" }, pings,
}));
console.log(`wrote ${pings.length} fake ping(s) to ${STATE}`);

if (process.argv.includes("--once") || clear) process.exit(0);

console.log(`watching ${CMDS} — press keys in the widget (Ctrl-C to stop)\n`);
setInterval(() => {
    for (const f of fs.readdirSync(CMDS)) {
        if (!f.endsWith(".json")) continue;
        const full = path.join(CMDS, f);
        try {
            console.log("  <-", fs.readFileSync(full, "utf8"));
            fs.unlinkSync(full);
        } catch { /* mid-write; catch it next tick */ }
    }
}, 500);
