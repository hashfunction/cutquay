import { open, mkdtemp, stat, lstat, realpath, link, rename, rm, mkdir } from 'node:fs/promises';
import { resolve, dirname, basename, join, isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';
import { exportReportSchema, type ExportReportV1, type ExportItemOutcome } from '../common/exportReport.js';
import type { ExportStage } from '../common/exportOperation.js';

interface Stage { path: string, sources: string[], overwrite: boolean, directory: string, stagingPath: string }
const stages = new Map<string, Stage>();
const isMissing = (error: unknown) => error instanceof Error && 'code' in error && error.code === 'ENOENT';
const isExisting = (error: unknown) => error instanceof Error && 'code' in error && error.code === 'EEXIST';
const optionalStat = async (path: string) => stat(path).catch((error: unknown) => { if (isMissing(error)) return undefined; throw error; });

async function protectSources(path: string, sources: string[]) {
  const destination = await optionalStat(path);
  const resolved = resolve(path);
  for (const source of sources) {
    const sourceStat = await optionalStat(source);
    if (resolved === resolve(source) || (destination && sourceStat && destination.dev === sourceStat.dev && destination.ino === sourceStat.ino)) {
      throw new Error('Export destination would replace a source file');
    }
    const sourceReal = await realpath(source).catch((error: unknown) => { if (isMissing(error)) return undefined; throw error; });
    const parentReal = await realpath(dirname(path));
    if (sourceReal === join(parentReal, basename(path))) throw new Error('Export destination would replace a source file');
  }
}

export async function beginExportFile({ path, sources, overwrite }: { path: string, sources: string[], overwrite: boolean }): Promise<ExportStage> {
  if (!isAbsolute(path) || sources.some((source) => !isAbsolute(source))) throw new Error('Export paths must be absolute');
  await mkdir(dirname(path), { recursive: true });
  await protectSources(path, sources);
  // lstat also treats a dangling symlink as an existing destination.
  const exists = await lstat(path).then(() => true).catch((error: unknown) => { if (isMissing(error)) return false; throw error; });
  if (exists && !overwrite) return { status: 'skipped_existing', path };
  const directory = await mkdtemp(join(dirname(path), '.cutquay-export-'));
  const stagingPath = join(directory, basename(path));
  const token = randomUUID();
  stages.set(token, { path, sources: [...sources], overwrite, directory, stagingPath });
  return { status: 'staged', token, stagingPath };
}

export async function discardExportFile({ token }: { token: string }) {
  const stage = stages.get(token);
  if (stage === undefined) return;
  await rm(stage.directory, { recursive: true, force: true });
  stages.delete(token);
}

export async function commitExportFile({ token }: { token: string }): Promise<ExportItemOutcome> {
  const stage = stages.get(token);
  if (stage === undefined) throw new Error('Unknown export stage');
  try {
    await protectSources(stage.path, stage.sources);
    const file = await open(stage.stagingPath, 'r+');
    let sizeBytes: number;
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size === 0) throw new Error('Export did not produce a nonempty file');
      sizeBytes = info.size;
      await file.sync();
    } finally { await file.close(); }
    if (stage.overwrite) await rename(stage.stagingPath, stage.path);
    else {
      try { await link(stage.stagingPath, stage.path); } catch (error) {
        if (isExisting(error)) return { path: stage.path, status: 'skipped_existing' };
        throw error;
      }
    }
    return { path: stage.path, status: 'created', sizeBytes };
  } finally { await discardExportFile({ token }); }
}

export async function writeExportReport({ path, report }: { path: string, report: ExportReportV1 }) {
  if (!path.endsWith('.cliptern-report.json')) throw new Error('Invalid report extension');
  const validated = exportReportSchema.parse(report);
  const stage = await beginExportFile({ path, sources: validated.sources, overwrite: false });
  if (stage.status !== 'staged') throw new Error('Report already exists');
  try {
    const file = await open(stage.stagingPath, 'wx', 0o600);
    try { await file.writeFile(`${JSON.stringify(validated, undefined, 2)}\n`); await file.sync(); } finally { await file.close(); }
    const outcome = await commitExportFile({ token: stage.token });
    if (outcome.status !== 'created') throw new Error('Report already exists');
  } finally { await discardExportFile({ token: stage.token }); }
}
