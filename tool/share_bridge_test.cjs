// Runs without dependencies: node tool/share_bridge_test.cjs
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = readFileSync('web/share.js', 'utf8');
function browser(navigator) {
  const clicks = [], revoked = [];
  const ctx = {window: {isSecureContext: true}, navigator, File,
    URL: {createObjectURL: () => 'blob:test', revokeObjectURL: url => revoked.push(url)},
    document: {createElement: () => ({click() { clicks.push(this.download); }, remove() {}}), body: {appendChild() {}}}};
  vm.runInNewContext(source, ctx);
  return {bridge: ctx.window.g2gShare, clicks, revoked};
}
(async () => {
  const fallback = browser({});
  assert.equal(fallback.bridge.prepare([new Uint8Array([1,2])]), false);
  assert.equal(await fallback.bridge.share(), 'unsupported');
  fallback.bridge.download(0); assert.deepEqual(fallback.clicks, ['G2G-1.png']);
  let shared;
  const native = browser({canShare: data => data.files.every(f => f.type === 'image/png'), share: data => { shared = data; return Promise.resolve(); }});
  assert.equal(native.bridge.prepare([new Uint8Array([1]), new Uint8Array([2])]), true);
  const result = native.bridge.share();
  assert.equal(shared.files.length, 2, 'share must be invoked before the asynchronous boundary');
  assert.equal(await result, 'shared');
  const cancel = browser({canShare: () => true, share: () => Promise.reject({name: 'AbortError'})});
  cancel.bridge.prepare([new Uint8Array([1])]); assert.equal(await cancel.bridge.share(), 'cancelled');
  const denied = browser({canShare: () => true, share: () => Promise.reject({name: 'NotAllowedError'})});
  denied.bridge.prepare([new Uint8Array([1])]); assert.equal(await denied.bridge.share(), 'failed');
  fallback.bridge.clear(); assert.equal(fallback.revoked.length, 1);
  console.log('PASS: unsupported, file capability detection, multi-file sharing, user activation, cancellation, fallback, URL cleanup.');
})().catch(error => { console.error(error); process.exitCode = 1; });
