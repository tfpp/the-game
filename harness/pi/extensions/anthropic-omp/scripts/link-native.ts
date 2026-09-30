import * as fs from "node:fs/promises";
import * as path from "node:path";

// Links the installed platform addon(s) into the vendored natives package. Linux x64
// publishes pi_natives.linux-x64-{modern,baseline}.node instead of a single addon; the
// loader picks a variant, so link every file the platform package ships.
const runtime = path.resolve(import.meta.dir, "../runtime");
const tag = `${process.platform}-${process.arch}`;
const source = path.join(runtime, `node_modules/@oh-my-pi/pi-natives-${tag}`);
const binaries = (await fs.readdir(source))
  .filter(name => name.startsWith(`pi_natives.${tag}`) && name.endsWith(".node"));
if (!binaries.length) throw new Error(`No pi_natives addon for ${tag} in ${source}`);
for (const name of binaries) {
  const target = path.join(runtime, "vendor/natives/native", name);
  try { await fs.symlink(path.relative(path.dirname(target), path.join(source, name)), target); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
}
