// eslint-disable-next-line import/no-extraneous-dependencies
import { afterEach, expect, it } from 'vitest';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import configureAppIdentity from './appIdentity';
import { recipe } from '../common/exportRecipe.fixture';

const require = createRequire(import.meta.url);
let directory: string | undefined;
afterEach(async () => { if (directory) await rm(directory, { recursive: true, force: true }); directory = undefined; });

function observedApp(root: string, explicitProfile = false) {
  const paths: Record<string, string> = { appData: root, userData: join(root, 'Cliptern'), sessionData: join(root, 'Cliptern') };
  const writes: string[] = [];
  return {
    paths,
    writes,
    name: 'Cliptern',
    modelId: '',
    getPath(key: string) { return paths[key]!; },
    setPath(key: string, value: string) { paths[key] = value; writes.push(key); },
    setName(value: string) { this.name = value; },
    setAppUserModelId(value: string) { this.modelId = value; },
    commandLine: { hasSwitch: (key: string) => key === 'user-data-dir' && explicitProfile },
  };
}

it('retains the established default profile and Windows application identity', () => {
  const app = observedApp('/profiles');
  configureAppIdentity(app, 'win32');
  expect(app.name).toBe('Cliptern');
  expect(app.paths['userData']).toBe(join('/profiles', 'CutQuay'));
  expect(app.paths['sessionData']).toBe(app.paths['userData']);
  expect(app.modelId).toBe('CutQuay');
});

it('preserves explicit isolated browser profiles and leaves config-dir selection to the existing store', () => {
  const app = observedApp('/profiles', true);
  app.paths['userData'] = '/owned/browser'; app.paths['sessionData'] = '/owned/browser';
  configureAppIdentity(app, 'win32');
  expect(app.writes).toEqual([]);
  expect(app.paths['userData']).toBe('/owned/browser');
  expect(app.paths['sessionData']).toBe('/owned/browser');
});

it('loads and persists a pre-rename recipe using the actual electron-store module', async () => {
  directory = await mkdtemp(join(tmpdir(), 'cliptern-profile-test-'));
  const app = observedApp(directory);
  const electronPath = require.resolve('electron');
  const storePath = require.resolve('electron-store');
  const previousElectron = require.cache[electronPath]; const previousStore = require.cache[storePath];
  try {
    // Adapt only the Electron platform boundary; storage/serialization is the real dependency.
    require.cache[electronPath] = { exports: { app } } as NodeJS.Module;
    Reflect.deleteProperty(require.cache, storePath);
    const Store = require('electron-store') as typeof import('electron-store');
    app.paths['userData'] = join(directory, 'CutQuay');
    const original = new Store();
    const saved = [{ ...recipe, id: 'kept', name: 'Weekend highlights' }];
    original.set('exportRecipes', saved);
    const before = await readFile(join(directory, 'CutQuay', 'config.json'), 'utf8');
    app.paths['userData'] = join(directory, 'Cliptern');
    configureAppIdentity(app, 'win32');
    const renamed = new Store();
    expect(renamed.get('exportRecipes')).toEqual(saved);
    expect(await readFile(join(directory, 'CutQuay', 'config.json'), 'utf8')).toBe(before);
    renamed.set('exportRecipes', [...saved, { ...recipe, id: 'new', name: 'Spring excerpt' }]);
    expect(new Store().get('exportRecipes')).toHaveLength(2);
    const custom = new Store({ cwd: join(directory, 'explicit-config') });
    custom.set('exportRecipes', []);
    expect(new Store().get('exportRecipes')).toHaveLength(2);
  } finally {
    if (previousElectron) require.cache[electronPath] = previousElectron; else Reflect.deleteProperty(require.cache, electronPath);
    if (previousStore) require.cache[storePath] = previousStore; else Reflect.deleteProperty(require.cache, storePath);
  }
});
