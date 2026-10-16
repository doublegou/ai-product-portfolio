import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
for (const partial of [false, true]) {
  test(partial ? 'partial failure retains successful items and source errors' : 'all-source failure saves report and returns failure', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'radar-cli-'));
    try {
      const preload = path.join(dir, 'fetch.mjs');
      await writeFile(preload, `globalThis.fetch = async (url) => {
        if (${partial} && String(url).includes('news.ycombinator.com'))
          return new Response('<table><tr class="athing" id="123"><td><span class="titleline"><a href="https://example.com/article">Fixture article</a></span></td></tr></table>');
        return new Response('Forbidden fixture', {status:403, statusText:'Forbidden'});
      };`);
      const output = path.join(dir, 'report.json');
      const run = spawnSync(process.execPath, ['--import', preload, 'scripts/run.mjs', '--sources', 'github,hackernews', '--format', 'json', '--output', output], {cwd:root, encoding:'utf8', timeout:10000});
      assert.equal(run.status, partial ? 0 : 1, run.stderr);
      const report = JSON.parse(await readFile(output, 'utf8'));
      assert.equal(report.sourceStatus.length, 2);
      assert.equal(report.sourceStatus[0].ok, false);
      assert.match(report.sourceStatus[0].error, /403/);
      assert.equal(report.itemCount, partial ? 1 : 0);
      assert.equal(report.items.length, partial ? 1 : 0);
      if (!partial) assert.match(run.stderr, /All sources failed/);
    } finally { await rm(dir, {recursive:true, force:true}); }
  });
}
