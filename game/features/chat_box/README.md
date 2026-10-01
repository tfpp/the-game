# Text chat

Enter opens public chat; Enter sends, Esc cancels. Existing controller rebinding of
`chat_open` remains supported; there is no new touch/controller control. Messages are
trimmed to 120 characters, escaped for BBCode and shown to every connected peer.
Slash commands go to `chat_commands`; server `send_notice(peer_id, text)` remains private.

## Discord recording

The dedicated server can forward public messages to the existing Discord bot, which
posts them in an operator-created `#game-chat` text channel. This is one-way: Discord
replies never enter the game. The input reminds players public chat may be recorded.
Only the display name and public message are exported, not account IDs, peer IDs, IPs,
private notices, slash commands or voice chat. Discord keeps the posted history according
to the channel's permissions and Discord retention; the game keeps no persistent archive.
Operators should restrict channel visibility appropriately and tell players when enabled.

Provisioning (also see `bot/README.md`):

1. Create `#game-chat` in the game's Discord server. Give the existing bot View Channel
   and Send Messages there. Set `BOT_GAME_CHAT_CHANNEL_ID` to its channel ID.
2. Provision a **new dedicated random key**, at least 32 ASCII bytes, as read-only files
   in the bot and game-server containers. Set `BOT_GAME_CHAT_KEY_FILE` (default
   `/run/secrets/bot/game-chat-key`) and `GAME_CHAT_KEY_FILE` (default
   `/run/secrets/game-chat-key`) to those files. Never reuse account, Discord, GitHub or
   agent keys; never package this key in client exports.
3. Set `GAME_CHAT_BOT_URL=http://bot:8081/bot/game-chat` on the dedicated game server
   (substitute the actual private service address). Prefer private container networking;
   if traversing an untrusted network, use HTTPS. Do not expose a new public tunnel route.
4. Deploy/restart the bot and game server with these settings. Send an ordinary in-game
   message and confirm its display name/text appear once in Discord without a ping.

Configuration is opt-in. Offline previews and clients never load the relay key or send
HTTP requests, even if these settings exist. An unset bot channel leaves its endpoint
unregistered; a configured bot channel with a missing/short key fails bot startup.
The game relay disables itself on missing/invalid configuration; in-game chat still works.
CI cannot provision the live channel or deployment mounts.

### Boundary and delivery semantics

`message_accepted(sender_name, text)` fires **only on the authoritative server**, after
normal public-message validation and RPC broadcast. `DiscordRelay` subscribes locally;
client receive RPCs and notices do not emit it. Existing RPC and notice signatures stay
unchanged. Direct slash-text submissions to the public RPC are rejected; the existing
command RPC/group handles commands separately.

The relay sends signed JSON `{id, timestamp, sender, text}` to `POST /bot/game-chat`.
Signature: hex HMAC-SHA256 of `game-chat-v1\n` plus the exact JSON bytes, in
`X-Game-Chat-Signature`, keyed with the trimmed file's UTF-8 bytes. IDs are a random
32-hex-character process session plus `:` and an incrementing sequence; they identify
messages, not players. The bot validates lengths, a ±5-minute timestamp and ID shape,
then posts literal code-block text through its existing no-mention `Post` interface.
Backticks/control characters cannot escape that block. Client payloads never select the
Discord channel or claim a sender name.

Delivery is **best effort**, not a durable audit log: one HTTP request at a time, a
100-message bound including the in-flight message, 10-second timeouts and at most three
attempts (1/2-second backoff). Full queues drop new messages; permanent HTTP rejections
drop immediately. Delivery failure does not delay gameplay/broadcasts. Retries retain
the same ID/body. The bot serializes posts and retains successful IDs for 10 minutes,
with a 4096-ID memory bound. Restarting either service loses queued/replay state. An
ambiguous Discord API timeout or bot crash after posting can still produce a duplicate;
long outages/queue pressure can lose messages. Late joiners see only new game chat and
never replay/export old messages. Disconnects/respawns do not alter accepted messages;
simultaneous sends retain server arrival order.

## Tests

```sh
cd game
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/chat_box -gexit
```

The suite includes real server/client/late-join ENet transport at the chat RPC boundary,
plus queue/offline/exclusion regressions. Bot HTTP signature, validation, replay,
formatting and retry tests are in `bot/internal/webhook/game_chat_test.go`.
