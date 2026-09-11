import { useCallback, useRef } from 'react';
import { startReport, finishReport, type ExportRun, type ExportItemOutcome } from '../../../common/exportReport';
import { isExportCancelled } from '../../../common/exportOperation';
import mainApi from '../mainApi';
import { errorToast } from '../swal';
import { readFileSize } from '../util';

interface ActiveReport {
  run: ExportRun, outputs: Map<string, ExportItemOutcome>, planned: Set<string>, commands: string[][],
  warnings: Set<string>, notices: Set<string>, directory: string,
}
const { join, basename } = window.require('node:path');

export default function useExportReports() {
  const active = useRef<ActiveReport | undefined>(undefined);
  const beginReport = useCallback((input: Parameters<typeof startReport>[0], directory: string, warnings = new Set<string>(), notices = new Set<string>()) => {
    const run = startReport(input);
    active.current = { run, directory, warnings, notices, outputs: new Map(), planned: new Set(), commands: [] };
    return run;
  }, []);
  const onExportOutcome = useCallback((outcome: ExportItemOutcome) => {
    active.current?.outputs.set(outcome.path, { ...outcome });
    if (outcome.status === 'skipped_existing') active.current?.warnings.add(`Skipped existing output: ${outcome.path}`);
  }, []);
  const planExportOutputs = useCallback((paths: string[]) => paths.forEach((path) => active.current?.planned.add(path)), []);
  const recordExportCommand = useCallback((args: string[]) => {
    active.current?.commands.push(args.map((arg, i) => (i > 0 && ['-headers', '-cookies', '-http_proxy', '-authorization'].includes(args[i - 1]!) ? '[redacted]' : arg)));
  }, []);
  const finishExportReport = useCallback(async (error?: unknown) => {
    const report = active.current;
    if (report === undefined) return undefined;
    active.current = undefined;
    let status: 'failed' | 'cancelled' | undefined = error === undefined ? undefined : (isExportCancelled(error) ? 'cancelled' : 'failed');
    for (const path of report.planned) {
      if (!report.outputs.has(path)) report.outputs.set(path, { path, status: 'not_attempted' });
    }
    for (const outcome of report.outputs.values()) {
      if (outcome.status === 'created') {
        try { outcome.sizeBytes = await readFileSize(outcome.path); } catch (err) {
          outcome.status = 'failed';
          outcome.error = `Published output could not be verified: ${String(err)}`;
          if (status !== 'cancelled') status = 'failed';
        }
      }
    }
    const finished = finishReport(report.run, {
      outputs: [...report.outputs.values()],
      commands: report.commands,
      warnings: [...report.warnings],
      notices: [...report.notices],
      ...(status !== undefined ? { status } : {}),
      ...(error !== undefined ? { error: error instanceof Error ? error.message : String(error) } : {}),
    });
    const primaryOutput = finished.outputs.find((item) => item.status === 'created')?.path;
    const filename = `${basename(primaryOutput ?? report.run.sources[0] ?? 'export')}.${report.run.runId}.cutquay-report.json`;
    const path = join(report.directory, filename);
    try {
      await mainApi.writeExportReport({ path, report: finished });
      return path;
    } catch (err) {
      const warning = `Export report could not be saved: ${String(err)}`;
      report.warnings.add(warning);
      errorToast(warning);
      return undefined;
    }
  }, []);
  return { beginReport, onExportOutcome, planExportOutputs, recordExportCommand, finishExportReport };
}
