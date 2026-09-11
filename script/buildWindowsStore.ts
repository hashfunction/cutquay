import { readFile } from 'node:fs/promises';
import { execa } from 'execa';

if (process.platform !== 'win32') throw new Error('Store packages require an actual Windows build host');
const configPath = process.env['CUTQUAY_STORE_CONFIG'];
if (!configPath) throw new Error('Set CUTQUAY_STORE_CONFIG to a reviewed electron-builder JSON config with the Trieflow-owned Partner Center identity');
const config = JSON.parse(await readFile(configPath, 'utf8')) as { appx?: { identityName?: string, publisher?: string, applicationId?: string, publisherDisplayName?: string } };
const { appx } = config;
if (!appx?.identityName || !appx.publisher || !appx.applicationId || appx.publisherDisplayName !== 'Trieflow LLC') throw new Error('A complete Trieflow-owned Store identity is required');
if (/mifi|losslesscut|2C479316-22A8-4D63-BC38-F0FB9AB0B974/i.test(JSON.stringify(config))) throw new Error('Upstream Store identity is prohibited');
await execa('yarn', ['check-release-licenses'], { stdio: 'inherit' });
await execa('yarn', ['build'], { stdio: 'inherit' });
await execa('yarn', ['electron-builder', '--win', 'appx', '--x64', '--config', configPath], { stdio: 'inherit' });
