import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, mkdtemp, rm, copyFile, rename } from 'node:fs/promises';
import { join, basename } from 'node:path';
import { execa } from 'execa';

const pin = JSON.parse(await readFile(new URL('../Release/ffmpeg-build.json', import.meta.url), 'utf8')) as {
  archiveName: string, archiveUrl: string, archiveSha256: string, archiveRoot: string,
  files: { path: string, sha256: string }[],
};
const root = 'ffmpeg/win32-x64';
await mkdir(root, { recursive: true });
const temp = await mkdtemp(join(root, '.download-'));
try {
  const response = await fetch(pin.archiveUrl);
  if (!response.ok) throw new Error(`FFmpeg download failed: HTTP ${response.status}`);
  const archive = Buffer.from(await response.arrayBuffer());
  if (createHash('sha256').update(archive).digest('hex') !== pin.archiveSha256) throw new Error('FFmpeg archive SHA-256 mismatch');
  const archivePath = join(temp, pin.archiveName);
  await writeFile(archivePath, archive, { flag: 'wx' });
  await execa('7z', ['x', archivePath, `-o${temp}`, '-y'], { stdio: 'inherit' });
  // Validate the entire selected inventory before copying any file into the bundle.
  for (const file of pin.files) {
    const bytes = await readFile(join(temp, pin.archiveRoot, file.path));
    if (createHash('sha256').update(bytes).digest('hex') !== file.sha256) throw new Error(`FFmpeg binary mismatch: ${file.path}`);
  }
  const stagedLib = join(temp, 'verified-lib');
  await mkdir(stagedLib);
  for (const file of pin.files) await copyFile(join(temp, pin.archiveRoot, file.path), join(stagedLib, basename(file.path)));
  await copyFile('Release/FFmpeg-LICENSE.txt', join(stagedLib, 'FFmpeg-LICENSE.txt'));
  const lib = join(root, 'lib');
  const previous = join(temp, 'previous-lib');
  let movedPrevious = false;
  try { await rename(lib, previous); movedPrevious = true; } catch (error) {
    if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) throw error;
  }
  try { await rename(stagedLib, lib); } catch (error) {
    if (movedPrevious) await rename(previous, lib);
    throw error;
  }
  console.log(`Verified ${pin.archiveName} and ${pin.files.length} native files. Corresponding-source audit remains a release gate.`);
} finally { await rm(temp, { recursive: true, force: true }); }
