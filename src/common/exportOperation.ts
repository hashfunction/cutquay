import type { ExportItemOutcome } from './exportReport.ts';

export type ExportStage = { status: 'staged', token: string, stagingPath: string } | { status: 'skipped_existing', path: string };
export interface ExportFileIo {
  beginExportFile: (input: { path: string, sources: string[], overwrite: boolean }) => Promise<ExportStage>,
  commitExportFile: (input: { token: string }) => Promise<ExportItemOutcome>,
  discardExportFile: (input: { token: string }) => Promise<void>,
}
export function isExportCancelled(error: unknown) {
  return error instanceof Error && (error.name === 'AbortError' || ('isCanceled' in error && error.isCanceled === true) || ('isTerminated' in error && error.isTerminated === true) || ('isForcefullyTerminated' in error && error.isForcefullyTerminated === true));
}
export async function exportOutput({ io, path, sources, overwrite, run, onOutcome }: {
  io: ExportFileIo, path: string, sources: string[], overwrite: boolean,
  run: (stagingPath: string) => Promise<unknown>, onOutcome?: ((outcome: ExportItemOutcome) => void) | undefined,
}): Promise<ExportItemOutcome> {
  let stage: ExportStage | undefined;
  try {
    stage = await io.beginExportFile({ path, sources, overwrite });
    const outcome = stage.status === 'skipped_existing' ? { path, status: 'skipped_existing' as const }
      : await (async () => {
        if (stage.status !== 'staged') throw new Error('Missing export stage');
        await run(stage.stagingPath);
        return io.commitExportFile({ token: stage.token });
      })();
    onOutcome?.(outcome);
    return outcome;
  } catch (error) {
    onOutcome?.({ path, status: isExportCancelled(error) ? 'cancelled' : 'failed', error: error instanceof Error ? error.message : String(error) });
    throw error;
  } finally {
    if (stage?.status === 'staged') await io.discardExportFile({ token: stage.token });
  }
}
