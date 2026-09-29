'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const source = path.resolve(__dirname, '..');
const revision = 'a'.repeat(40);

function fixture(t, platform = 'linux') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'the-game-install-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const script = (name, body) => fs.writeFileSync(path.join(bin, name), '#!/bin/bash\nset -eu\n' + body, { mode: 0o755 });
  script('node', `if [[ "\${1:-}" == -p && "$2" == process.platform ]]; then echo "$TEST_PLATFORM"; elif [[ "\${1:-}" == -p && "$2" == process.arch ]]; then echo x64; else exec "$REAL_NODE" "$@"; fi\n`);
  script('curl', `[[ "\${FAIL_DOWNLOAD:-}" != 1 ]] || exit 22
url=''; output=''
while [[ $# -gt 0 ]]; do
  case "$1" in https:*) url=$1; shift ;; -o) output=$2; shift 2 ;; *) shift ;; esac
done
if [[ "$url" == *api.github.com* ]]; then echo '{"sha":"${revision}"}'; else
  [[ "$url" == *'/${revision}/desktop/'* ]] || exit 3
  cp "$SOURCE/\${url##*/}" "$output"
fi
`);
  script('npm', `if [[ "$1" == ci ]]; then [[ "\${FAIL_BUILD:-}" != 1 ]]; else
  mkdir -p "dist/TheGame-$TEST_PLATFORM-x64"
  case "$TEST_PLATFORM" in darwin) mkdir "dist/TheGame-$TEST_PLATFORM-x64/TheGame.app" ;; win32) touch "dist/TheGame-$TEST_PLATFORM-x64/TheGame.exe" ;; *) touch "dist/TheGame-$TEST_PLATFORM-x64/TheGame" ;; esac
fi
`);
  script('mv', 'if [[ "${FAIL_SWAP:-}" == 1 && "$1" == */dist/* ]]; then exit 1; fi\nexec /bin/mv "$@"\n');
  script('cygpath', 'printf "%s\\n" "$2"\n');
  const prefix = path.join(root, 'Apps with spaces', 'TheGame');
  const env = { ...process.env, HOME: root, XDG_DATA_HOME: path.join(root, 'data'), LOCALAPPDATA: root,
    PATH: bin + path.delimiter + process.env.PATH, REAL_NODE: process.execPath, SOURCE: source, TEST_PLATFORM: platform };
  const run = (overrides = {}, args = []) => spawnSync('bash', [path.join(source, 'install.sh'), '--prefix', prefix, ...args],
    { env: { ...env, ...overrides }, encoding: 'utf8' });
  return { root, prefix, env, run };
}

for (const platform of ['linux', 'darwin', 'win32']) {
  test(`installer builds and updates ${platform} for the current user`, t => {
    const f = fixture(t, platform);
    let result = f.run();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(path.join(f.prefix, '.the-game-installer'), 'utf8').trim(), revision);
    fs.writeFileSync(path.join(f.prefix, 'old-version'), 'old');
    result = f.run({}, ['--ref', revision]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(path.join(f.prefix, 'old-version')), false);
    assert.equal(fs.existsSync(f.prefix + '.install-lock'), false);
    if (platform === 'linux') {
      const launcher = fs.readFileSync(path.join(f.env.XDG_DATA_HOME, 'applications/the-game.desktop'), 'utf8');
      assert.ok(launcher.includes(`Exec="${f.prefix}/TheGame"`));
      assert.ok(!launcher.includes('--no-sandbox'));
    }
  });
}

test('failed downloads, builds and replacement restore the existing app and release the lock', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  fs.writeFileSync(path.join(f.prefix, 'old-version'), 'keep');
  for (const failure of ['FAIL_DOWNLOAD', 'FAIL_BUILD', 'FAIL_SWAP']) {
    const result = f.run({ [failure]: '1' });
    assert.notEqual(result.status, 0);
    assert.equal(fs.readFileSync(path.join(f.prefix, 'old-version'), 'utf8'), 'keep');
    assert.equal(fs.existsSync(f.prefix + '.install-lock'), false);
  }
});

test('unmanaged directories and concurrent installs are rejected', t => {
  const f = fixture(t);
  fs.mkdirSync(f.prefix, { recursive: true });
  fs.writeFileSync(path.join(f.prefix, 'mine'), 'keep');
  assert.match(f.run().stderr, /unmanaged/);
  assert.equal(fs.readFileSync(path.join(f.prefix, 'mine'), 'utf8'), 'keep');
  fs.writeFileSync(path.join(f.prefix, '.the-game-installer'), revision);
  fs.mkdirSync(f.prefix + '.install-lock');
  assert.match(f.run().stderr, /Another install/);
});

test('a pipe invocation installs correctly and cleans temporary files', t => {
  const f = fixture(t);
  const result = spawnSync('bash', ['-s', '--', '--prefix', f.prefix], {
    env: f.env, input: fs.readFileSync(path.join(source, 'install.sh')), encoding: 'utf8'
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fs.readdirSync(path.dirname(f.prefix)), ['TheGame']);
});
