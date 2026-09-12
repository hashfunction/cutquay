import { appendFile, readFile } from 'node:fs/promises';

await appendFile('licenses.txt', `\n\n${await readFile('Release/NATIVE-SOURCES.txt', 'utf8')}\n\n${await readFile('Release/FFmpeg-LICENSE.txt', 'utf8')}`);
