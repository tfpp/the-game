import { afterEach, expect, test } from "bun:test";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import type { UsageProvider, UsageReport } from "@oh-my-pi/pi-ai/usage";
import { UsagePollCoordinator } from "../runtime/usage-poll";

const dirs: string[] = [];
const open: UsagePollCoordinator[] = [];
afterEach(async () => {
  for (const poll of open.splice(0)) poll.close();
  for (const dir of dirs.splice(0)) await fs.rm(dir, { recursive: true, force: true });
});
async function workers(count: number, now: () => number) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-omp-poll-"));
  dirs.push(dir);
  return Array.from({ length: count }, () => {
    const poll = new UsagePollCoordinator(path.join(dir, "usage-poll.db"), { now, backoffMs: 60_000 });
    open.push(poll);
    return poll;
  });
}
const report = (used: number): UsageReport => ({ provider: "anthropic", fetchedAt: 1, limits: [
  { id: "anthropic:5h", label: "5h", scope: { provider: "anthropic" }, amount: { unit: "percent", used } },
] } as UsageReport);

test("only one worker fetches; concurrent workers wait for and share its result", async () => {
  const [a, b, c] = await workers(3, Date.now);
  let calls = 0, release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const fetch = async () => { calls++; await gate; return report(7); };
  const results = Promise.all([a, b, c].map(poll => poll.run("acct", undefined, fetch)));
  await Bun.sleep(50);
  expect(calls).toBe(1);
  release();
  expect((await results).map(r => r?.limits[0].amount.used)).toEqual([7, 7, 7]);
  expect(calls).toBe(1);
  // A worker arriving just after still reuses the shared result.
  expect((await b.run("acct", undefined, fetch))?.limits[0].amount.used).toBe(7);
  expect(calls).toBe(1);
});

test("a failure (e.g. 429) gates every worker for the backoff, then one retries", async () => {
  let now = 1_000_000;
  const [a, b] = await workers(2, () => now);
  let calls = 0;
  expect(await a.run("acct", undefined, async () => { calls++; return null; })).toBeNull();
  now += 30_000;
  expect(await b.run("acct", undefined, async () => { calls++; return report(1); })).toBeNull();
  expect(calls).toBe(1);
  now += 60_000;
  expect((await b.run("acct", undefined, async () => { calls++; return report(2); }))?.limits[0].amount.used).toBe(2);
  expect(calls).toBe(2);
});

test("a thrown fetch releases the lease and backs off; waiters honor cancellation", async () => {
  let now = 1_000_000;
  const [a, b] = await workers(2, () => now);
  await expect(a.run("acct", undefined, async () => { throw new Error("boom"); })).rejects.toThrow("boom");
  expect(await b.run("acct", undefined, async () => report(3))).toBeNull();
  now += 120_000;
  let release!: () => void;
  const slow = a.run("other", undefined, () => new Promise(resolve => { release = () => resolve(report(4)); }));
  const controller = new AbortController();
  const waiting = b.run("other", controller.signal, async () => report(5));
  controller.abort();
  expect(await waiting).toBeNull();
  release();
  expect((await slow)?.limits[0].amount.used).toBe(4);
});

test("wrap sets the long failure backoff and keys by account", async () => {
  const [a] = await workers(1, Date.now);
  const seen: string[] = [];
  const base: UsageProvider = { id: "anthropic", cacheVersion: 3,
    fetchUsage: async params => { seen.push(params.accountKey!); return report(9); } };
  const wrapped = a.wrap(base);
  expect(wrapped.failureBackoffMs).toBe(60_000);
  expect(wrapped.cacheVersion).toBe(3);
  const ctx = { fetch: globalThis.fetch };
  await wrapped.fetchUsage({ provider: "anthropic", credential: { type: "oauth" }, accountKey: "x" }, ctx);
  await wrapped.fetchUsage({ provider: "anthropic", credential: { type: "oauth" }, accountKey: "y" }, ctx);
  await wrapped.fetchUsage({ provider: "anthropic", credential: { type: "oauth" }, accountKey: "x" }, ctx);
  expect(seen).toEqual(["x", "y"]);
});
