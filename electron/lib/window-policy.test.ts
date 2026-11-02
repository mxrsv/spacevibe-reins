import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isChannel } from '../../src/lib/ipc-contract.ts';
import { allowNavigation, allowWindowOpen, isTrustedPage } from './window-policy.ts';
import { usageWorkerPath } from './worker-path.ts';

const built = { appUrl: 'file:///Applications/Reins.app/Contents/Resources/app.asar/out/renderer/index.html' };
const dev = { ...built, devUrl: 'http://localhost:5173/' };

test('only the app page may call the main process', () => {
  assert.equal(isTrustedPage(`${built.appUrl}#/rules`, built), true);
  for (const url of ['https://example.invalid/', 'file:///etc/passwd', 'http://localhost:5173/', 'about:blank', 'not a url', '']) {
    assert.equal(isTrustedPage(url, built), false, url);
  }
});

test('the dev server origin is trusted only when a dev URL is given', () => {
  assert.equal(isTrustedPage('http://localhost:5173/', dev), true);
  assert.equal(isTrustedPage('http://localhost:5173/src/main.tsx', dev), true);
  assert.equal(isTrustedPage('http://localhost:9999/', dev), false);
  assert.equal(isTrustedPage('https://example.invalid/', dev), false);
});

test('navigating away and opening windows are refused', () => {
  assert.equal(allowNavigation('https://example.invalid/', built), false);
  assert.equal(allowNavigation('file:///etc/hosts', built), false);
  assert.equal(allowWindowOpen(), false);
});

test('the channel allow-list does not accept inherited object keys', () => {
  assert.equal(isChannel('inventory:read'), true);
  for (const name of ['fs:read-file', 'constructor', '__proto__', 'hasOwnProperty', '']) assert.equal(isChannel(name), false);
});

test('a packaged worker path points at the unpacked folder', () => {
  assert.equal(usageWorkerPath('/A/Reins.app/Contents/Resources/app.asar'), '/A/Reins.app/Contents/Resources/app.asar/core/usage.mjs'.replace('app.asar/', 'app.asar.unpacked/'));
  assert.equal(usageWorkerPath('/repo'), '/repo/core/usage.mjs');
});
