# Anthropic subscription provider backed by OMP

Personal Pi extension installed at `~/.pi/agent/extensions/anthropic-omp`.

**This reuses the fork's actual provider/auth implementation; it is not a header-only imitation.** It is pinned to oh-my-pi commit `740f3e3154a3f1561a0badb0ec076097fa733028` (package version 18.3.0). The original checkout and Pi's built-in Anthropic provider are unchanged.

## Start

1. Run `/reload` in Pi, or restart Pi.
2. Run `/login` and select **Anthropic subscription (OMP)**.
3. Complete the browser flow. If the browser cannot reach this machine, paste the final redirect URL/code into Pi's prompt.
4. Select a model under **anthropic-omp** with `/model`.

No credentials have been imported from Pi, Claude Code, or OMP. The extension requires its own login. Existing Anthropic selections are not automatically changed.

Commands:

- `/omp-anthropic-status`: backend version and stored subscription-account count; does not perform inference.
- `/omp-anthropic-forget`: confirmation, then delete all grants in this extension's store. Afterwards use `/logout` for **Anthropic subscription (OMP)** to remove Pi's non-secret marker too.

**Pi's ordinary `/logout` removes only its marker, disabling requests through this provider. Use `/omp-anthropic-forget` to delete the underlying grants.** Grant deletion is local, not server-side token revocation.

## Architecture and fidelity

Pi (Node/jiti) → private stdio IPC → a lazily started Bun process → unchanged, pinned OMP code.

The snapshot contains the required source packages, KDL-compiled policy/catalog, and the coding-agent's session-metadata helper. The published matching native addon is installed locally. `runtime/snapshot.json` records SHA-256 hashes; `bun run verify:snapshot` checks them. The snapshot does not follow changes to the original checkout automatically.

Reused behavior includes:

- Authorization-code + PKCE login, browser/manual callback handling, scopes and token endpoint; callback port **54545**.
- Account/organization identity bootstrap, SQLite credential storage, early refresh, rotating refresh tokens, cross-process refresh leases, and default account selection/rotation.
- The fork's `streamSimple` path, including replay-safe auth recovery; not just the low-level Anthropic transport.
- Claude Code client/beta headers, identity and billing system blocks, final serialized-body CCH checksum, tool-name mapping, session/account/device metadata, caching policy and output limits.
- The fork's model/effort policy, reasoning/signatures, usage accounting, and provider retries.
- Pi payload/response hooks, cancellation, text/thinking/tool streaming, and lossless preservation of the fork's history/control fields through Pi session JSON.

The statusbar can request sanitized five-hour/seven-day usage through the `anthropic-omp:usage` event and the existing worker's `usage` operation. The backend uses the fork's usage cache and refresh coordination for the session's active account, without changing account selection. A sole stored account is used before selection; ambiguous multi-account sessions return no usage. No credentials cross this display-only bridge.

Real access/refresh tokens stay in the Bun backend's SQLite store. Only a non-secret managed-credential marker and identity metadata enter Pi's `auth.json`. Repeated logins can add accounts to the fork's credential pool.

### Exactness boundary

This is **provider-layer parity, not the entire OMP coding-agent**. Pi still chooses its own prompts, tools, agent loop, compaction, outer retry policy and context. The bridge resolves Pi's system/tool deltas into the fork's current-context format and preserves fork tool/effort request-control records between turns. Therefore requests from the two complete applications are not promised to be byte-identical for differently assembled conversations.

**Pi documentation pointer:** this extension replaces Pi's recognized, generated `<docs>` index with a short pointer to the installed README: “Pi documentation: `<README path>`. Consult only when asked about Pi.” This is applied only to the outgoing `anthropic-omp` system prompt, before the fork builds/signs the request. Stored transcripts, other providers, project instructions and ordinary custom `<docs>` blocks are not modified; no documentation files are deleted. Unrecognized or malformed blocks are left intact. The longer topic-to-document index is no longer injected automatically.

The normal Pi `streamSimple` contract is supported. OMP-only caller features/configuration (custom OMP model definitions, account-policy settings, agent-managed cache warming, optional compaction/fallback controls) are not exposed as Pi settings. Pi-native Anthropic SDK clients/thinking controls, custom JS fetch functions, per-request environment overrides, deferred responses, and null-valued header suppression are rejected rather than silently approximated. Use Pi's ordinary thinking-level selector. Pi's SDK routinely supplies `timeoutMs` and may supply `maxRetries`; these are accepted but not forwarded, preserving the fork's own first-event/idle timeouts and transport/auth retry policy. Pi's outer agent retries and cancellation still apply.

Input images and signed/redacted thinking are preserved. Extra OMP-only assistant blocks retain their opaque data with a display marker; assistant-image streaming events are rejected because Pi's assistant event protocol cannot represent them.

Two deliberate safety restrictions: this provider never falls back to a paid API key, and it refuses non-official/environment-redirected inference endpoints. It does not share live rotating grants with other applications.

## Local files and requirements

- Pi tested: **0.87.1**, Node **26.8.2**.
- Bun tested: **1.4.2**; the fork requires Bun ≥1.3.14. `bun` must be on Pi's PATH, or set `PI_OMP_BUN` to its executable.
- Native addon installed for this machine: `@oh-my-pi/pi-natives-darwin-arm64@18.3.0`.
- `state/auth.db`: real subscription grants; directory mode 0700, database mode 0600. This is file-permission-protected SQLite, **not encrypted/keychain storage**.
- `state/last-wire-error.json`: redacted diagnostics from the final HTTP send point on a rejected Messages request. Includes Claude Code headers, verification of the final billing checksum using the fork's signer, and whether metadata matches the selected account. Excludes tokens, account/session IDs, prompt content, tool arguments and response bodies. The fork's separate `http-400-requests` dump is **pre-signing**; its `cch=00000` placeholder is not proof that an unsigned request was sent.
- `state/`: also isolates the fork's install identity, logs and agent state from the user's normal OMP configuration. `PI_OMP_STATE_DIR` can override this directory.
- `runtime/vendor/`: pinned source; MIT license in `runtime/LICENSE.oh-my-pi`.

The factory starts no background processes. Login/status/inference starts the worker; shutdown/reload stops it and cancels outstanding work. IPC uses pipes, not a local inference HTTP server. The OAuth flow temporarily opens its own loopback callback listener.

## Verification

From this directory:

```sh
bun check
bun test
node scripts/smoke-node.mjs
bun run verify:snapshot
```

Offline tests cover login/PKCE and grant persistence, identical outbound bytes versus direct fork calls (including final CCH), tool-name round trips, request hooks, refresh single-flight, 401 replay, no API-key fallback, endpoint protection, session-history preservation, stream framing, cancellation/concurrency and child failure. The Node smoke test uses Pi's actual loader and crosses the real Bun boundary; it deliberately blocks routing before credentials/network inference.

Live diagnostics verified that both stored OAuth grants accept small requests, and that the full Pi request streamed output when only its generated documentation block was omitted; restoring that block reproduced the upstream extra-usage rejection. The short README pointer was subsequently verified with `claude-opus-5-5` through the actual Node/Pi loader → extension → Bun path: HTTP 200 and a completed text response, with all 22 tool definitions, conversation, metadata and source transcript preserved. The verification used a disposable access-only credential store, not the live rotating refresh grant. The server's rejection reason is still unknown, and these checks cannot guarantee Anthropic will continue to accept this unofficial client.

Local dependency repair:

```sh
(cd runtime && bun install --frozen-lockfile --ignore-scripts)
bun scripts/link-native.ts
bun check
```

Development type/test resolution uses symlinks in `node_modules/@earendil-works` to the installed Pi packages. If Pi's global package location changes, refresh those symlinks. Pi itself supplies these peer packages when loading extensions. Do not edit vendor source to patch behavior unnoticed: make deliberate, reviewed snapshot updates and rerun parity tests.

## Policy caveat

Anthropic's authentication policy restricts subscription OAuth to its native applications and prohibits third-party developers offering Claude.ai login in their applications. This is an unofficial integration and may stop working or be subject to enforcement. See https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use . API-key authentication is the supported route for third-party applications.
