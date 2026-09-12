// Copyright 2026 Trieflow LLC. MIT. External screenshot-only input driver.
import assert from 'node:assert/strict';
import { open, readFile, readdir, lstat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { Cdp, inspectDom, validateEndpoint, validateTarget, writeNewJson } from '../msix/workflowUi.mjs';

const canonical = (value) => path.win32.normalize(value).toLowerCase();
const mediaPath = (src) => canonical(decodeURIComponent(new URL(src).pathname).replace(/^\/([A-Za-z]:)/, '$1'));
const recipeName = 'Festival teaser - Original quality';

async function hash(file) { const stat = await lstat(file); assert(stat.isFile() && !stat.isSymbolicLink()); const bytes = await readFile(file); assert.equal(bytes.length, stat.size); return { bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }; }

export function validateScene(view, media, time, duration) {
  assert(view.width >= 1400 && view.height >= 850 && view.width <= 2000 && view.height <= 1400, 'Actual renderer is too small or oversized');
  assert.equal(view.devicePixelRatio, 1, 'Capture requires verified 100% display scale');
  assert.equal(view.visibleToast, false, 'A notification obscures the scene');
  const videos = view.video.filter((v) => mediaPath(v.src) === canonical(media)); assert.equal(videos.length, 1, 'Exactly one actual media element required');
  const v = videos[0]; assert(v.readyState >= 2 && !v.error && v.paused === true && v.seeking === false && v.videoWidth === 2048 && v.videoHeight === 858, 'Actual film frame is not decoded and paused');
  assert(Math.abs(v.currentTime - time) < 0.15 && Math.abs(v.duration - duration) < 0.15, 'Actual playback position/duration differs');
  return v;
}

export function validateExport(report, config, source, size) {
  assert.equal(report.version, 1); assert(['succeeded', 'succeeded_with_warnings'].includes(report.status)); assert.equal(report.operation, 'cut');
  assert.deepEqual(report.sources, [source]); assert.equal(report.effective.mode, 'lossless');
  assert.deepEqual(report.segments, [{ requestedStart: 376, requestedEnd: 400, keyframeCut: true }]);
  assert.equal(report.recipe.name, recipeName); assert.notEqual(report.recipe.id, 'current');
  for (const [k, v] of Object.entries({ outFormat: 'webm', exportMode: 'separate', keyframeCut: true, enableOverwriteOutput: false }))assert.equal(report.recipe[k], v);
  assert.deepEqual(config.exportRecipes.filter((r) => r.id === report.recipe.id), [report.recipe]);
  assert.equal(report.outputs.length, 1); const output = report.outputs[0]; assert.equal(output.status, 'created'); assert.equal(output.sizeBytes, size); assert(size > 0);
  assert.equal(canonical(path.win32.dirname(output.path)), canonical(path.win32.dirname(source))); assert.notEqual(canonical(output.path), canonical(source)); assert.equal(path.win32.extname(output.path), '.webm');
  return output.path;
}

// Read-only observation of the live renderer. No app state, styles, markup,
// video time or pixels are written by Runtime.evaluate.
function inspectCapture() {
  const visible = (e) => { const r = e.getBoundingClientRect(); const s = globalThis.getComputedStyle(e); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  return { width: globalThis.innerWidth,
    height: globalThis.innerHeight,
    devicePixelRatio: globalThis.devicePixelRatio,
    visibleToast: [...globalThis.document.querySelectorAll('.swal2-toast')].some((element) => visible(element)),
    thumbnails: [...globalThis.document.querySelectorAll('img')].filter((e) => visible(e) && e.complete && e.naturalWidth > 50 && e.src.startsWith('blob:')).length,
    video: [...globalThis.document.querySelectorAll('video')].map((v) => ({ src: v.currentSrc || v.src, duration: v.duration, currentTime: v.currentTime, paused: v.paused, seeking: v.seeking, readyState: v.readyState, error: v.error?.message ?? null, videoWidth: v.videoWidth, videoHeight: v.videoHeight })) };
}

async function run(request) {
  const socket = new globalThis.WebSocket(validateEndpoint(request.endpoint, request.port));
  await new Promise((resolve, reject) => { const timer = setTimeout(() => { socket.close(); reject(new Error('CDP connection timed out')); }, 10000); socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true }); socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('CDP connection failed')); }, { once: true }); });
  const client = new Cdp(socket); const steps = []; let primary;
  const result = { schema_version: 1,
    purpose: 'marketing screenshots only',
    consumer_acceptance: false,
    phase: request.phase,
    nonce: request.nonce,
    capture_source_commit: request.captureSource,
    qualified_source_commit: request.packageSource,
    package_full_name: request.packageFullName,
    process_id: request.processId,
    steps,
    captured: false };
  try {
    const browsers = (await client.call('SystemInfo.getProcessInfo')).processInfo.filter((p) => p.type === 'browser'); assert.equal(browsers.length, 1); assert.equal(browsers[0].id, request.processId);
    const target = validateTarget((await client.call('Target.getTargets')).targetInfos, request.rendererPath);
    const { sessionId } = await client.call('Target.attachToTarget', { targetId: target.targetId, flatten: true });
    const call = (method, params) => client.call(method, params, sessionId);
    await call('Runtime.enable', {}); await call('Page.enable', {});
    const evaluate = async (fn, arg) => { const r = await call('Runtime.evaluate', { expression: `(${fn.toString()})(${JSON.stringify(arg) ?? ''})`, returnByValue: true }); assert(!r.exceptionDetails, JSON.stringify(r.exceptionDetails)); return r.result.value; };
    const inspect = (q) => evaluate(inspectDom, q); const view = () => evaluate(inspectCapture);
    const wait = async (fn, label) => { const deadline = Date.now() + 45000; let last; while (Date.now() < deadline) { assert.equal(client.exceptions.length, 0, 'Unhandled renderer exception'); try { const value = await fn(); if (value) return value; } catch (error) { last = error; } await delay(200); } throw new Error(`UI timeout ${label}: ${last?.message ?? 'not ready'}`); };
    const control = (q) => wait(() => inspect({ exposedOnly: true, ...q }), JSON.stringify(q));
    const key = async (name, code, virtual, modifiers = 0) => { await call('Input.dispatchKeyEvent', { type: name === 'Enter' ? 'keyDown' : 'rawKeyDown', ...(name === 'Enter' ? { text: '\r', unmodifiedText: '\r' } : {}), key: name, code, windowsVirtualKeyCode: virtual, modifiers }); await call('Input.dispatchKeyEvent', { type: 'keyUp', key: name, code, windowsVirtualKeyCode: virtual, modifiers }); };
    const click = async (q) => { const p = await control(q); await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: p.x, y: p.y, button: 'left', clickCount: 1 }); await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: p.x, y: p.y, button: 'left', clickCount: 1 }); steps.push({ action: 'click', query: q }); };
    const input = async (selector, text, submit = false) => { await click({ selector }); await key('a', 'KeyA', 65, 2); await call('Input.insertText', { text }); await key(submit ? 'Enter' : 'Tab', submit ? 'Enter' : 'Tab', submit ? 13 : 9); steps.push({ action: 'input', selector, text }); };
    const select = async (selector, value) => { const p = await control({ selector }); const enabled = p.options.filter((o) => !o.disabled); const index = enabled.findIndex((o) => o.value === value); assert(index !== -1); await click({ selector }); await key('Home', 'Home', 36); for (let i = 0; i < index; i += 1) await key('ArrowDown', 'ArrowDown', 40); await key('Enter', 'Enter', 13); await wait(async () => (await inspect({ selector })).value === value, 'selected option'); steps.push({ action: 'select', selector, value }); };
    const seek = async (time) => { await key('g', 'KeyG', 71); await control({ selector: '[role="dialog"] input' }); const seconds = time % 60; const text = `00:${String(Math.floor(time / 60)).padStart(2, '0')}:${seconds.toFixed(3).padStart(6, '0')}`; await input('[role="dialog"] input', text, true); await wait(async () => { const v = (await view()).video[0]; return v && !v.seeking && Math.abs(v.currentTime - time) < 0.15; }, 'visible seek completed'); };
    const snapshot = async (name, time, duration) => {
      const observed = await wait(async () => { const v = await view(); validateScene(v, request.media, time, duration); return v; }, 'unobscured decoded scene');
      const dom = await inspect({ kind: 'snapshot' }); await writeNewJson(path.join(request.evidence, `${name}.json`), { ...observed, dom });
      const captured = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false, fromSurface: true });
      const bytes = Buffer.from(captured.data, 'base64'); assert(bytes.length < 16000000); assert.equal(bytes.readUInt32BE(16), observed.width); assert.equal(bytes.readUInt32BE(20), observed.height);
      const handle = await open(path.join(request.evidence, `${name}.png`), 'wx'); try { await handle.writeFile(bytes); } finally { await handle.close(); }
      // Pause input while PowerShell verifies this exact window on the real
      // desktop and takes a second, unedited native-window capture.
      await writeNewJson(path.join(request.evidence, `${name}-native-request.json`), { nonce: request.nonce, process_id: request.processId, name });
      await (await open(path.join(request.evidence, `${name}-native-request.ready`), 'wx')).close();
      await wait(async () => { try { await lstat(path.join(request.evidence, `${name}-native-complete.ready`)); const ack = JSON.parse(await readFile(path.join(request.evidence, `${name}-native-complete.json`), 'utf8')); assert.equal(ack.nonce, request.nonce); assert.equal(ack.process_id, request.processId); assert.equal(ack.name, name); return ack; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } }, 'native capture acknowledgement');
      steps.push({ action: 'actual-screenshot', name, sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, width: observed.width, height: observed.height });
    };
    const before = await hash(request.media); assert.equal(before.sha256, request.mediaHash);
    const drop = await control({ kind: 'drop' });
    for (const type of ['dragEnter', 'dragOver', 'drop']) await call('Input.dispatchDragEvent', { type, x: drop.x, y: drop.y, data: { items: [], files: [request.media], dragOperationsMask: 1 } });
    steps.push({ action: 'file-drop', path: request.media, sha256: before.sha256 });
    await wait(async () => { const v = (await view()).video[0]; return v && mediaPath(v.src) === canonical(request.media) && v.readyState >= 2 && !v.error; }, 'actual media import');
    if (request.phase === 'export') {
      if (!(await inspect({ kind: 'snapshot' })).inputs.some((i) => i.title === "Manually input current segment's start time")) await click({ selector: '[role="button"]', text: 'Toggle advanced view' });
      await input('input[title="Manually input current segment\'s start time"]', '00:06:16.000', true);
      await input('input[title="Manually input current segment\'s end time"]', '00:06:40.000', true);
      await select('select[title="Zoom"]', '8');
      await click({ selector: 'svg[role="button"]', text: 'Show thumbnails' });
      await seek(390);
      await wait(async () => (await view()).thumbnails > 0, 'real timeline thumbnails');
      await snapshot('01-trim-timeline', 390, 464.141);
      await click({ selector: 'button[title="Export selection"]' }); await control({ selector: '#export-recipe-name' });
      const overwrite = { selector: 'button[role="switch"]', rowText: 'Overwrite existing files' };
      if ((await control(overwrite)).checked === 'true') await click(overwrite);
      await select('div:has(> h1) select[title="Output container format:"]', 'webm');
      await input('#export-recipe-name', recipeName); await click({ selector: 'button', text: 'Save current' });
      const recipes = await control({ selector: '#export-recipe' }); const saved = recipes.options.find((o) => o.text === recipeName); assert(saved); await select('#export-recipe', saved.value);
      // Recipe pane is real, and the paused film remains behind its translucent surface.
      await snapshot('02-export-recipe', 390, 464.141);
      await click({ selector: 'button[title="Export selection"]', exposedOnly: true });
      await wait(async () => { const v = await inspect({ kind: 'snapshot' }); return v.text.includes('Success!') && v.text.includes('Open report'); }, 'actual successful export');
      const reports = (await readdir(path.dirname(request.media))).filter((n) => n.endsWith('.cliptern-report.json')); assert.equal(reports.length, 1);
      const report = JSON.parse(await readFile(path.join(path.dirname(request.media), reports[0]), 'utf8'));
      const output = report.outputs?.[0]?.path; assert.equal(canonical(path.win32.dirname(output)), canonical(path.win32.dirname(request.media)));
      const outputHash = await hash(output); const config = JSON.parse(await readFile(path.join(request.config, 'config.json'), 'utf8'));
      validateExport(report, config, request.media, outputHash.bytes);
      await writeNewJson(path.join(request.evidence, 'consumer-export-report.json'), report);
      await writeNewJson(path.join(request.evidence, 'saved-recipe.json'), report.recipe);
      Object.assign(result, { output, output_hash: outputHash, recipe: report.recipe, input_hash: before });
      await click({ selector: '[role="dialog"] button', text: 'Close' });
    } else {
      assert(request.duration >= 23.5 && request.duration <= 35, 'Exported duration is not a bounded keyframe-aligned trim');
      await seek(Math.min(14, request.duration / 2));
      await snapshot('03-export-reopened', Math.min(14, request.duration / 2), request.duration);
      Object.assign(result, { output: request.media, output_hash: before, reopened_duration: request.duration });
    }
    assert.deepEqual(await hash(request.media), before, 'Imported media bytes changed'); assert.equal(client.exceptions.length, 0);
    result.captured = true;
  } catch (error) { primary = error; result.error = error.stack ?? String(error); } finally { client.close(); result.renderer_exceptions = client.exceptions; await writeNewJson(path.join(request.evidence, 'ui-result.json'), result); }
  if (primary) throw primary;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try { assert.equal(process.platform, 'win32'); const raw = await readFile(process.argv[2]); assert.equal(createHash('sha256').update(raw).digest('hex'), process.argv[3]); const request = JSON.parse(raw); assert(['export', 'reopen'].includes(request.phase)); await run(request); } catch (error) { console.error(error); process.exitCode = 1; }
}
