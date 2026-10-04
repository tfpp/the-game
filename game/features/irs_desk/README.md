# IRS desk

On the south casino promenade at **(10, 0, 17.8)**, facing the gaming pit.
Use **E**, controller **B/Circle**, or touch **Use**. Type declared gambling
winnings and the tax you choose to pay in dollars, then **Declare and pay**.
Leave or Esc/B closes the form; Start hands over to the pause menu.
Touch uses the decimal keyboard; controller users need a keyboard for text entry.

There is deliberately no rate, suggestion, winnings lookup or truthfulness check.
The jail warning is flavor only: this does not introduce arrests or a jail.
Zero declarations/payments are allowed. Winnings are informational, not a credit.
Tax cannot exceed **$100 per filing**, the existing signed charge API limit,
or the available wallet. Additional filings are voluntary; no tax debt is tracked.

## Authority and lifecycle

The desk uses NetworkedInteraction for authenticated Use, range, payload validation
and private form/receipt events. Each server-issued filing token is single-use.
The server validates bounded integer cents and player identity again on submit.
It captures the amount/account once, locks concurrent submission, and calls
PlayerMoney.adjust_account with that same 64-character operation ID for every retry.
Transient failures lock both amounts and offer Retry; terminal rejection/success
requires a new Use. Wallet busy/table holds and insufficient funds stay owned by
PlayerMoney. Separate players can file concurrently; repeated network requests
cannot debit a completed filing twice. Real-account debits are persisted by the
existing API; temporary/offline money uses its existing idempotent receipts.

Forms/declarations are private session state, not a public or persistent tax ledger.
Disconnect discards the form, but an already-started account payment can finish.
A response is never delivered to a replacement player/account. Respawn/range exit
closes the local form, not a payment already submitted. Mode changes invalidate
old completions. Late joiners see the static desk and the existing replicated
wallet balances, never somebody else's form or receipt.

The desk/chair are existing textured hotel-prop prefabs; the small brass plate
reuses SignBoard. No new models, textures, room geometry, lights or input actions.
No APIs/callers are changed, and no dependency on unmerged PR #501's dialogue UI.

Tests: `tests/features/irs_desk/` covers cents parsing, authenticated requests,
wallet debits/retries, modal behavior, lifecycle, and actual GridMap floor/clearance.
Run `tests/features/irs_desk/network_test.sh` from `game/` for a real server,
driver and late-joining observer (private forms, range, replay and both wallets).
The probe scene accepts `--irs-role=capture` for offline desk/desktop/phone
renders to `/tmp/irs-*.png`; captures require a graphical renderer.
