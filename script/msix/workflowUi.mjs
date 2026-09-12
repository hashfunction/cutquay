// Copyright 2026 Trieflow LLC. MIT. External CDP driver; never packaged with the app.
import assert from 'node:assert/strict';
import { open, readFile, readdir, lstat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export async function writeNewJson(file, value) {
  const handle = await open(file, 'wx');
  try { await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`); await handle.sync(); } finally { await handle.close(); }
}
async function hashFile(file) {
  const stat = await lstat(file); assert(stat.isFile() && !stat.isSymbolicLink(), 'Expected regular proof file');
  const bytes = await readFile(file);
  assert.equal(bytes.length, stat.size);
  return { bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
}
export function validateEndpoint(value, port) {
  const url = new URL(value);
  assert.equal(url.protocol, 'ws:'); assert.equal(url.hostname, '127.0.0.1'); assert.equal(Number(url.port), port);
  assert(!url.username && !url.password && !url.search && !url.hash);
  assert(/^\/devtools\/browser\/[A-Za-z0-9-]+$/.test(url.pathname));
  return url.href;
}
const winCanonical = (value) => path.win32.normalize(value).toLowerCase();
export function validateTarget(targets, installedRenderer) {
  const pages = targets.filter((t) => t.type === 'page'); assert.equal(pages.length, 1, 'Exactly one consumer renderer required');
  const url = new URL(pages[0].url); assert.equal(url.protocol, 'file:'); assert(!url.host && !url.search && !url.hash);
  assert.equal(winCanonical(decodeURIComponent(url.pathname).replace(/^\/([A-Za-z]:)/, '$1')), winCanonical(installedRenderer), 'Renderer is not the exact installed source');
  return pages[0];
}
export function validateExport(report, config, fixture, name, size) {
  assert.equal(report.version, 1); assert(['succeeded', 'succeeded_with_warnings'].includes(report.status)); assert.equal(report.operation, 'cut');
  assert.deepEqual(report.sources, [fixture]); assert.equal(report.effective.mode, 'lossless');
  assert.deepEqual(report.segments, [{ requestedStart: 2, requestedEnd: 5, keyframeCut: true }]);
  assert.equal(report.recipe.name, name); assert.notEqual(report.recipe.id, 'current');
  assert.equal(report.recipe.outFormat, 'mp4'); assert.equal(report.recipe.exportMode, 'separate');
  assert.equal(report.recipe.keyframeCut, true); assert.equal(report.recipe.enableOverwriteOutput, false);
  const saved = config.exportRecipes.filter((r) => r.id === report.recipe.id); assert.equal(saved.length, 1); assert.deepEqual(saved[0], report.recipe);
  assert.equal(report.outputs.length, 1); const result = report.outputs[0]; assert.equal(result.status, 'created'); assert.equal(result.sizeBytes, size); assert(size > 0);
  assert.equal(winCanonical(path.win32.dirname(result.path)), winCanonical(path.win32.dirname(fixture)));
  assert.notEqual(winCanonical(result.path), winCanonical(fixture)); assert.equal(path.win32.extname(result.path).toLowerCase(), '.mp4');
  assert(report.commands.length > 0 && report.commands.every((c) => Array.isArray(c) && c.every((v) => typeof v === 'string')));
  return { output: result.path, recipe: saved[0] };
}
export function validateInspection(probe) {
  assert.equal(probe.streams.length, 2); const video = probe.streams.filter((s) => s.codec_type === 'video'); const audio = probe.streams.filter((s) => s.codec_type === 'audio');
  assert.equal(video.length, 1); assert.equal(audio.length, 1); assert.equal(video[0].codec_name, 'h264'); assert.equal(audio[0].codec_name, 'aac');
  assert.equal(video[0].width, 160); assert.equal(video[0].height, 90);
  const duration = Number(probe.format.duration); assert(Number.isFinite(duration) && duration >= 2.85 && duration <= 3.15, 'Output is not the three-second trim');
  return { duration, video: video[0], audio: audio[0] };
}

export class Cdp {
  constructor(socket) {
    this.socket = socket; this.next = 0; this.pending = new Map(); this.exceptions = [];
    socket.addEventListener('message', (event) => {
      let msg; try { msg = JSON.parse(event.data); } catch { this.fail(new Error('Malformed CDP message')); return; }
      if (msg.method === 'Runtime.exceptionThrown') this.exceptions.push(msg.params);
      if (!msg.id) return;
      const pending = this.pending.get(msg.id); if (!pending) return;
      this.pending.delete(msg.id); clearTimeout(pending.timer);
      if (msg.error) pending.reject(new Error(JSON.stringify(msg.error))); else pending.resolve(msg.result);
    });
    socket.addEventListener('close', () => this.fail(new Error('CDP closed')));
    socket.addEventListener('error', () => this.fail(new Error('CDP socket error')));
  }

  fail(error) { for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(error); } this.pending.clear(); }

  call(method, params = {}, sessionId = undefined) {
    return new Promise((resolve, reject) => {
      this.next += 1; const id = this.next;
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 10000);
      this.pending.set(id, { resolve, reject, timer });
      try { this.socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })); } catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }

  close() { this.socket.close(); this.fail(new Error('CDP driver finished')); }
}
async function connect(endpoint) {
  const socket = new globalThis.WebSocket(endpoint);
  await new Promise((resolve, reject) => { const timer = setTimeout(() => { socket.close(); reject(new Error('CDP connect timeout')); }, 10000); socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true }); socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('CDP connection failed')); }, { once: true }); });
  return new Cdp(socket);
}

// This function is serialized into the actual renderer. It only reads DOM state
// and scrolls existing controls into view; input is dispatched through CDP.
export function inspectDom(query) {
  const { document } = globalThis;
  const visible = (el) => { const rect = el.getBoundingClientRect(); const style = globalThis.getComputedStyle(el); return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none'; };
  // eslint-disable-next-line unicorn/prefer-dom-node-text-content -- Rendered success text must exclude hidden dialogs.
  if (query.kind === 'snapshot') return { title: document.title, text: document.body.innerText, video: [...document.querySelectorAll('video')].map((v) => ({ src: v.currentSrc || v.src, duration: v.duration, readyState: v.readyState, error: v.error?.message ?? null })), inputs: [...document.querySelectorAll('input')].filter((el) => visible(el)).map((i) => ({ id: i.id, title: i.title, value: i.value, disabled: i.disabled })), selects: [...document.querySelectorAll('select')].filter((el) => visible(el)).map((s) => ({ id: s.id, title: s.title, value: s.value, options: [...s.options].map((o) => ({ value: o.value, text: o.text, disabled: o.disabled })) })) };
  let elements;
  if (query.kind === 'drop') { const video = document.querySelector('video'); elements = video ? [video.parentElement.parentElement] : []; } else { elements = [...document.querySelectorAll(query.selector)].filter((el) => visible(el)); if (query.text !== undefined)elements = elements.filter((el) => el.textContent.trim() === query.text); }
  if (query.rowText) elements = elements.filter((el) => el.closest('tr')?.cells[0]?.textContent.trim().startsWith(query.rowText));
  if (query.exposedOnly && elements.length > 1) elements = elements.filter((el) => { const r = el.getBoundingClientRect(); const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return hit && (hit === el || el.contains(hit)); });
  if (elements.length !== 1) throw new Error(`Expected one visible control ${JSON.stringify(query)}, found ${elements.length}`);
  const el = elements[0]; if (el.disabled || el.closest('fieldset[disabled]')) throw new Error('Control disabled');
  el.scrollIntoView({ block: 'center', inline: 'center' });
  const rect = el.getBoundingClientRect(); const x = Math.max(1, Math.min(globalThis.innerWidth - 2, rect.x + rect.width / 2)); const y = Math.max(1, Math.min(globalThis.innerHeight - 2, rect.y + rect.height / 2));
  const hit = document.elementFromPoint(x, y); if (!hit || !(el === hit || el.contains(hit))) throw new Error('Control occluded');
  return { x, y, value: el.value ?? null, checked: el.getAttribute('aria-checked'), text: el.textContent.trim(), options: el.options ? [...el.options].map((o) => ({ value: o.value, text: o.text, disabled: o.disabled })) : null };
}

async function runUi(request) {
  const client = await connect(validateEndpoint(request.endpoint, request.port)); const steps = []; let primary = null; let captureFailure;
  let result = { schemaVersion: 1, phase: request.phase, sourceCommit: request.sourceCommit, brokerProcessId: request.processId, packageFullName: request.packageFullName, automation: 'unmodified consumer renderer; loopback CDP input', steps, passed: false };
  try {
    const processes = await client.call('SystemInfo.getProcessInfo');
    const browsers = processes.processInfo.filter((p) => p.type === 'browser'); assert.equal(browsers.length, 1); assert.equal(browsers[0].id, request.processId, 'CDP browser PID differs from retained broker process');
    const targets = await client.call('Target.getTargets'); const target = validateTarget(targets.targetInfos, request.rendererPath);
    const { sessionId } = await client.call('Target.attachToTarget', { targetId: target.targetId, flatten: true });
    const call = (method, params) => client.call(method, params, sessionId);
    await call('Runtime.enable', {}); await call('Page.enable', {});
    const inspect = async (query) => { const response = await call('Runtime.evaluate', { expression: `(${inspectDom.toString()})(${JSON.stringify(query)})`, returnByValue: true }); if (response.exceptionDetails) throw new Error(JSON.stringify(response.exceptionDetails)); return response.result.value; };
    const wait = async (fn, label) => { const deadline = Date.now() + 45000; let last; while (Date.now() < deadline) { assert.equal(client.exceptions.length, 0, 'Unhandled renderer exception'); try { const value = await fn(); if (value) return value; } catch (error) { last = error; } await delay(200); } throw new Error(`UI timeout ${label}${last ? `: ${last.message}` : ''}`); };
    const control = async (query) => wait(() => inspect({ exposedOnly: true, ...query }), `control ${JSON.stringify(query)}`);
    const key = async (keyName, code, virtual, modifiers = 0) => { await call('Input.dispatchKeyEvent', { type: keyName === 'Enter' ? 'keyDown' : 'rawKeyDown', ...(keyName === 'Enter' ? { text: '\r', unmodifiedText: '\r' } : {}), key: keyName, code, windowsVirtualKeyCode: virtual, modifiers }); await call('Input.dispatchKeyEvent', { type: 'keyUp', key: keyName, code, windowsVirtualKeyCode: virtual, modifiers }); };
    const click = async (query) => { const point = await control(query); await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: point.x, y: point.y, button: 'left', clickCount: 1 }); await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: point.x, y: point.y, button: 'left', clickCount: 1 }); steps.push({ action: 'click', query }); };
    const input = async (selector, text, submit = false) => { await click({ selector }); await key('a', 'KeyA', 65, 2); await call('Input.insertText', { text }); await (submit ? key('Enter', 'Enter', 13) : key('Tab', 'Tab', 9)); steps.push({ action: 'input', selector, text }); };
    const select = async (selector, text) => { const point = await control({ selector }); const enabled = point.options.filter((o) => !o.disabled); const index = enabled.findIndex((o) => o.text === text); assert(index !== -1, `Missing option ${text}`); await click({ selector }); await key('Home', 'Home', 36); for (let i = 0; i < index; i += 1) await key('ArrowDown', 'ArrowDown', 40); await key('Enter', 'Enter', 13); await wait(async () => { const current = await inspect({ selector, exposedOnly: true }); return current.value === enabled[index].value; }, `selected option ${text}`); steps.push({ action: 'select', selector, text }); };
    const snapshot = async (name) => { const dom = await inspect({ kind: 'snapshot' }); await writeNewJson(path.join(request.evidence, `${name}.json`), dom); const image = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }); const handle = await open(path.join(request.evidence, `${name}.png`), 'wx'); try { await handle.writeFile(Buffer.from(image.data, 'base64')); } finally { await handle.close(); }steps.push({ action: 'snapshot', name }); return dom; };
    captureFailure = () => snapshot(`${request.phase}-failure`);
    await control({ kind: 'drop' });
    const before = await snapshot(`${request.phase}-before`); assert(before.title.includes('Cliptern'));
    const media = request.phase === 'export' ? request.fixture : request.output;
    const beforeHash = await hashFile(media);
    const point = await control({ kind: 'drop' });
    for (const type of ['dragEnter', 'dragOver', 'drop']) await call('Input.dispatchDragEvent', { type, x: point.x, y: point.y, data: { items: [], files: [media], dragOperationsMask: 1 } });
    steps.push({ action: 'file-drop', path: media });
    await wait(async () => { const value = await inspect({ kind: 'snapshot' }); return value.video.some((v) => { try { return winCanonical(decodeURIComponent(new URL(v.src).pathname).replace(/^\/([A-Za-z]:)/, '$1')) === winCanonical(media) && v.readyState >= 1 && !v.error && v.duration > 0; } catch { return false; } }); }, 'imported actual media element');
    if (request.phase === 'export') {
      // A fresh profile starts in simple view, where manual trim inputs are
      // absent. Use the exposed consumer toggle before entering exact times.
      const trimView = await inspect({ kind: 'snapshot' });
      if (!trimView.inputs.some((i) => i.title === "Manually input current segment's start time")) await click({ selector: '[role="button"]', text: 'Toggle advanced view' });
      await input('input[title="Manually input current segment\'s start time"]', '00:00:02.000', true);
      await input('input[title="Manually input current segment\'s end time"]', '00:00:05.000', true);
      await wait(async () => { const view = await inspect({ kind: 'snapshot' }); return view.inputs.some((i) => i.title.endsWith('start time') && i.value === '00:00:02.000') && view.inputs.some((i) => i.title.endsWith('end time') && i.value === '00:00:05.000'); }, 'committed trim values');
      const trim = await snapshot('trim-entered');
      assert(trim.inputs.some((i) => i.title.endsWith('start time') && i.value === '00:00:02.000')); assert(trim.inputs.some((i) => i.title.endsWith('end time') && i.value === '00:00:05.000'));
      await click({ selector: 'button[title="Export selection"]' });
      await control({ selector: '#export-recipe-name' });
      const overwrite = { selector: 'button[role="switch"]', rowText: 'Overwrite existing files' };
      if ((await control(overwrite)).checked === 'true') await click(overwrite);
      await wait(async () => (await inspect(overwrite)).checked === 'false', 'overwrite disabled through visible control');
      await input('#export-recipe-name', request.recipeName);
      await click({ selector: 'button', text: 'Save current' });
      await select('#export-recipe', request.recipeName);
      await snapshot('recipe-saved-applied');
      // The overlay renders a separate export button. Choose the unique one
      // whose center is exposed; no blind first/last DOM selection.
      await click({ selector: 'button[title="Export selection"]', exposedOnly: true });
      await wait(async () => { const value = await inspect({ kind: 'snapshot' }); return value.text.includes('Success!') && value.text.includes('Open report'); }, 'consumer export success dialog');
      await snapshot('export-success');
      const reports = (await readdir(path.dirname(request.fixture))).filter((name) => name.endsWith('.cliptern-report.json')); assert.equal(reports.length, 1, 'Expected one new consumer export report');
      const reportPath = path.join(path.dirname(request.fixture), reports[0]); const report = JSON.parse(await readFile(reportPath, 'utf8'));
      const exported = report.outputs?.[0]?.path; assert.equal(winCanonical(path.win32.dirname(exported)), winCanonical(path.win32.dirname(request.fixture)));
      const outputHash = await hashFile(exported); const config = JSON.parse(await readFile(path.join(request.config, 'config.json'), 'utf8'));
      const validated = validateExport(report, config, request.fixture, request.recipeName, outputHash.bytes);
      await writeNewJson(path.join(request.evidence, 'consumer-export-report.json'), report);
      await writeNewJson(path.join(request.evidence, 'saved-recipe.json'), validated.recipe);
      result = { ...result, output: validated.output, outputHash, recipe: validated.recipe, reportHash: await hashFile(reportPath), inputHash: beforeHash };
      await click({ selector: '[role="dialog"] button', text: 'Close' });
    } else {
      const inspection = validateInspection(request.inspection);
      const reopened = await snapshot('output-reopened'); const video = reopened.video.find((v) => Number.isFinite(v.duration)); assert(Math.abs(video.duration - inspection.duration) <= 0.1); assert(video.duration >= 2.85 && video.duration <= 3.15, 'Reopened video duration differs from expected trim');
      // Reopening creates an initial full-file segment, which is intentionally
      // excluded from cutting. Its existing button is titled Export.
      await click({ selector: 'button[title="Export"]', text: 'Export' });
      const formatSelector = 'div:has(> h1) select[title="Output container format:"]';
      // Perturb the existing control, then require the persisted recipe to
      // restore it through its actual onChange path after app restart.
      const fmt = await control({ selector: formatSelector }); const alternative = fmt.options.find((o) => o.value === 'matroska'); assert(alternative);
      await select(formatSelector, alternative.text);
      await select('#export-recipe', request.recipeName);
      const selected = await control({ selector: formatSelector }); assert.equal(selected.value, 'mp4');
      await snapshot('persisted-recipe-reapplied');
      result = { ...result, output: media, outputHash: beforeHash, reopenedDuration: video.duration, persistedRecipeApplied: true };
      await key('Escape', 'Escape', 27);
    }
    assert.deepEqual(await hashFile(media), beforeHash, 'Imported media changed during UI workflow');
    assert.equal(client.exceptions.length, 0, 'Unhandled renderer exceptions');
    result.passed = true;
  } catch (error) { primary = error; result.primaryError = error.stack ?? String(error); try { if (captureFailure) await captureFailure(); } catch (captureError) { result.captureError = captureError.message; } } finally { client.close(); result.rendererExceptions = client.exceptions; }
  try { await writeNewJson(path.join(request.evidence, `${request.phase}-ui-result.json`), result); } catch (error) { throw new Error(`UI reporting failed: ${error.message}; primary: ${primary?.message ?? 'none'}`); }
  if (primary) throw primary;
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try { assert.equal(process.platform, 'win32', 'Actual UI driver requires Windows'); const request = JSON.parse(await readFile(process.argv[2], 'utf8')); assert(['export', 'reopen'].includes(request.phase)); await runUi(request); } catch (error) { console.error(error); process.exitCode = 1; }
}
