// Copyright 2026 Trieflow LLC. MIT. CI-only pinned runtime acquisition.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { downloadArtifact } = require('@electron/get');
const { pipeline } = require('node:stream/promises');
const { createWriteStream, createReadStream } = require('node:fs');
async function main() {
  if (process.platform !== 'win32' || process.env.CI !== 'true') throw Error('Requires disposable Windows CI');
  const output = path.resolve(process.argv[2]);
  const version = require('../../package.json').devDependencies.electron;
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw Error('Exact Electron version is required');
  await fs.mkdir(output); // new directory only
  const name = `electron-v${version}-win32-x64.zip`;
  const base = `https://github.com/electron/electron/releases/download/v${version}/`;
  const response = await fetch(base + 'SHASUMS256.txt');
  if (!response.ok) throw Error(`Electron checksums HTTP ${response.status}`);
  const checksums = await response.text();
  const lines = checksums.split(/\r?\n/).map(line => /^([0-9a-f]{64}) [ *](.+)$/.exec(line)).filter(Boolean);
  const matches = lines.filter(line => line[2] === name);
  if (matches.length !== 1) throw Error('Exact Electron checksum missing/ambiguous');
  const cached = await downloadArtifact({ version, platform:'win32', arch:'x64', artifactName:'electron',
    checksums: { [name]:matches[0][1] }, mirrorOptions: {
      mirror:'https://github.com/electron/electron/releases/download/', customDir:`v${version}`, customFilename:name,
    } });
  await pipeline(createReadStream(cached), createWriteStream(path.join(output,name), {flags:'wx'}));
  const hash = crypto.createHash('sha256');
  for await (const chunk of createReadStream(path.join(output,name))) hash.update(chunk);
  if (hash.digest('hex') !== matches[0][1]) throw Error('Copied Electron archive checksum differs from official release');
  await fs.writeFile(path.join(output,'SHASUMS256.txt'),checksums,{flag:'wx'});
  console.log(`Retained checksum-verified Electron ${version} input; corresponding-source review remains open.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
