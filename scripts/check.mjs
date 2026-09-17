import { readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
let checked = 0;
for (const dir of ['src', 'api', 'scripts', 'tests']) {
  for (const entry of await readdir(path.join(root, dir), { withFileTypes: true })) {
    if (!entry.isFile() || !/\.(mjs|js)$/.test(entry.name)) continue;
    const result = spawnSync(process.execPath, ['--check', path.join(root, dir, entry.name)], { encoding: 'utf8' });
    if (result.status !== 0) { process.stderr.write(result.stderr); process.exit(1); }
    checked++;
  }
}
console.log(`${checked} JavaScript files passed syntax checks.`);
