import { afterAll, beforeAll, expect, it, vi } from 'vitest';
import { renderToString } from 'react-dom/server';
import { createRequire } from 'node:module';
import { mkdtemp, readFile, readdir, rm, writeFile, symlink, lstat, link } from 'node:fs/promises';
import { linkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, basename, dirname } from 'node:path';
import { execa } from 'execa';
import * as exportFiles from '../../../main/exportFiles';
import type { ExportItemOutcome } from '../../../common/exportReport';
import { startReport, finishReport } from '../../../common/exportReport';
import { recipe } from '../../../common/exportRecipe.fixture';
import type { FFprobeFormat, FFprobeChapter, FFprobeStream } from '../../../common/ffprobe';

// Only Electron's host boundary is replaced. The production renderer operations,
// native FFmpeg process runner, stream mapping, timestamps and filesystem publish code run unchanged.
vi.mock('electron', () => ({ app: { getVersion: () => 'test', getAppPath: () => '.', isPackaged: false }, clipboard: {}, nativeImage: {} }));
vi.mock('../worker/eval', async () => {
  const { runInNewContext } = await import('node:vm');
  return { default: (code: string, context: object) => runInNewContext(code, context) };
});
vi.mock('../swal', () => ({ errorToast: vi.fn() }));
vi.mock('../../../main/logger', () => ({ default: { info: () => undefined, warn: () => undefined, error: () => undefined } }));

const ffmpegDir = process.env['CUTQUAY_TEST_FFMPEG_DIR'];
let dir: string;
let source: string;
let meta: { streams: FFprobeStream[], format: FFprobeFormat, chapters: FFprobeChapter[] };
let operations: ReturnType<(typeof import('./useFfmpegOperations'))['default']>;
const outcomes: ExportItemOutcome[] = [];
const commands: string[][] = [];
let reports: ReturnType<(typeof import('./useExportReports'))['default']>;
let cancelNextCommand = false;
let beforeNextCommand: (() => void) | undefined;
let attachmentStreams: FFprobeStream[];
let attachmentPath: string;
let renderOperations: (input: string, overwrite: boolean) => void;

beforeAll(async () => {
  if (ffmpegDir === undefined) return;
  dir = await mkdtemp(join(tmpdir(), 'cliptern-media-'));
  source = join(dir, '日本語 fixture.mkv');
  const ffmpeg = await import('../../../main/ffmpeg');
  ffmpeg.setCustomFfPath(ffmpegDir);
  const require = createRequire(import.meta.url);
  const native = await import('../../../main/util');
  vi.stubGlobal('window', {
    process,
    electron: { ...exportFiles, pathExists: native.pathExists },
    require: (name: string) => {
      if (name === '@electron/remote') return { app: { getVersion: () => 'test', getAppPath: () => '.' }, require: () => ({ ...native, ffmpeg, isDev: false }) };
      if (name === 'electron') return { ipcRenderer: {} };
      // Node built-ins are the only remaining imports; this is the Electron host adapter.
      // eslint-disable-next-line import/no-dynamic-require
      return require(name);
    },
  });
  await execa(join(ffmpegDir, 'ffmpeg'), ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=10:duration=6', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=6', '-c:v', 'libx264', '-preset', 'ultrafast', '-g', '10', '-bf', '0', '-c:a', 'pcm_s16le', '-map_metadata', '-1', source]);
  const probed = await ffmpeg.runFfprobe(['-v', 'quiet', '-print_format', 'json', '-show_streams', '-show_format', '-show_chapters', source]);
  meta = JSON.parse(new TextDecoder().decode(probed.stdout));
  const { default: useFfmpegOperations } = await import('./useFfmpegOperations');
  const { default: useExportReports } = await import('./useExportReports');
  renderOperations = (input, overwrite) => {
    function Harness() {
      reports = useExportReports();
      operations = useFfmpegOperations({ filePath: input,
        treatInputFileModifiedTimeAsStart: false,
        treatOutputFileModifiedTimeAsStart: false,
        isEncoding: false,
        lossyMode: undefined,
        enableOverwriteOutput: overwrite,
        outputPlaybackRate: 1,
        cutFromAdjustmentFrames: 0,
        cutToAdjustmentFrames: 0,
        encCustomBitrate: undefined,
        appendLastCommandsLog: () => undefined,
        appendFfmpegCommandLog: (args) => {
          commands.push(args); reports.recordExportCommand(args);
          const callback = beforeNextCommand; beforeNextCommand = undefined; callback?.();
          if (cancelNextCommand) { cancelNextCommand = false; queueMicrotask(() => ffmpeg.abortFfmpegs()); }
        },
        ffmpegHwaccel: 'none',
        onExportPlanned: reports.planExportOutputs,
        onExportOutcome: (outcome) => { outcomes.push(outcome); reports.onExportOutcome(outcome); } });
      return null;
    }
    renderToString(<Harness />);
  };
  renderOperations(source, false);
}, 20000);

afterAll(async () => { if (dir) await rm(dir, { recursive: true, force: true }); vi.unstubAllGlobals(); });

it.skipIf(ffmpegDir === undefined)('cuts, merges and extracts actual generated media with truthful skipped-existing outcomes', async () => {
  const original = await readFile(source);
  const segments = [{ start: 1, end: 2, name: 'one', originalIndex: 0 }, { start: 3, end: 5, name: 'two', originalIndex: 1 }];
  const settings = {
    originalInputPaths: [source],
    outputDir: dir,
    customOutDir: dir,
    segments,
    cutFileNames: ['one.mkv', 'two.mkv'],
    fileDuration: 6,
    rotation: undefined,
    detectedFps: 10,
    onProgress: () => undefined,
    keyframeCut: true,
    copyFileStreams: [{ path: source, streamIds: [0, 1] }],
    allFilesMeta: { [source]: meta },
    outFormat: 'matroska',
    shortestFlag: false,
    ffmpegExperimental: false,
    preserveMetadata: 'default' as const,
    preserveMetadataOnMerge: true,
    preserveMovData: false,
    preserveChapters: true,
    movFastStart: false,
    avoidNegativeTs: 'make_non_negative' as const,
    paramsByFile: new Map(),
    chapters: undefined,
  };
  const cut = await operations.cutMultiple(settings);
  expect(cut.map((item) => item.status)).toEqual(['created', 'created']);
  expect(cut.every((item) => (item.sizeBytes ?? 0) > 1000)).toBe(true);
  const skipped = await operations.cutMultiple(settings);
  expect(skipped.map((item) => item.status)).toEqual(['skipped_existing', 'skipped_existing']);
  const mergedPath = join(dir, 'merged.mkv');
  const merged = await operations.concatCutSegments({ originalInputPaths: [source], customOutDir: dir, outFormat: 'matroska', segmentPaths: cut.map((item) => item.path), ffmpegExperimental: false, onProgress: () => undefined, preserveMovData: false, movFastStart: false, chapterNames: ['one', 'two'], preserveMetadataOnMerge: true, mergedOutFilePath: mergedPath });
  expect(merged.outcome.status).toBe('created');
  const extracted = await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams: meta.streams.filter((stream) => stream.codec_type === 'audio') });
  expect(extracted.map((item) => item.status)).toEqual(['created']);
  const skippedAudio = await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams: meta.streams.filter((stream) => stream.codec_type === 'audio') });
  expect(skippedAudio.map((item) => item.status)).toEqual(['skipped_existing']);
  const report = finishReport(startReport({ operation: 'cut', sources: [source], recipe, segments: segments.map((segment) => ({ requestedStart: segment.start, requestedEnd: segment.end, keyframeCut: true })), effective: { mode: 'lossless' } }), { outputs: outcomes, commands, notices: ['Cutpoints may be inaccurate.'] });
  expect(report.outputs.find((item) => item.path === mergedPath)?.status).toBe('created');
  expect(report.segments.map((segment) => [segment.requestedStart, segment.requestedEnd])).toEqual([[1, 2], [3, 5]]);
  expect(await readFile(source)).toEqual(original);
  expect((await readdir(dir)).some((name) => name.startsWith('.cutquay-export-'))).toBe(false);
}, 20000);

it.skipIf(ffmpegDir === undefined)('does not publish output when real FFmpeg cannot parse its source', async () => {
  const invalid = join(dir, 'invalid.mkv');
  const output = join(dir, 'invalid-output.mkv');
  await writeFile(invalid, 'not a video');
  await expect(operations.concatFiles({ originalInputPaths: [invalid], paths: [invalid], metadataFromPath: invalid, outDir: dir, outPath: output, includeAllStreams: true, streams: meta.streams, outFormat: 'matroska', ffmpegExperimental: false, preserveMovData: false, movFastStart: false, chapters: undefined, preserveMetadataOnMerge: false })).rejects.toThrow();
  expect(outcomes.at(-1)).toMatchObject({ path: output, status: 'failed' });
  expect(await readdir(dir)).not.toContain('invalid-output.mkv');
});

it.skipIf(ffmpegDir === undefined)('protects original media through the real automatic merge and an ancestor directory alias', async () => {
  renderOperations(source, true);
  const { generateCutMergedFileNames } = await import('../util/outputNameTemplate');
  const alias = join(dir, 'ancestor-alias');
  await symlink(dirname(dir), alias, process.platform === 'win32' ? 'junction' : 'dir');
  const aliasDir = join(alias, basename(dir));
  expect((await lstat(aliasDir)).isDirectory()).toBe(true);
  const generated = await generateCutMergedFileNames({
    // eslint-disable-next-line no-template-curly-in-string
    template: '${FILENAME}${EXT}',
    isCustomFormatSelected: true,
    fileFormat: 'matroska',
    sourceFile: { path: source },
    outputDir: aliasDir,
    safeOutputFileName: true,
    maxLabelLength: 100,
    exportCount: 0,
    currentFileExportCount: 0,
    segLabels: ['one', 'two'],
  });
  expect(generated.problems.error).toBeUndefined();
  const original = await readFile(source);
  const run = startReport({ operation: 'cut', sources: [source], recipe, segments: [], effective: {} });
  try {
    let failure: unknown;
    try {
      await operations.concatCutSegments({
        originalInputPaths: run.sources,
        customOutDir: aliasDir,
        outFormat: 'matroska',
        segmentPaths: [join(dir, 'one.mkv'), join(dir, 'two.mkv')],
        ffmpegExperimental: false,
        onProgress: () => undefined,
        preserveMovData: false,
        movFastStart: false,
        chapterNames: undefined,
        preserveMetadataOnMerge: true,
        mergedOutFilePath: join(aliasDir, generated.fileNames[0]!),
      });
    } catch (error) { failure = error; }
    expect((await readFile(source)).equals(original)).toBe(true);
    expect(failure).toBeInstanceOf(Error);
    expect(outcomes.at(-1)).toMatchObject({ status: 'failed' });
  } finally { await writeFile(source, original); }
});

it.skipIf(ffmpegDir === undefined)('publishes the exact attachment payload when native FFmpeg returns its expected Buffer stderr', async () => {
  const attached = join(dir, 'with-attachment.mkv');
  const payload = join(dir, 'note.txt');
  await writeFile(payload, 'attachment review payload');
  await execa(join(ffmpegDir!, 'ffmpeg'), ['-v', 'error', '-i', source, '-map', '0', '-c', 'copy', '-attach', payload, '-metadata:s:t', 'mimetype=text/plain', attached]);
  const ffmpeg = await import('../../../main/ffmpeg');
  const probed = await ffmpeg.runFfprobe(['-v', 'quiet', '-print_format', 'json', '-show_streams', attached]);
  const streams = (JSON.parse(new TextDecoder().decode(probed.stdout)).streams as FFprobeStream[]).filter((stream) => stream.codec_type === 'attachment');
  expect(streams).toHaveLength(1);
  attachmentPath = attached;
  attachmentStreams = streams;
  renderOperations(attached, false);
  const run = reports.beginReport({ operation: 'extract', sources: [attached], recipe, segments: [], effective: {} }, dir);
  const extracted = await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams });
  expect(extracted[0]?.status).toBe('created');
  expect(await readFile(extracted[0]!.path, 'utf8')).toBe('attachment review payload');
  const reportPath = await reports.finishExportReport();
  const report = JSON.parse(await readFile(reportPath!, 'utf8'));
  expect(report).toMatchObject({ runId: run.runId, status: 'succeeded', outputs: [{ path: extracted[0]!.path, status: 'created', sizeBytes: 25 }] });
  reports.beginReport({ operation: 'extract', sources: [attached], recipe, segments: [], effective: {} }, dir);
  const skipped = await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams });
  expect(skipped[0]?.status).toBe('skipped_existing');
  const skippedReportPath = await reports.finishExportReport();
  const skippedReport = JSON.parse(await readFile(skippedReportPath!, 'utf8'));
  expect(skippedReport.status).toBe('succeeded_with_warnings');
  expect(skippedReport.outputs).toEqual([{ path: extracted[0]!.path, status: 'skipped_existing' }]);
  expect(skippedReportPath).not.toBe(reportPath);
});

it.skipIf(ffmpegDir === undefined)('protects external run inputs and their aliases during actual automatic merge', async () => {
  renderOperations(source, true);
  const external = join(dir, 'external-é-source.mkv');
  const hard = join(dir, 'hard-alias.mkv');
  const soft = join(dir, 'file-alias.mkv');
  const directoryAlias = join(dir, 'directory-alias');
  const original = await readFile(source);
  await writeFile(external, original);
  await link(external, hard);
  await symlink(external, soft);
  await symlink(dir, directoryAlias, process.platform === 'win32' ? 'junction' : 'dir');
  const inputs = [source, external];
  const run = reports.beginReport({ operation: 'cut', sources: inputs, recipe, segments: [], effective: {} }, dir);
  inputs.splice(1, 1);
  expect(run.sources).toEqual([source, external]);
  expect(Object.isFrozen(run.sources)).toBe(true);
  const aliases = [external, hard, soft, join(directoryAlias, basename(external))];
  // Check case aliases when the host filesystem treats them as the same file.
  const caseAlias = join(dir, 'EXTERNAL-É-SOURCE.MKV');
  if ((await readFile(caseAlias).catch(() => undefined))?.equals(original)) aliases.push(caseAlias);
  const normalizedAlias = external.normalize('NFD');
  if ((await readFile(normalizedAlias).catch(() => undefined))?.equals(original)) aliases.push(normalizedAlias);
  for (const destination of aliases) {
    await expect(operations.concatCutSegments({ originalInputPaths: run.sources, customOutDir: dir, outFormat: 'matroska', segmentPaths: [join(dir, 'one.mkv'), join(dir, 'two.mkv')], ffmpegExperimental: false, onProgress: () => undefined, preserveMovData: false, movFastStart: false, chapterNames: undefined, preserveMetadataOnMerge: true, mergedOutFilePath: destination })).rejects.toThrow(/source/i);
    expect(await readFile(external)).toEqual(original);
  }
}, 20000);

it.skipIf(ffmpegDir === undefined)('reports a cancelled native attachment and leaves later tracks unattempted while preserving prior output', async () => {
  renderOperations(attachmentPath, true);
  const first = attachmentStreams[0]!;
  const later = { ...first, index: 998 };
  reports.beginReport({ operation: 'extract', sources: [attachmentPath], recipe, segments: [], effective: {} }, dir);
  cancelNextCommand = true;
  let failure: unknown;
  try { await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams: [first, later] }); } catch (error) { failure = error; }
  expect(failure).toBeInstanceOf(Error);
  const reportPath = await reports.finishExportReport(failure);
  const report = JSON.parse(await readFile(reportPath!, 'utf8'));
  expect(report.status).toBe('cancelled');
  expect(report.outputs.map((output: ExportItemOutcome) => output.status)).toEqual(['cancelled', 'not_attempted']);
  expect(await readFile(report.outputs[0].path, 'utf8')).toBe('attachment review payload');
  expect((await readdir(dir)).some((name) => name.startsWith('.cutquay-export-'))).toBe(false);
});

it.skipIf(ffmpegDir === undefined)('rejects a missing native attachment output and records subsequent tracks as unattempted', async () => {
  renderOperations(attachmentPath, false);
  reports.beginReport({ operation: 'extract', sources: [attachmentPath], recipe, segments: [], effective: {} }, dir);
  let failure: unknown;
  try { await operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams: [{ ...attachmentStreams[0]!, index: 999 }, ...attachmentStreams] }); } catch (error) { failure = error; }
  expect(failure).toBeInstanceOf(Error);
  const reportPath = await reports.finishExportReport(failure);
  const report = JSON.parse(await readFile(reportPath!, 'utf8'));
  expect(report.status).toBe('failed');
  expect(report.outputs.map((output: ExportItemOutcome) => output.status)).toEqual(['failed', 'not_attempted']);
  expect(await readFile(report.outputs[0].path).catch(() => undefined)).toBeUndefined();
  expect((await readdir(dir)).some((name) => name.startsWith('.cutquay-export-'))).toBe(false);
});

it.skipIf(ffmpegDir === undefined)('does not suppress an unrelated native FFmpeg failure during attachment extraction', async () => {
  renderOperations(join(dir, 'invalid.mkv'), false);
  await expect(operations.extractStreams({ originalInputPaths: [source, ...(attachmentPath ? [attachmentPath] : [])], customOutDir: dir, streams: attachmentStreams })).rejects.toThrow();
  expect(outcomes.at(-1)?.status).toBe('failed');
  expect(await readFile(outcomes.at(-1)!.path).catch(() => undefined)).toBeUndefined();
});

it.skipIf(ffmpegDir === undefined)('rechecks original source aliases at publication after native automatic merge has run', async () => {
  renderOperations(source, true);
  const destination = join(dir, 'late-alias.mkv');
  const original = await readFile(source);
  const run = reports.beginReport({ operation: 'cut', sources: [source], recipe, segments: [], effective: {} }, dir);
  beforeNextCommand = () => linkSync(source, destination);
  await expect(operations.concatCutSegments({ originalInputPaths: run.sources, customOutDir: dir, outFormat: 'matroska', segmentPaths: [join(dir, 'one.mkv'), join(dir, 'two.mkv')], ffmpegExperimental: false, onProgress: () => undefined, preserveMovData: false, movFastStart: false, chapterNames: undefined, preserveMetadataOnMerge: true, mergedOutFilePath: destination })).rejects.toThrow(/source/i);
  expect(outcomes.at(-1)).toMatchObject({ path: destination, status: 'failed' });
  expect(await readFile(source)).toEqual(original);
  expect(await readFile(destination)).toEqual(original);
  expect((await readdir(dir)).some((name) => name.startsWith('.cutquay-export-'))).toBe(false);
});
