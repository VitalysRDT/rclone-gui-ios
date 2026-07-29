#!/usr/bin/env node
// Compiles the showcase site's JSX sources to the plain JS the pages load.
//
// docs/ is served as-is by GitHub Pages: no bundler at runtime, no CDN and no
// Babel in the browser. Every docs/*.src.jsx is compiled ahead of time to the
// matching docs/*.js (React.createElement calls, classic JSX runtime), which is
// what index.html and forum.html load next to docs/lib/react*.js.
//
//   npm i --prefix /tmp/esb esbuild
//   ESBUILD_PATH=/tmp/esb node scripts/build-site.mjs [name…] [--check]
//
// With no name, every source is built. `--check` compiles without writing and
// exits non-zero if a committed .js is out of date.

import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const docs = join(root, 'docs');

const args = process.argv.slice(2);
const check = args.includes('--check');
const wanted = args.filter((a) => !a.startsWith('--'));

function esbuildBinary() {
  const candidates = [
    process.env.ESBUILD_PATH && join(resolve(process.env.ESBUILD_PATH), 'node_modules/.bin/esbuild'),
    process.env.ESBUILD_PATH && join(resolve(process.env.ESBUILD_PATH), 'esbuild'),
    join(root, 'node_modules/.bin/esbuild'),
  ].filter(Boolean);

  for (const bin of candidates) {
    try {
      execFileSync(bin, ['--version'], { stdio: 'ignore' });
      return bin;
    } catch (err) { /* try the next location */ }
  }
  try {
    execFileSync('esbuild', ['--version'], { stdio: 'ignore' });
    return 'esbuild';
  } catch (err) { /* not on PATH either */ }

  console.error(
    'esbuild not found. Install it and point ESBUILD_PATH at the install prefix:\n'
    + '  npm i --prefix /tmp/esb esbuild\n'
    + '  ESBUILD_PATH=/tmp/esb node scripts/build-site.mjs',
  );
  process.exit(2);
}

const esbuild = esbuildBinary();
const sources = readdirSync(docs)
  .filter((name) => name.endsWith('.src.jsx'))
  .filter((name) => wanted.length === 0 || wanted.includes(name.replace(/\.src\.jsx$/, '')))
  .sort();

if (sources.length === 0) {
  console.error(`No matching source in docs/ for: ${wanted.join(', ') || '(all)'}`);
  process.exit(2);
}

const scratch = mkdtempSync(join(tmpdir(), 'rgsite-'));
let stale = 0;

try {
  for (const source of sources) {
    const target = source.replace(/\.src\.jsx$/, '.js');
    const built = join(scratch, target);

    // Note: no --charset=utf8, so non-ASCII stays escaped exactly like the
    // committed files.
    execFileSync(esbuild, [
      join(docs, source),
      '--bundle',
      `--outfile=${built}`,
      '--loader:.jsx=jsx',
      '--jsx=transform',
      '--format=iife',
      '--log-level=warning',
    ], { stdio: ['ignore', 'ignore', 'inherit'] });

    const output = readFileSync(built, 'utf8');
    let current = null;
    try { current = readFileSync(join(docs, target), 'utf8'); } catch (err) { /* first build */ }

    if (current === output) {
      console.log(`  = ${target} (up to date)`);
      continue;
    }
    if (check) {
      console.error(`  ✗ ${target} is out of date — run: node scripts/build-site.mjs`);
      stale += 1;
      continue;
    }

    writeFileSync(join(docs, target), output);
    console.log(`  → ${target} (${(output.length / 1024).toFixed(1)} kB)`);
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

process.exit(stale > 0 ? 1 : 0);
