import { readFile } from 'node:fs/promises';

const evidence = JSON.parse(await readFile('Release/ffmpeg-build.json', 'utf8')) as { correspondingSourceAuditComplete: boolean, runtimeExecutedOnWindows: boolean };
if (!evidence.correspondingSourceAuditComplete || !evidence.runtimeExecutedOnWindows) {
  throw new Error('Release blocked: FFmpeg corresponding-source inventory and Windows runtime verification are incomplete. See Release/ffmpeg-build.json.');
}
await readFile('licenses.txt');
await readFile('Release/THIRD-PARTY-NOTICES.txt');
