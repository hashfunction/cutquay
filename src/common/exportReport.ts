import { z } from 'zod';
import { exportRecipeSchema } from './exportRecipe.ts';

export const exportOutcomeSchema = z.object({
  path: z.string(),
  status: z.enum(['created', 'skipped_existing', 'deleted_after_merge', 'failed', 'cancelled', 'not_attempted']),
  sizeBytes: z.number().nonnegative().optional(),
  error: z.string().optional(),
});
export type ExportItemOutcome = z.infer<typeof exportOutcomeSchema>;
const reportInputSchema = z.object({
  operation: z.enum(['cut', 'merge', 'extract']),
  sources: z.array(z.string()),
  recipe: exportRecipeSchema,
  segments: z.array(z.object({ requestedStart: z.number().nonnegative(), requestedEnd: z.number().nonnegative(), keyframeCut: z.boolean() })),
  effective: z.record(z.string(), z.unknown()),
});
export const exportReportSchema = reportInputSchema.extend({
  version: z.literal(1),
  runId: z.uuid(),
  startedAt: z.iso.datetime(),
  finishedAt: z.iso.datetime(),
  status: z.enum(['succeeded', 'succeeded_with_warnings', 'cancelled', 'failed']),
  outputs: z.array(exportOutcomeSchema),
  commands: z.array(z.array(z.string())),
  warnings: z.array(z.string()),
  notices: z.array(z.string()),
  error: z.string().optional(),
});
export type ExportReportV1 = z.infer<typeof exportReportSchema>;

function freeze<T>(value: T): T {
  if (typeof value === 'object' && value !== null) {
    Object.values(value).forEach((child) => freeze(child));
    Object.freeze(value);
  }
  return value;
}
export function startReport(input: z.infer<typeof reportInputSchema>) {
  return freeze({ ...structuredClone(reportInputSchema.parse(input)), version: 1 as const, runId: globalThis.crypto.randomUUID(), startedAt: new Date().toISOString() });
}
export type ExportRun = ReturnType<typeof startReport>;

export function finishReport(run: ExportRun, result: {
  outputs: ExportItemOutcome[], commands?: string[][], warnings?: string[], notices?: string[],
  status?: 'failed' | 'cancelled', error?: string,
}): ExportReportV1 {
  const warnings = result.warnings ?? [];
  let status: ExportReportV1['status'] = 'succeeded';
  if (warnings.length > 0 || result.outputs.length === 0 || result.outputs.some((o) => o.status === 'skipped_existing' || o.status === 'not_attempted')) status = 'succeeded_with_warnings';
  if (result.outputs.some((o) => o.status === 'cancelled')) status = 'cancelled';
  if (result.outputs.some((o) => o.status === 'failed')) status = 'failed';
  if (result.status !== undefined) status = result.status;
  return freeze(exportReportSchema.parse({
    ...run,
    finishedAt: new Date().toISOString(),
    status,
    outputs: result.outputs,
    commands: result.commands ?? [],
    warnings,
    notices: result.notices ?? [],
    ...(result.error !== undefined ? { error: result.error } : {}),
  }));
}
