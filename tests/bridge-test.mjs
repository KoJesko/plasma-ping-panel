#!/usr/bin/env node
/*
 * Tests PingBridge's capture logic against a stubbed Discord. The plugin only
 * touches BdApi/Webpack at start(), so we can stub those and drive
 * classifyPing / toRecord / drainCommands directly.
 *
 *   node tests/bridge-test.mjs
 */
import { createRequire } from "node:module";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";

const ME = "111";
const GUILD = "G1";
const MY_ROLES = ["R_DEV"];

// --- stub Discord -----------------------------------------------------------
const channels = {
    C_TEXT: { id: "C_TEXT", type: 0, name: "general", guild_id: GUILD },
    C_DM:   { id: "C_DM",   type: 1 },
    C_GDM:  { id: "C_GDM",  type: 3, name: "the group" },
};

const noopLogger = { info() {}, warn() {}, error() {} };
globalThis.BdApi = {
    Logger: noopLogger,
    Data: { load: () => ({}), save() {} },
    UI: { showToast() {}, buildSettingsPanel: () => ({}) },
    Webpack: {
        getStore: (name) => ({
            UserStore: { getCurrentUser: () => ({ id: ME, username: "me", global_name: "Me" }) },
            ChannelStore: { getChannel: (id) => channels[id] },
            GuildStore: { getGuild: (id) => ({ id, name: "My Server" }) },
            GuildMemberStore: { getSelfMember: () => ({ roles: MY_ROLES }) },
        }[name]),
        getModule: () => ({ dispatch() {}, subscribe() {}, unsubscribe() {}, _actionHandlers: {} }),
        getByKeys: () => ({ get: async () => ({ body: [] }), post: async () => ({}), del: async () => ({}) }),
    },
};

const require = createRequire(import.meta.url);
const PingBridge = require("../package/contents/bridge/PingBridge.plugin.js");

const bridge = new PingBridge({ name: "PingBridge" });
bridge.modules = {
    Dispatcher: BdApi.Webpack.getModule(),
    UserStore: BdApi.Webpack.getStore("UserStore"),
    ChannelStore: BdApi.Webpack.getStore("ChannelStore"),
    GuildStore: BdApi.Webpack.getStore("GuildStore"),
    GuildMemberStore: BdApi.Webpack.getStore("GuildMemberStore"),
    HTTP: BdApi.Webpack.getByKeys(),
};
bridge.settings = { keywords: "deploy, incident", captureEveryone: true, backfillOnStart: false };

const msg = (over = {}) => ({
    id: "M1", channel_id: "C_TEXT", guild_id: GUILD,
    author: { id: "222", username: "sam", global_name: "Sam", avatar: "abc", discriminator: "0" },
    content: "hello", timestamp: new Date(0).toISOString(),
    mentions: [], mention_roles: [], mention_everyone: false, ...over,
});
const classify = (over) => {
    const m = msg(over);
    return bridge.classifyPing(m, channels[m.channel_id]);
};

let failures = 0;
const check = (name, fn) => {
    try { fn(); console.log(`  ok   ${name}`); }
    catch (e) { failures++; console.log(`  FAIL ${name}\n       ${e.message}`); }
};

/*
 * BetterDiscord's require() is a switch over a fixed module list, not Node's
 * resolver. An unlisted name is resolved as a FILE relative to the plugins
 * folder, so it throws "ENOENT ... lstat" at load time and BD reports only its
 * generic "error was encountered while trying to load this plugin". require("os")
 * cost hours to that exact trap, so it is asserted rather than remembered.
 * List extracted from betterdiscord.js (the Fd require shim).
 */
const BD_MODULES = new Set([
    "request", "https", "original-fs", "fs", "path", "events",
    "electron", "process", "vm", "module", "buffer", "crypto",
]);

/** Strip comments so the scan sees code only — the file documents this trap in prose. */
function codeOf(relative) {
    return fs.readFileSync(new URL(relative, import.meta.url), "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, " ")
        .replace(/^\s*\/\/.*$/gm, " ");
}

console.log("\nbetterdiscord require compatibility");
check("only requires modules BetterDiscord's shim supports", () => {
    const src = codeOf("../package/contents/bridge/PingBridge.plugin.js");
    const used = new Set();
    for (const m of src.matchAll(/\brequire\(\s*["']([^"']+)["']\s*\)/g)) used.add(m[1]);
    const bad = [...used].filter(n => !n.startsWith("./") && !BD_MODULES.has(n));
    assert.deepEqual(bad, [],
        `unsupported require(): ${bad.join(", ")} — BD resolves these as file paths and throws ENOENT at load`);
});
check("does not call os.homedir (no os module in BD)", () => {
    assert.equal(/\bos\s*\.\s*homedir\s*\(/.exec(codeOf("../package/contents/bridge/PingBridge.plugin.js")), null,
        "os.homedir() is unavailable; use process.env.HOME");
});

console.log("\nclassification");
check("plain channel chatter is not a ping", () => assert.equal(classify(), null));
check("own message is never a ping", () =>
    assert.equal(classify({ author: { id: ME }, mentions: [{ id: ME }] }), null));
check("ephemeral message is ignored", () =>
    assert.equal(classify({ flags: 64, mentions: [{ id: ME }] }), null));
check("direct @mention", () =>
    assert.equal(classify({ mentions: [{ id: ME }] }), "direct"));
check("DM channel is always a ping", () =>
    assert.equal(classify({ channel_id: "C_DM" }), "dm"));
check("group DM is a ping", () =>
    assert.equal(classify({ channel_id: "C_GDM" }), "dm"));
check("reply to me outranks plain mention", () =>
    assert.equal(classify({ mentions: [{ id: ME }], referenced_message: { author: { id: ME } } }), "reply"));
check("reply without mention still counts", () =>
    assert.equal(classify({ referenced_message: { author: { id: ME } } }), "reply"));
check("role I hold pings me", () =>
    assert.equal(classify({ mention_roles: ["R_DEV"] }), "role"));
check("role I do NOT hold does not", () =>
    assert.equal(classify({ mention_roles: ["R_OTHER"] }), null));
check("@everyone", () =>
    assert.equal(classify({ mention_everyone: true }), "everyone"));
check("@everyone suppressed when captureEveryone is off", () => {
    bridge.settings.captureEveryone = false;
    const r = classify({ mention_everyone: true });
    bridge.settings.captureEveryone = true;
    assert.equal(r, null);
});
check("keyword match", () =>
    assert.equal(classify({ content: "the DEPLOY is done" }), "keyword"));
check("keyword matching is case-insensitive and trimmed", () =>
    assert.equal(classify({ content: "big Incident tonight" }), "keyword"));

console.log("\nrecord shape");
check("guild message names its guild and channel", () => {
    const m = msg({ mentions: [{ id: ME }] });
    const r = bridge.toRecord(m, channels.C_TEXT, "direct");
    assert.equal(r.guildName, "My Server");
    assert.equal(r.channelName, "#general");
    assert.equal(r.authorName, "Sam");
    assert.match(r.avatarUrl, /cdn\.discordapp\.com\/avatars\/222\/abc\.png/);
});
check("DM record has no guild", () => {
    const r = bridge.toRecord(msg({ channel_id: "C_DM", guild_id: undefined }), channels.C_DM, "dm");
    assert.equal(r.guildId, null);
    assert.equal(r.channelName, "Direct Message");
});
check("mentions are rendered as @name in the preview", () => {
    const m = msg({ content: "hey <@111> look", mentions: [{ id: "111", global_name: "Me" }] });
    assert.equal(bridge.plainText(m), "hey @Me look");
});
check("custom emoji collapse to :name:", () =>
    assert.equal(bridge.plainText(msg({ content: "nice <:kek:12345>" })), "nice :kek:"));
check("attachment-only message gets a placeholder", () =>
    assert.equal(bridge.plainText(msg({ content: "", attachments: [{}, {}] })), "[2 attachment(s)]"));
check("animated avatars use .gif", () => {
    const r = bridge.toRecord(msg({ author: { id: "9", avatar: "a_xyz", username: "g" } }), channels.C_TEXT, "direct");
    assert.match(r.avatarUrl, /a_xyz\.gif/);
});
check("missing avatar falls back to a default", () => {
    const r = bridge.toRecord(msg({ author: { id: "80351110224678912", username: "n", discriminator: "0" } }), channels.C_TEXT, "direct");
    assert.match(r.avatarUrl, /embed\/avatars\/[0-5]\.png/);
});

console.log("\ndedupe + cap");
check("re-adding the same id does not duplicate", () => {
    bridge.pings = [];
    const r = bridge.toRecord(msg({ mentions: [{ id: ME }] }), channels.C_TEXT, "direct");
    bridge.addPing(r);
    bridge.addPing(r);
    assert.equal(bridge.pings.length, 1);
});

console.log("\ncommand handling");
check("a command file is read, executed, and deleted", () => {
    const dir = path.join(os.homedir(), ".local", "share", "discord-pings", "commands");
    fs.mkdirSync(dir, { recursive: true });
    bridge.pings = [{ id: "M9", channelId: "C_TEXT", read: false }];
    const f = path.join(dir, "test-drain.json");
    fs.writeFileSync(f, JSON.stringify({ op: "ack", messageId: "M9", channelId: "C_TEXT" }));
    bridge.drainCommands();
    assert.equal(fs.existsSync(f), false, "command file should be consumed");
    assert.equal(bridge.pings[0].read, true, "ack should mark the ping read");
});
check("dismiss removes the ping", () => {
    bridge.pings = [{ id: "M9", channelId: "C_TEXT", read: false }];
    bridge.execute({ op: "dismiss", messageId: "M9" });
    assert.equal(bridge.pings.length, 0);
});
check("malformed json does not throw", () => {
    const dir = path.join(os.homedir(), ".local", "share", "discord-pings", "commands");
    const f = path.join(dir, "bad.json");
    fs.writeFileSync(f, "{ not json");
    bridge.drainCommands();
    fs.rmSync(f, { force: true });
});

console.log("\nsecurity");
check("ack/dismiss never put a non-snowflake ID into an API path", () => {
    const urls = [];
    const saved = bridge.modules.HTTP;
    bridge.modules.HTTP = {
        post: async (r) => { urls.push(r.url); },
        del: async (r) => { urls.push(r.url); },
    };
    try {
        bridge.ack("../../guilds/1", "2");
        bridge.ack("1", "2/../../../users/@me");
        bridge.removeFromInbox("../../relationships/1");
        assert.deepEqual(urls, [], `unexpected requests: ${urls.join(", ")}`);
        bridge.ack("123", "456");
        bridge.removeFromInbox("456");
        assert.deepEqual(urls, ["/channels/123/messages/456/ack", "/users/@me/mentions/456"]);
    } finally {
        bridge.modules.HTTP = saved;
    }
});
check("state file and its directory are private to the user", () => {
    bridge.writeState({ version: 1, pings: [] });
    const dir = path.join(os.homedir(), ".local", "share", "discord-pings");
    assert.equal(fs.statSync(dir).mode & 0o777, 0o700, "data dir should be 0700");
    assert.equal(fs.statSync(path.join(dir, "pings.json")).mode & 0o777, 0o600, "pings.json should be 0600");
});

console.log(failures ? `\n${failures} check(s) failed\n` : "\nall checks passed\n");
process.exit(failures ? 1 : 0);
