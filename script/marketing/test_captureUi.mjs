/* eslint-disable no-param-reassign, unicorn/filename-case -- Mutates detached refusal fixtures; filename is the established workflow entry. */
import assert from 'node:assert/strict';
import test from 'node:test';
import { validateScene, validateExport } from './captureUi.mjs';

test('real rendered media must be paused, decoded, exact-path, sufficiently large and unobscured', () => {
  const view = { width: 1456, height: 961, devicePixelRatio: 1, visibleToast: false, video: [{ src: 'file:///C:/demo/Spring.webm', readyState: 4, error: null, duration: 464.141, currentTime: 390, paused: true, seeking: false, videoWidth: 2048, videoHeight: 858 }] };
  validateScene(view, String.raw`C:\demo\Spring.webm`, 390, 464.141);
  for (const mutation of [(v) => { v.width = 784; }, (v) => { v.visibleToast = true; }, (v) => { v.video[0].paused = false; }, (v) => { v.video[0].paused = 'false'; }, (v) => { v.video[0].src = 'file:///C:/other.webm'; }, (v) => { v.video[0].currentTime = 0; }, (v) => { v.video[0].videoWidth = 0; }]) {
    const changed = structuredClone(view); mutation(changed); assert.throws(() => validateScene(changed, String.raw`C:\demo\Spring.webm`, 390, 464.141));
  }
});
test('export evidence must bind actual trim, saved recipe, non-overwrite and output', () => {
  const recipe = { id: 'customer', name: 'Festival teaser - Original quality', outFormat: 'webm', exportMode: 'separate', keyframeCut: true, enableOverwriteOutput: false };
  const report = { version: 1, status: 'succeeded', operation: 'cut', sources: [String.raw`C:\demo\Spring.webm`], effective: { mode: 'lossless' }, segments: [{ requestedStart: 376, requestedEnd: 400, keyframeCut: true }], recipe, outputs: [{ path: String.raw`C:\demo\Teaser.webm`, status: 'created', sizeBytes: 123 }] };
  validateExport(report, { exportRecipes: [recipe] }, report.sources[0], 123);
  for (const mutation of [(r) => { r.segments[0].requestedEnd = 5; }, (r) => { r.recipe.enableOverwriteOutput = true; }, (r) => { r.recipe.name = 'Original CI'; }, (r) => { [r.outputs[0].path] = r.sources; }, (r) => { r.outputs[0].sizeBytes = 1; }]) {
    const changed = structuredClone(report); mutation(changed); assert.throws(() => validateExport(changed, { exportRecipes: [changed.recipe] }, report.sources[0], 123));
  }
});
