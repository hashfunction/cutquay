import { appendFile, readFile } from 'node:fs/promises';

await appendFile('licenses.txt', `\n\nFFmpeg Windows runtime: GPL version 3 (--enable-gpl --enable-version3). See Release/ffmpeg-build.json for provenance and incomplete corresponding-source gates.\n\n${await readFile('Release/FFmpeg-LICENSE.txt', 'utf8')}`);
