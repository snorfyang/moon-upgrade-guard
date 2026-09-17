#!/usr/bin/env node
//
// Differential check of the storage compatibility engine against
// OpenZeppelin Upgrades Core.
//
// Both tools are given the same pair of artifacts and asked for a verdict. The
// point is not that the two agree on wording, but that they agree on whether the
// change blocks an upgrade, and that every disagreement is understood.
//
// This is a development tool, not part of CI: it needs Node and a copy of
// `@openzeppelin/upgrades-core`, while the test suite stays offline and depends
// on nothing but the MoonBit toolchain.
//
//   npm install --prefix /tmp/ozdiff @openzeppelin/upgrades-core
//   OZ_UPGRADES_CORE=/tmp/ozdiff/node_modules/@openzeppelin/upgrades-core \
//     node scripts/oz-differential.mjs
//
// Environment:
//   OZ_UPGRADES_CORE  path to an installed @openzeppelin/upgrades-core
//   MOONUPGRADEGUARD_BIN  path to the native CLI (defaults to the debug build)
//   FIXTURES          directory holding the fixture pairs (defaults to fixtures)

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const oz = require(
  process.env.OZ_UPGRADES_CORE ?? '@openzeppelin/upgrades-core',
);
const cli =
  process.env.MOONUPGRADEGUARD_BIN ??
  '_build/native/debug/build/cmd/moonupgradeguard/moonupgradeguard.exe';
const fixtures = process.env.FIXTURES ?? 'fixtures';

const ozVersion = require(
  path.join(process.env.OZ_UPGRADES_CORE ?? '@openzeppelin/upgrades-core', 'package.json'),
).version;

// The engine's verdict: exit 1 means a blocking finding, 0 means none, and 2
// means the tool refused the input. Only the first two are comparable.
function runEngine(dir) {
  const args = ['storage', `${dir}/old.json`, `${dir}/new.json`, '--format', 'json'];
  let stdout = '';
  let status = 0;
  try {
    stdout = execFileSync(cli, args, { encoding: 'utf8' });
  } catch (error) {
    status = error.status ?? -1;
    stdout = `${error.stdout ?? ''}${error.stderr ?? ''}`;
  }
  let codes = [];
  try {
    const parsed = JSON.parse(stdout);
    if (Array.isArray(parsed)) {
      codes = [...new Set(parsed.map(item => item.code))].sort();
    }
  } catch {
    // A non-JSON report means the run never reached the diagnostics layer.
  }
  return { status, codes, blocking: status === 1 };
}

// The reference's verdict: `pass` is true when no unsafe operation survived its
// own filtering, and the kinds name what it saw.
function runReference(dir) {
  const oldArtifact = JSON.parse(readFileSync(`${dir}/old.json`, 'utf8'));
  const newArtifact = JSON.parse(readFileSync(`${dir}/new.json`, 'utf8'));
  if (!oldArtifact.storageLayout || !newArtifact.storageLayout) {
    return { skipped: 'no storageLayout' };
  }
  const report = oz.getStorageUpgradeReport(
    oldArtifact.storageLayout,
    newArtifact.storageLayout,
    {},
  );
  const kinds = [...new Set(report.ops.map(operation => operation.kind))].sort();
  return { pass: report.pass, kinds, blocking: !report.pass };
}

function describe(result) {
  if (result.skipped) return `skip (${result.skipped})`;
  if (result.kinds === undefined) return `exit ${result.status}`;
  return result.kinds.length === 0 ? 'pass' : result.kinds.join(', ');
}

const cases = readdirSync(fixtures, { withFileTypes: true })
  .filter(entry => entry.isDirectory())
  .map(entry => entry.name)
  .sort();

console.log(`reference: @openzeppelin/upgrades-core ${ozVersion}`);
console.log(`engine:    ${cli}`);
console.log('');

let compared = 0;
const divergences = [];

for (const name of cases) {
  const dir = path.join(fixtures, name);
  if (!existsSync(`${dir}/old.json`) || !existsSync(`${dir}/new.json`)) {
    console.log(`- ${name}: no pair`);
    continue;
  }
  const engine = runEngine(dir);
  let reference;
  try {
    reference = runReference(dir);
  } catch (error) {
    reference = { skipped: `error: ${String(error.message).split('\n')[0]}` };
  }

  const comparable = engine.status !== 2 && reference.blocking !== undefined;
  let verdict = 'n/a';
  if (comparable) {
    compared += 1;
    verdict = engine.blocking === reference.blocking ? 'agree' : 'DIFFER';
  }
  if (verdict === 'DIFFER') {
    divergences.push({ name, engine, reference });
  }

  console.log(
    `- ${name}: engine ${describe(engine)} | reference ${describe(reference)} | ${verdict}`,
  );
}

console.log('');
console.log(`compared ${compared} pairs, ${divergences.length} divergences`);
for (const divergence of divergences) {
  console.log(
    `  ${divergence.name}: engine ${describe(divergence.engine)} vs reference ${describe(divergence.reference)}`,
  );
}
