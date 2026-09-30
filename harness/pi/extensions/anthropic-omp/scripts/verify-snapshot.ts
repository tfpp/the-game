import * as path from "node:path";
import snapshot from "../runtime/snapshot.json" with { type: "json" };

const root = path.resolve(import.meta.dir, "../runtime/vendor");
const changed: string[] = [];
for (const [file, expected] of Object.entries(snapshot.hashes)) {
  try {
    const bytes = await Bun.file(path.join(root, file)).arrayBuffer();
    const hash = new Bun.CryptoHasher("sha256").update(bytes).digest("hex");
    if (hash !== expected) changed.push(file);
  } catch { changed.push(file); }
}
if (changed.length) throw new Error(`Pinned OMP snapshot modified or missing: ${changed.join(", ")}`);
console.log(`Verified ${Object.keys(snapshot.hashes).length} pinned files at ${snapshot.revision}`);
