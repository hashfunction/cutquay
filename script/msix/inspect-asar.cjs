// Copyright 2026 Trieflow LLC. MIT. Qualification only; never executes application code.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const asar = require('@electron/asar');
const [source, release, artwork] = process.argv.slice(2);
async function main() {
const archive = path.join(release, 'resources/app.asar');
const digest = data => ({ bytes: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') });
const regular = file => {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) throw Error(`Expected regular ASAR/source file: ${file}`);
  return fs.readFileSync(file);
};
const sharp = require('sharp');
const generatedArtwork = await sharp(regular(path.join(source,'src/renderer/src/icon.svg'))).png().resize(512,512,{fit:sharp.fit.contain,background:{r:0,g:0,b:0,alpha:0}}).toBuffer();
if (!generatedArtwork.equals(regular(artwork))) throw Error('Artwork does not match actual original SVG generator output');
const sourcePackage = JSON.parse(regular(path.join(source, 'package.json')));
if (sourcePackage.name !== 'cutquay' || sourcePackage.productName !== 'CutQuay' || sourcePackage.version !== '1.0.0' || sourcePackage.main !== './out/main/index.js') throw Error('Unexpected source application metadata');
const files = {};
function visit(directory, prefix = '') {
  for (const [name, node] of Object.entries(directory.files)) {
    if (!name || /[\\/\x00-\x1f]/.test(name) || name === '.' || name === '..' || node.link) throw Error('Unsafe ASAR entry or link');
    const relative = prefix + name;
    if (node.files) visit(node, relative + '/');
    else {
      if (!Number.isSafeInteger(node.size) || node.size < 0) throw Error('Invalid ASAR entry size');
      files[relative] = { size: node.size, unpacked: node.unpacked === true };
    }
  }
}
visit(asar.getRawHeader(archive).header);
const packaged = JSON.parse(asar.extractFile(archive, 'package.json', false));
for (const field of ['name','productName','version','main']) {
  if (packaged[field] !== sourcePackage[field]) throw Error(`ASAR metadata mismatch: ${field}`);
}
const sourceFiles = {};
const notices = ['LICENSE','NOTICE','licenses.txt','Release/THIRD-PARTY-NOTICES.txt','Release/ffmpeg-build.json','Release/FFmpeg-LICENSE.txt'];
for (const relative of [...notices, 'out/main/index.js','out/renderer/index.html']) {
  if (!files[relative] || files[relative].unpacked) throw Error(`ASAR required file missing/unpacked: ${relative}`);
  const actual = asar.extractFile(archive, relative, false);
  const expected = regular(path.join(source, relative));
  if (!actual.equals(expected)) throw Error(`ASAR differs from source notice/build output: ${relative}`);
  sourceFiles[relative] = digest(expected);
}
for (const relative of ['package.json','yarn.lock','src/renderer/src/icon.svg']) sourceFiles[relative] = digest(regular(path.join(source,relative)));
const unpacked = {};
for (const [relative, info] of Object.entries(files)) {
  if (info.unpacked) {
    const name = 'resources/app.asar.unpacked/' + relative;
    const bytes = regular(path.join(release,name));
    if (bytes.length !== info.size) throw Error(`ASAR unpacked size mismatch: ${name}`);
    unpacked[name] = digest(bytes);
  }
}
console.log(JSON.stringify({ sourceFiles, asarFiles: files, unpacked, notices,
  electronVersion: sourcePackage.devDependencies.electron,
  expectedWindowTitle: sourcePackage.productName,
  expectedUnpackedWindowTitle: `${sourcePackage.productName} ${sourcePackage.version}`,
  titleReason: 'process.windowsStore is true for MSIX; src/renderer/src/util.ts omits version for packaged startup',
  asar: digest(regular(archive)) }));

}
main().catch(error => { console.error(error); process.exitCode = 1; });
