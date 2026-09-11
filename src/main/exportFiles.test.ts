// eslint-disable-next-line import/no-extraneous-dependencies
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, writeFile, readFile, readdir, rm, link, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beginExportFile, commitExportFile, discardExportFile, writeExportReport } from './exportFiles.ts';
import { exportOutput } from '../common/exportOperation.js';
import type { ExportItemOutcome } from '../common/exportReport.js';
import { startReport, finishReport } from '../common/exportReport.js';
import { recipe } from '../common/exportRecipe.fixture.js';

let dir: string;
beforeEach(async () => { dir = await mkdtemp(join(tmpdir(), 'cutquay-test-')); });
afterEach(async () => { await rm(dir, { recursive: true, force: true }); });
const io = { beginExportFile, commitExportFile, discardExportFile };

describe('atomic export publication with real filesystem fixtures', () => {
  it('preserves an existing destination when overwrite is disabled', async () => {
    const path = join(dir, '音声.mp4');
    await writeFile(path, 'original');
    const outcomes: ExportItemOutcome[] = [];
    await exportOutput({ io, path, sources: [], overwrite: false, onOutcome: (o) => outcomes.push(o), run: async () => { throw new Error('Must not run'); } });
    expect(await readFile(path, 'utf8')).toBe('original');
    expect(outcomes).toEqual([{ path, status: 'skipped_existing' }]);
  });
  it('closes the existence-check race without replacing another writer', async () => {
    const path = join(dir, 'race.mp4');
    const stage = await beginExportFile({ path, sources: [], overwrite: false });
    expect(stage.status).toBe('staged');
    if (stage.status !== 'staged') throw new Error('Expected stage');
    await writeFile(stage.stagingPath, 'our bytes');
    await writeFile(path, 'other writer');
    expect(await commitExportFile({ token: stage.token })).toEqual({ path, status: 'skipped_existing' });
    expect(await readFile(path, 'utf8')).toBe('other writer');
    expect(await readdir(dir)).toEqual(['race.mp4']);
  });
  it('publishes only completed output and removes its own partial staging file on failure', async () => {
    const path = join(dir, 'failed.mkv');
    const outcomes: ExportItemOutcome[] = [];
    await expect(exportOutput({ io,
      path,
      sources: [],
      overwrite: false,
      onOutcome: (o) => outcomes.push(o),
      run: async (staging) => {
        await writeFile(staging, 'partial');
        throw new Error('Disk full');
      } })).rejects.toThrow('Disk full');
    expect(outcomes[0]).toMatchObject({ path, status: 'failed', error: 'Disk full' });
    expect(await readdir(dir)).toEqual([]);
  });
  it('preserves old output on cancellation even with explicit overwrite', async () => {
    const path = join(dir, 'cancelled.mkv');
    await writeFile(path, 'old');
    const outcomes: ExportItemOutcome[] = [];
    await expect(exportOutput({ io,
      path,
      sources: [],
      overwrite: true,
      onOutcome: (o) => outcomes.push(o),
      run: async (staging) => {
        await writeFile(staging, 'partial');
        throw Object.assign(new Error('Cancelled'), { isCanceled: true });
      } })).rejects.toThrow('Cancelled');
    expect(outcomes[0]?.status).toBe('cancelled');
    expect(await readFile(path, 'utf8')).toBe('old');
  });
  it('refuses source paths, hard links and symlinks even with overwrite enabled', async () => {
    const source = join(dir, 'source.mp4');
    const hard = join(dir, 'hard.mp4');
    const soft = join(dir, 'soft.mp4');
    await writeFile(source, 'source');
    await link(source, hard);
    await symlink(source, soft);
    for (const path of [source, hard, soft]) {
      await expect(beginExportFile({ path, sources: [source], overwrite: true })).rejects.toThrow(/source/i);
    }
    expect(await readFile(source, 'utf8')).toBe('source');
  });
  it('rejects empty completed staging output without replacing prior bytes', async () => {
    const path = join(dir, 'empty.bin');
    await writeFile(path, 'prior bytes');
    const outcomes: ExportItemOutcome[] = [];
    await expect(exportOutput({ io, path, sources: [], overwrite: true, onOutcome: (outcome) => outcomes.push(outcome), run: async (staging) => { await writeFile(staging, ''); } })).rejects.toThrow();
    expect(outcomes[0]?.status).toBe('failed');
    expect(await readFile(path, 'utf8')).toBe('prior bytes');
    expect(await readdir(dir)).toEqual(['empty.bin']);
  });
  it('commits explicit overwrite atomically and reports verified size', async () => {
    const path = join(dir, 'replace.mkv');
    await writeFile(path, 'old');
    const outcome = await exportOutput({ io, path, sources: [], overwrite: true, run: async (staging) => { await writeFile(staging, 'complete'); } });
    expect(outcome).toEqual({ path, status: 'created', sizeBytes: 8 });
    expect(await readFile(path, 'utf8')).toBe('complete');
    expect(await readdir(dir)).toEqual(['replace.mkv']);
  });
  it('writes a valid immutable report without replacing an existing report', async () => {
    const path = join(dir, 'result.cutquay-report.json');
    const report = finishReport(startReport({ operation: 'cut', recipe, sources: [], segments: [], effective: {} }), { outputs: [] });
    await writeExportReport({ path, report });
    expect(JSON.parse(await readFile(path, 'utf8')).runId).toBe(report.runId);
    await expect(writeExportReport({ path, report })).rejects.toThrow();
    expect(await readdir(dir)).toEqual(['result.cutquay-report.json']);
  });
});
