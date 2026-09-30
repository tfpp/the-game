import { Database } from "bun:sqlite";
import type { UsageFetchParams, UsageProvider, UsageReport } from "@oh-my-pi/pi-ai/usage";

/**
 * Anthropic rate-limits /api/oauth/usage per source IP, and every Pi session
 * runs its own worker. The fork already shares the report cache through
 * auth.db, but when an entry expires every worker fetches at once, and a
 * failure only cools down for 10s. This wraps the Claude usage provider with a
 * cross-process single flight: one worker holds a lease and fetches, the others
 * wait for and reuse its result, and any failure (usually a 429) gates every
 * worker for `failureBackoffMs`.
 */
export const USAGE_FAILURE_BACKOFF_MS = 5 * 60_000;
const LEASE_MS = 30_000;
const SHARE_MS = 30_000;
const WAIT_STEP_MS = 250;

interface Row { owner: string | null; lease_until: number; fetched_at: number; report: string | null; failed_until: number }

export class UsagePollCoordinator {
  readonly #db: Database;
  readonly #owner = crypto.randomUUID();
  readonly #now: () => number;
  readonly #backoffMs: number;

  constructor(dbPath: string, options: { now?: () => number; backoffMs?: number } = {}) {
    this.#db = new Database(dbPath, { create: true });
    this.#db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 2000;");
    this.#db.exec(`CREATE TABLE IF NOT EXISTS usage_poll (
      account_key TEXT PRIMARY KEY, owner TEXT, lease_until INTEGER NOT NULL DEFAULT 0,
      fetched_at INTEGER NOT NULL DEFAULT 0, report TEXT, failed_until INTEGER NOT NULL DEFAULT 0)`);
    this.#now = options.now ?? Date.now;
    this.#backoffMs = options.backoffMs ?? USAGE_FAILURE_BACKOFF_MS;
  }

  close(): void { this.#db.close(); }

  /** Returns a shared outcome, or `"lead"` when this process now owns the fetch. */
  #claim(key: string): { report: UsageReport | null } | "lead" | "wait" {
    return this.#db.transaction(() => {
      const now = this.#now();
      const row = this.#db.query<Row, [string]>("SELECT * FROM usage_poll WHERE account_key = ?").get(key);
      if (row?.report && now - row.fetched_at < SHARE_MS) return { report: JSON.parse(row.report) as UsageReport };
      if (row && row.failed_until > now) return { report: null };
      if (row && row.lease_until > now && row.owner !== this.#owner) return "wait";
      this.#db.query(`INSERT INTO usage_poll (account_key, owner, lease_until) VALUES (?1, ?2, ?3)
        ON CONFLICT(account_key) DO UPDATE SET owner = ?2, lease_until = ?3`).run(key, this.#owner, now + LEASE_MS);
      return "lead" as const;
    }).immediate();
  }

  #settle(key: string, report: UsageReport | null): void {
    const now = this.#now();
    if (report) {
      this.#db.query("UPDATE usage_poll SET owner = NULL, lease_until = 0, fetched_at = ?2, report = ?3, failed_until = 0 WHERE account_key = ?1 AND owner = ?4")
        .run(key, now, JSON.stringify(report), this.#owner);
    } else {
      const jitter = this.#backoffMs * (Math.random() * 0.2 - 0.1);
      this.#db.query("UPDATE usage_poll SET owner = NULL, lease_until = 0, failed_until = ?2 WHERE account_key = ?1 AND owner = ?3")
        .run(key, Math.round(now + this.#backoffMs + jitter), this.#owner);
    }
  }

  async run(key: string, signal: AbortSignal | undefined, fetch: () => Promise<UsageReport | null>): Promise<UsageReport | null> {
    for (;;) {
      if (signal?.aborted) return null;
      const claim = this.#claim(key);
      if (claim === "wait") { await Bun.sleep(WAIT_STEP_MS); continue; }
      if (claim !== "lead") return claim.report;
      let report: UsageReport | null = null;
      try { report = await fetch(); return report; }
      finally { this.#settle(key, report); }
    }
  }

  wrap(provider: UsageProvider): UsageProvider {
    return {
      ...provider,
      failureBackoffMs: this.#backoffMs,
      fetchUsage: (params: UsageFetchParams, ctx) =>
        this.run(`${provider.id}:${params.baseUrl ?? "default"}:${params.accountKey ?? "unknown"}`, params.signal,
          () => provider.fetchUsage(params, ctx)),
    };
  }
}
