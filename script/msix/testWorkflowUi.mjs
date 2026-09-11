/* eslint-disable no-param-reassign, no-return-assign -- Deliberately corrupt detached report fixtures. */
// Copyright 2026 Trieflow LLC. MIT. Pure boundary tests, not Windows UI evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { validateEndpoint, validateTarget, validateExport, validateInspection, writeNewJson } from './workflowUi.mjs';

const fixture = String.raw`C:\owned\source.mp4`;
const output = String.raw`C:\owned\trim.mp4`;
const recipe = { version: 1, id: 'saved-id', name: 'CI original trim', exportMode: 'separate', outFormat: 'mp4', keyframeCut: true, enableOverwriteOutput: false };
function report() { return { version: 1, status: 'succeeded', operation: 'cut', sources: [fixture], recipe, segments: [{ requestedStart: 2, requestedEnd: 5, keyframeCut: true }], effective: { mode: 'lossless' }, outputs: [{ path: output, status: 'created', sizeBytes: 1234 }], commands: [['-i', fixture, '-c:v:0', 'copy']] }; }

test('endpoint rejects non-loopback, credentials, fragments and wrong browser token', () => {
  assert.equal(validateEndpoint('ws://127.0.0.1:4567/devtools/browser/token', 4567), 'ws://127.0.0.1:4567/devtools/browser/token');
  for (const url of ['ws://example.com:4567/devtools/browser/token', 'ws://127.0.0.1:9999/devtools/browser/token', 'ws://user@127.0.0.1:4567/devtools/browser/token', 'ws://127.0.0.1:4567/devtools/browser/token#x', 'ws://127.0.0.1:4567/foreign']) assert.throws(() => validateEndpoint(url, 4567));
});
test('only one exact installed renderer is accepted, without sibling or URL aliases', () => {
  const installed = String.raw`C:\Program Files\WindowsApps\Cut\resources\app.asar\out\renderer\index.html`;
  const target = { type: 'page', url: 'file:///C:/Program%20Files/WindowsApps/Cut/resources/app.asar/out/renderer/index.html', targetId: 'one' };
  assert.equal(validateTarget([target], installed).targetId, 'one');
  for (const targets of [[], [target, target], [{ ...target, url: `${target.url}?x` }], [{ ...target, url: target.url.replace('/Cut/', '/Cut-other/') }], [{ ...target, url: 'https://example.com' }]]) assert.throws(() => validateTarget(targets, installed));
});
test('actual export report must bind source, saved recipe, requested range and one created output', () => {
  assert.equal(validateExport(report(), { exportRecipes: [recipe] }, fixture, 'CI original trim', 1234).output, output);
  for (const mutate of [(r) => r.status = 'failed', (r) => r.sources = [output], (r) => r.recipe = { ...recipe, id: 'current' }, (r) => r.segments[0].requestedStart = 0, (r) => r.outputs[0].status = 'skipped_existing', (r) => r.outputs[0].path = String.raw`C:\owned-other\trim.mp4`, (r) => r.outputs[0].path = fixture, (r) => r.outputs[0].sizeBytes = 1, (r) => r.effective.mode = 'smart-cut', (r) => r.commands = []]) {
    const value = report(); mutate(value); assert.throws(() => validateExport(value, { exportRecipes: [recipe] }, fixture, 'CI original trim', 1234));
  }
  assert.throws(() => validateExport(report(), { exportRecipes: [] }, fixture, 'CI original trim', 1234));
});
test('ffprobe output requires both expected streams and actual trimmed duration', () => {
  const probe = { streams: [{ codec_type: 'video', codec_name: 'h264', width: 160, height: 90 }, { codec_type: 'audio', codec_name: 'aac' }], format: { duration: '3.040' } };
  assert.equal(validateInspection(probe).duration, 3.04);
  for (const value of [{ ...probe, format: { duration: '8' } }, { ...probe, streams: probe.streams.slice(0, 1) }, { ...probe, streams: [{ ...probe.streams[0], width: 320 }, probe.streams[1]] }]) assert.throws(() => validateInspection(value));
});
test('evidence publication preserves an existing result', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'cut-ui-evidence-'));
  try { const file = path.join(root, 'result.json'); await writeFile(file, 'previous'); await assert.rejects(writeNewJson(file, { passed: true })); assert.equal(await readFile(file, 'utf8'), 'previous'); } finally { await rm(root, { recursive: true }); }
});

test('actual DOM locator refuses obscured/disabled controls and resolves only the exposed export button', async () => {
  const { JSDOM } = await import('jsdom');
  const { inspectDom } = await import('./workflowUi.mjs');
  const dom = new JSDOM('<button id="behind" title="Export selection">Export</button><button id="front" title="Export selection">Export</button><fieldset disabled><input id="locked"></fieldset><table><tr><td>Overwrite existing files</td><td><button id="overwrite" role="switch" aria-checked="true"></button></td></tr></table>');
  const previous = { document: globalThis.document, getComputedStyle: globalThis.getComputedStyle, innerWidth: globalThis.innerWidth, innerHeight: globalThis.innerHeight };
  try {
    globalThis.document = dom.window.document; globalThis.getComputedStyle = dom.window.getComputedStyle; globalThis.innerWidth = 800; globalThis.innerHeight = 600;
    for (const element of dom.window.document.querySelectorAll('*')) { element.getBoundingClientRect = () => ({ x: 10, y: 10, width: 100, height: 30 }); element.scrollIntoView = () => { /* jsdom has no layout/scroll implementation. */ }; }
    let hit = dom.window.document.querySelector('#front'); dom.window.document.elementFromPoint = () => hit;
    assert.throws(() => inspectDom({ selector: 'button' }), /Expected one/);
    assert.equal(inspectDom({ selector: 'button', exposedOnly: true }).text, 'Export');
    assert.throws(() => inspectDom({ selector: '#behind' }), /occluded/);
    hit = dom.window.document.querySelector('#locked'); assert.throws(() => inspectDom({ selector: '#locked' }), /disabled/);
    assert.equal(dom.window.document.querySelector('#locked').value, '');
    hit = dom.window.document.querySelector('#overwrite');
    assert.equal(inspectDom({ selector: 'button[role="switch"]', rowText: 'Overwrite existing files' }).checked, 'true');
    assert.throws(() => inspectDom({ selector: 'button[role="switch"]', rowText: 'Unrelated row' }), /Expected one/);
  } finally { Object.assign(globalThis, previous); dom.window.close(); }
});

test('CDP transport keeps correlated result, protocol failure and disconnect distinct', async () => {
  const { Cdp } = await import('./workflowUi.mjs');
  class Socket extends EventTarget {
    send(value) { this.sent = JSON.parse(value); }

    reply(value) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(value) })); }

    close() { this.dispatchEvent(new Event('close')); }
  }
  const socket = new Socket(); const client = new Cdp(socket);
  const success = client.call('Target.getTargets'); socket.reply({ id: socket.sent.id, result: { targetInfos: [] } }); assert.deepEqual(await success, { targetInfos: [] });
  const failed = client.call('Input.dispatchDragEvent', {}, 'actual-session'); assert.equal(socket.sent.sessionId, 'actual-session'); socket.reply({ id: socket.sent.id, error: { message: 'drag rejected' } }); await assert.rejects(failed, /drag rejected/);
  const disconnected = client.call('Runtime.evaluate'); socket.close(); await assert.rejects(disconnected, /CDP closed/);
  socket.reply({ method: 'Runtime.exceptionThrown', params: { text: 'renderer failed' } }); assert.equal(client.exceptions.length, 1);
  client.close();
});
