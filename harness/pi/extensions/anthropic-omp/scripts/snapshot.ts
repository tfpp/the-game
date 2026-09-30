// Installation-time snapshot, never run automatically by the extension.
import * as fs from "node:fs/promises";
import * as path from "node:path";

const source = process.argv[2];
const revision = process.argv[3];
if (!source || !revision) throw new Error("Usage: bun scripts/snapshot.ts <checkout> <revision>");
const root = path.resolve(import.meta.dir, "..");
const runtime = path.join(root, "runtime");
const packages = ["ai", "catalog", "utils", "wire", "omptype", "natives"];
const hashes: Record<string, string> = {};
const rootManifest = await Bun.file(path.join(source, "package.json")).json();
for (const name of packages) {
  const from = path.join(source, "packages", name);
  const to = path.join(runtime, "vendor", name);
  await fs.mkdir(to, { recursive: true });
  for (const subdir of ["src", "native"]) {
    try { await fs.cp(path.join(from, subdir), path.join(to, subdir), { recursive: true, errorOnExist: true, force: false }); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const manifest = await Bun.file(path.join(from, "package.json")).json();
  for (const [dep, version] of Object.entries(manifest.dependencies ?? {})) {
    if (version === "catalog:") manifest.dependencies[dep] = `workspace:*`;
  }
  delete manifest.devDependencies;
  delete manifest.scripts;
  await Bun.write(path.join(to, "package.json"), JSON.stringify(manifest, null, 2) + "\n");
  const glob = new Bun.Glob("**/*");
  for await (const file of glob.scan({ cwd: to, onlyFiles: true })) {
    hashes[`${name}/${file}`] = new Bun.CryptoHasher("sha256").update(await Bun.file(path.join(to, file)).arrayBuffer()).digest("hex");
  }
}
for (const file of ["session-metadata.ts", "auth-storage.ts"]) {
  const relative = `coding-agent/src/session/${file}`;
  const bytes = await Bun.file(path.join(source, "packages", relative)).arrayBuffer();
  await Bun.write(path.join(runtime, "vendor", relative), bytes);
  hashes[relative] = new Bun.CryptoHasher("sha256").update(bytes).digest("hex");
}
await fs.copyFile(path.join(source, "LICENSE"), path.join(runtime, "LICENSE.oh-my-pi"));
await Bun.write(path.join(runtime, "package.json"), JSON.stringify({
  name: "anthropic-omp-runtime", private: true, type: "module",
  workspaces: ["vendor/*"],
  dependencies: {
    "@oh-my-pi/pi-ai": "workspace:*",
    "@oh-my-pi/pi-catalog": "workspace:*",
    [`@oh-my-pi/pi-natives-${process.platform}-${process.arch}`]: rootManifest.workspaces.catalog["@oh-my-pi/pi-natives"],
  },
}, null, 2) + "\n");
await Bun.write(path.join(runtime, "snapshot.json"), JSON.stringify({ revision, source, hashes }, null, 2) + "\n");
