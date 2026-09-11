// eslint-disable-next-line import/no-extraneous-dependencies
import { describe, expect, it } from 'vitest';
import { startReport, finishReport } from './exportReport.ts';
import { recipe } from './exportRecipe.fixture.ts';

const input = {
  operation: 'cut' as const,
  sources: ['source.mp4'],
  recipe,
  segments: [{ requestedStart: 1, requestedEnd: 2, keyframeCut: true }, { requestedStart: 4, requestedEnd: 6, keyframeCut: true }],
  effective: { mode: 'lossless', streamIds: [0, 1] },
};

describe('export reports', () => {
  it('freezes a detached per-run snapshot before settings and selections change', () => {
    const mutable = structuredClone(input);
    const run = startReport(mutable);
    mutable.recipe.name = 'Changed';
    mutable.sources.push('unexpected.mp4');
    mutable.effective.streamIds.push(2);
    expect(run.recipe.name).toBe('Podcast clip');
    expect(run.sources).toEqual(['source.mp4']);
    expect(run.effective).toEqual({ mode: 'lossless', streamIds: [0, 1] });
    expect(Object.isFrozen(run.effective)).toBe(true);
  });
  it('does not report a skipped existing file as created', () => {
    const report = finishReport(startReport(input), { outputs: [{ path: 'existing.mp4', status: 'skipped_existing' }] });
    expect(report.outputs).toEqual([{ path: 'existing.mp4', status: 'skipped_existing' }]);
    expect(report.status).toBe('succeeded_with_warnings');
  });
  it('retains requested ranges and distinguishes merge cleanup from surviving outputs', () => {
    const report = finishReport(startReport(input), { outputs: [
      { path: 'part.mp4', status: 'deleted_after_merge' }, { path: 'merged.mp4', status: 'created', sizeBytes: 42 },
    ],
    notices: ['Cutpoints may be inaccurate.'] });
    expect(report.segments.map((s) => [s.requestedStart, s.requestedEnd])).toEqual([[1, 2], [4, 6]]);
    expect(report.outputs[1]).toEqual({ path: 'merged.mp4', status: 'created', sizeBytes: 42 });
    expect(report.notices).toContain('Cutpoints may be inaccurate.');
  });
  it('never promotes failed or cancelled runs to success after partial creation', () => {
    const run = startReport(input);
    expect(finishReport(run, { outputs: [{ path: 'part.mp4', status: 'created' }], status: 'cancelled' }).status).toBe('cancelled');
    expect(finishReport(run, { outputs: [{ path: 'part.mp4', status: 'failed', error: 'Disk full' }] }).status).toBe('failed');
    expect(finishReport(run, { outputs: [] }).status).toBe('succeeded_with_warnings');
  });
});
