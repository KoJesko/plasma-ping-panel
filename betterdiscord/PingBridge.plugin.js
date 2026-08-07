/**
 * @name PingBridge
 * @author kojesko
 * @version 0.1.0
 * @description Mirrors your mentions to ~/.local/share/discord-pings/ so the Plasma "Discord Pings" widget can browse them from the panel.
 * @source https://github.com/KoJesko/plasma-discord-pings
 */

const fs = require("fs");
const path = require("path");
const os = require("os");

const DATA_DIR = path.join(os.homedir(), ".local", "share", "discord-pings");
const STATE_FILE = path.join(DATA_DIR, "pings.json");
const STATE_TMP = STATE_FILE + ".tmp";
const CMD_DIR = path.join(DATA_DIR, "commands");

const MAX_PINGS = 200;
const WRITE_DEBOUNCE_MS = 250;
const CMD_SWEEP_MS = 2000;

/*
 * Nothing at module scope may touch BdApi. This file is evaluated the moment
 * BetterDiscord loads it, and any throw there surfaces only as the generic
 * "An error was encountered while trying to load this plugin" with no clue
 * which line did it. Every BdApi access is deferred into a method.
 */

/** Stores get renamed across Discord builds, so look them up two ways. */
function findStore(W, name) {
    try {
        if (typeof W.getStore === "function") {
            const s = W.getStore(name);
            if (s) return s;
        }
    } catch (_) { /* fall through to the generic lookup */ }
    return W.getModule(m => m?.getName?.() === name, { searchExports: true });
}

module.exports = class PingBridge {
    constructor(meta) {
        this.meta = meta;
        this.pings = [];
        this.writeTimer = null;
        this.watcher = null;
        this.sweepTimer = null;
        this.subscriptions = [];
        this.settings = { keywords: "", captureEveryone: true, backfillOnStart: true };
        // Reading saved settings is best-effort: a failure here must not stop
        // the plugin from loading, or we're back to the opaque load error.
        try {
            Object.assign(this.settings, BdApi.Data.load("PingBridge", "settings") || {});
        } catch (_) { /* first run, or BdApi.Data not ready yet */ }
    }

    // ---------------------------------------------------------------- lifecycle

    start() {
        const W = BdApi.Webpack;
        this.modules = {
            Dispatcher: W.getModule(m => m?.dispatch && m?.subscribe && m?._actionHandlers)
                || W.getByKeys("dispatch", "subscribe"),
            UserStore: findStore(W, "UserStore"),
            ChannelStore: findStore(W, "ChannelStore"),
            GuildStore: findStore(W, "GuildStore"),
            GuildMemberStore: findStore(W, "GuildMemberStore"),
            HTTP: W.getByKeys("getAPIBaseURL", "get") || W.getByKeys("get", "post", "patch", "del"),
        };

        const missing = Object.entries(this.modules)
            .filter(([, v]) => !v)
            .map(([k]) => k);
        if (missing.length) {
            // Write the failure into the state file so the widget can surface it
            // instead of just silently showing an empty list forever.
            this.writeError(`PingBridge could not resolve: ${missing.join(", ")}. Discord likely changed its internals.`);
            BdApi.UI.showToast(`PingBridge: missing ${missing.join(", ")}`, { type: "error" });
            return;
        }

        fs.mkdirSync(CMD_DIR, { recursive: true });
        this.loadState();

        this.onMessage = this.handleMessageCreate.bind(this);
        this.onAck = this.handleAck.bind(this);
        this.subscribe("MESSAGE_CREATE", this.onMessage);
        this.subscribe("MESSAGE_ACK", this.onAck);
        this.subscribe("CHANNEL_ACK", this.onAck);

        this.watchCommands();
        if (this.settings.backfillOnStart) this.backfill();
        this.scheduleWrite();
        BdApi.Logger?.info?.("PingBridge", `bridging to ${STATE_FILE}`);
    }

    stop() {
        for (const [event, cb] of this.subscriptions) {
            try { this.modules.Dispatcher.unsubscribe(event, cb); } catch (_) { /* already gone */ }
        }
        this.subscriptions = [];
        if (this.watcher) { this.watcher.close(); this.watcher = null; }
        if (this.sweepTimer) { clearInterval(this.sweepTimer); this.sweepTimer = null; }
        if (this.writeTimer) { clearTimeout(this.writeTimer); this.writeTimer = null; }
        this.flush();
    }

    subscribe(event, cb) {
        this.modules.Dispatcher.subscribe(event, cb);
        this.subscriptions.push([event, cb]);
    }

    // ---------------------------------------------------------------- capture

    get selfId() {
        return this.modules.UserStore.getCurrentUser()?.id;
    }

    myRoles(guildId) {
        if (!guildId) return [];
        try {
            return this.modules.GuildMemberStore.getSelfMember(guildId)?.roles || [];
        } catch (_) {
            return [];
        }
    }

    get keywordList() {
        return String(this.settings.keywords || "")
            .split(",")
            .map(s => s.trim().toLowerCase())
            .filter(Boolean);
    }

    /**
     * Decide whether a message is a ping for us and, if so, what kind.
     * Returns a kind string, or null when the message should be ignored.
     *
     * Kinds: "dm" | "direct" | "reply" | "role" | "everyone" | "keyword"
     */
    classifyPing(msg, channel) {
        const me = this.selfId;
        if (!msg || !me) return null;
        if (msg.author?.id === me) return null;                 // never ping ourselves
        if (msg.flags & 64) return null;                        // ephemeral

        const isDM = channel && (channel.type === 1 || channel.type === 3);
        if (isDM) return "dm";

        const mentionsMe = (msg.mentions || []).some(u => (u?.id ?? u) === me);
        if (mentionsMe) {
            // A reply that pings you arrives as a normal mention; distinguish it
            // so the widget can show "replied to you" rather than "mentioned you".
            if (msg.referenced_message?.author?.id === me) return "reply";
            return "direct";
        }
        if (msg.referenced_message?.author?.id === me) return "reply";

        const guildId = msg.guild_id || channel?.guild_id;
        const roles = msg.mention_roles || [];
        if (roles.length && this.myRoles(guildId).some(r => roles.includes(r))) return "role";

        if (msg.mention_everyone && this.settings.captureEveryone) return "everyone";

        const kws = this.keywordList;
        if (kws.length) {
            const body = String(msg.content || "").toLowerCase();
            if (kws.some(k => body.includes(k))) return "keyword";
        }
        return null;
    }

    handleMessageCreate(event) {
        const msg = event?.message;
        if (!msg) return;
        const channel = this.modules.ChannelStore.getChannel(msg.channel_id);
        const kind = this.classifyPing(msg, channel);
        if (!kind) return;
        this.addPing(this.toRecord(msg, channel, kind));
    }

    handleAck(event) {
        const channelId = event?.channelId;
        if (!channelId) return;
        let changed = false;
        for (const p of this.pings) {
            if (p.channelId === channelId && !p.read) { p.read = true; changed = true; }
        }
        if (changed) this.scheduleWrite();
    }

    toRecord(msg, channel, kind) {
        const guildId = msg.guild_id || channel?.guild_id || null;
        const guild = guildId ? this.modules.GuildStore.getGuild(guildId) : null;
        const author = msg.author || {};

        let channelName;
        if (!channel) channelName = "unknown";
        else if (channel.type === 1) channelName = "Direct Message";
        else if (channel.type === 3) channelName = channel.name || "Group DM";
        else channelName = "#" + (channel.name || channel.id);

        return {
            id: msg.id,
            channelId: msg.channel_id,
            guildId,
            guildName: guild?.name || (guildId ? guildId : "Direct Messages"),
            channelName,
            authorId: author.id,
            authorName: author.global_name || author.username || "unknown",
            avatarUrl: this.avatarUrl(author),
            content: this.plainText(msg),
            timestamp: Date.parse(msg.timestamp) || Date.now(),
            kind,
            read: false,
        };
    }

    avatarUrl(author) {
        if (!author?.id) return "";
        if (author.avatar) {
            const ext = String(author.avatar).startsWith("a_") ? "gif" : "png";
            return `https://cdn.discordapp.com/avatars/${author.id}/${author.avatar}.${ext}?size=64`;
        }
        // Default avatars: legacy accounts index by discriminator, pomelo by id.
        const idx = author.discriminator && author.discriminator !== "0"
            ? Number(author.discriminator) % 5
            : Number((BigInt(author.id) >> 22n) % 6n);
        return `https://cdn.discordapp.com/embed/avatars/${idx}.png`;
    }

    /** Flatten mentions/emoji/newlines so the widget can show a one-line preview. */
    plainText(msg) {
        let text = String(msg.content || "");
        for (const u of msg.mentions || []) {
            const name = u.global_name || u.username;
            if (u.id && name) text = text.split(`<@${u.id}>`).join(`@${name}`).split(`<@!${u.id}>`).join(`@${name}`);
        }
        text = text.replace(/<a?:(\w+):\d+>/g, ":$1:").replace(/\s+/g, " ").trim();
        if (!text && (msg.attachments || []).length) text = `[${msg.attachments.length} attachment(s)]`;
        if (!text && (msg.embeds || []).length) text = "[embed]";
        return text;
    }

    addPing(record) {
        const existing = this.pings.findIndex(p => p.id === record.id);
        if (existing !== -1) this.pings.splice(existing, 1);
        this.pings.unshift(record);
        if (this.pings.length > MAX_PINGS) this.pings.length = MAX_PINGS;
        this.scheduleWrite();
    }

    // ---------------------------------------------------------------- backfill

    /**
     * Pull recent mentions through Discord's own HTTP module on startup, so the
     * list isn't empty until someone pings you. This is the same request the
     * client makes when you open the Inbox, on the same session.
     */
    backfill() {
        const { HTTP } = this.modules;
        if (!HTTP?.get) return;
        HTTP.get({
            url: "/users/@me/mentions",
            query: { limit: 25, roles: true, everyone: !!this.settings.captureEveryone },
        }).then(res => {
            const body = res?.body || [];
            let added = 0;
            for (const msg of body) {
                if (this.pings.some(p => p.id === msg.id)) continue;
                const channel = this.modules.ChannelStore.getChannel(msg.channel_id);
                const kind = this.classifyPing(msg, channel) || "direct";
                this.pings.push(this.toRecord(msg, channel, kind));
                added++;
            }
            if (added) {
                this.pings.sort((a, b) => b.timestamp - a.timestamp);
                if (this.pings.length > MAX_PINGS) this.pings.length = MAX_PINGS;
                this.scheduleWrite();
            }
            BdApi.Logger?.info?.("PingBridge", `backfilled ${added} mention(s)`);
        }).catch(err => {
            BdApi.Logger?.warn?.("PingBridge", "backfill failed", err);
        });
    }

    // ---------------------------------------------------------------- commands

    /** The widget drops JSON files into commands/; we execute and delete them. */
    watchCommands() {
        const run = () => this.drainCommands();
        try {
            this.watcher = fs.watch(CMD_DIR, () => setTimeout(run, 20));
        } catch (err) {
            BdApi.Logger?.warn?.("PingBridge", "fs.watch unavailable, polling only", err);
        }
        this.sweepTimer = setInterval(run, CMD_SWEEP_MS);
    }

    drainCommands() {
        let files;
        try { files = fs.readdirSync(CMD_DIR); } catch (_) { return; }
        for (const file of files) {
            if (!file.endsWith(".json")) continue;
            const full = path.join(CMD_DIR, file);
            let cmd;
            try {
                cmd = JSON.parse(fs.readFileSync(full, "utf8"));
            } catch (_) {
                // Half-written file; the next sweep will pick it up complete.
                continue;
            }
            try { fs.unlinkSync(full); } catch (_) { /* already removed */ }
            try { this.execute(cmd); } catch (err) {
                BdApi.Logger?.warn?.("PingBridge", "command failed", cmd, err);
            }
        }
    }

    execute(cmd) {
        switch (cmd?.op) {
            case "ack":
                this.ack(cmd.channelId, cmd.messageId);
                this.mark(cmd.messageId, { read: true });
                break;
            case "dismiss":
                this.pings = this.pings.filter(p => p.id !== cmd.messageId);
                this.removeFromInbox(cmd.messageId);
                this.scheduleWrite();
                break;
            case "ackAll":
                for (const p of this.pings) {
                    if (!p.read) { this.ack(p.channelId, p.id); p.read = true; }
                }
                this.scheduleWrite();
                break;
            case "clear":
                this.pings = [];
                this.scheduleWrite();
                break;
            case "refresh":
                this.backfill();
                break;
            default:
                BdApi.Logger?.warn?.("PingBridge", "unknown op", cmd);
        }
    }

    mark(messageId, patch) {
        const p = this.pings.find(x => x.id === messageId);
        if (p) { Object.assign(p, patch); this.scheduleWrite(); }
    }

    ack(channelId, messageId) {
        const { HTTP } = this.modules;
        if (!HTTP?.post || !channelId || !messageId) return;
        HTTP.post({
            url: `/channels/${channelId}/messages/${messageId}/ack`,
            body: { token: null },
        }).catch(err => BdApi.Logger?.warn?.("PingBridge", "ack failed", err));
    }

    removeFromInbox(messageId) {
        const { HTTP } = this.modules;
        if (!HTTP?.del || !messageId) return;
        HTTP.del({ url: `/users/@me/mentions/${messageId}` })
            .catch(err => BdApi.Logger?.warn?.("PingBridge", "inbox delete failed", err));
    }

    // ---------------------------------------------------------------- state io

    loadState() {
        try {
            const raw = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
            if (Array.isArray(raw?.pings)) this.pings = raw.pings;
        } catch (_) {
            this.pings = [];   // first run, or a corrupted file we can safely rebuild
        }
    }

    scheduleWrite() {
        if (this.writeTimer) return;
        this.writeTimer = setTimeout(() => {
            this.writeTimer = null;
            this.flush();
        }, WRITE_DEBOUNCE_MS);
    }

    flush() {
        const me = this.modules?.UserStore?.getCurrentUser?.();
        this.writeState({
            version: 1,
            updatedAt: Date.now(),
            bridgeUp: true,
            self: me ? { id: me.id, name: me.global_name || me.username } : null,
            pings: this.pings,
        });
    }

    writeError(message) {
        this.writeState({ version: 1, updatedAt: Date.now(), bridgeUp: false, error: message, pings: [] });
    }

    /** Atomic write so the widget never reads a half-written file. */
    writeState(obj) {
        try {
            fs.mkdirSync(DATA_DIR, { recursive: true });
            fs.writeFileSync(STATE_TMP, JSON.stringify(obj), "utf8");
            fs.renameSync(STATE_TMP, STATE_FILE);
        } catch (err) {
            BdApi.Logger?.error?.("PingBridge", "state write failed", err);
        }
    }

    // ---------------------------------------------------------------- settings

    getSettingsPanel() {
        return BdApi.UI.buildSettingsPanel({
            settings: [
                {
                    type: "text", id: "keywords", name: "Keyword pings",
                    note: "Comma-separated. Messages containing one are captured even without an @mention.",
                    value: this.settings.keywords,
                },
                {
                    type: "switch", id: "captureEveryone", name: "Capture @everyone / @here",
                    note: "Leave on to capture them; you can still hide them in the widget's filters.",
                    value: this.settings.captureEveryone,
                },
                {
                    type: "switch", id: "backfillOnStart", name: "Backfill on start",
                    note: "Fetch recent mentions from the Inbox when Discord launches.",
                    value: this.settings.backfillOnStart,
                },
            ],
            onChange: (_category, id, value) => {
                this.settings[id] = value;
                BdApi.Data.save("PingBridge", "settings", this.settings);
            },
        });
    }
};
