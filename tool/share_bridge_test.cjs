// Runs without dependencies: node tool/share_bridge_test.cjs
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = readFileSync('web/share.js', 'utf8');
function browser(navigator) {
  const clicks = [], revoked = [], nodes = [];
  function createElement(tag) {
    const node = {tag, children: [], style: {},
      append(...children) { this.children.push(...children); },
      setAttribute(name, value) { this[name] = value; },
      showModal() { this.open = true; },
      focus() {},
      click() {
        if (this.disabled) return;
        if (tag === 'a') clicks.push(this.download);
        this.onclick?.();
      },
      remove() { this.removed = true; }};
    nodes.push(node);
    return node;
  }
  let nextUrl = 0;
  const ctx = {window: {isSecureContext: true}, navigator, File,
    URL: {createObjectURL: () => `blob:test-${nextUrl++}`, revokeObjectURL: url => revoked.push(url)},
    document: {createElement, body: {appendChild() {}}}};
  vm.runInNewContext(source, ctx);
  return {bridge: ctx.window.g2gShare, clicks, revoked,
    get dialog() { return nodes.find(n => n.tag === 'dialog' && !n.removed); }};
}
(async () => {
  const fallback = browser({});
  assert.equal(fallback.bridge.prepare([new Uint8Array([1,2])]), false);
  assert.equal(await fallback.bridge.share(), 'unsupported');
  assert.equal(await fallback.bridge.download(0), 'requested');
  assert.deepEqual(fallback.clicks, ['G2G-1.png']);
  assert.equal(await fallback.bridge.download(99), 'failed');
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
  for (const device of [
    {userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)'},
    {userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) CriOS/130.0.0.0 Mobile Safari/604.1'},
    {userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Instagram'}
  ]) {
    const ios = browser(device);
    ios.bridge.prepare([new Uint8Array([1]), new Uint8Array([2])]);
    let completed = false;
    const saving = ios.bridge.download(1).then(result => { completed = true; return result; });
    assert.equal(ios.clicks.length, 0, 'iPhone must not use an anchor download');
    const dialog = ios.dialog;
    assert.equal(dialog.open, true, 'save view opens synchronously on the tap');
    const [, , image, confirm] = dialog.children;
    assert.equal(image.tag, 'img');
    assert.equal(image.src, 'blob:test-1', 'save the requested page');
    confirm.click();
    await Promise.resolve();
    assert.equal(completed, false, 'cannot confirm before image loads');
    image.onload();
    await Promise.resolve();
    assert.equal(completed, false, 'opening/loading an image is not a save');
    confirm.click();
    assert.equal(await saving, 'confirmed');
    assert.equal(ios.dialog, undefined);
    assert.equal(ios.revoked.length, 0, 'keep image URLs available for retries');

    const cancelled = ios.bridge.download(0);
    ios.dialog.children[4].click();
    assert.equal(await cancelled, 'cancelled');
    const escaped = ios.bridge.download(0);
    ios.dialog.oncancel({preventDefault() {}});
    assert.equal(await escaped, 'cancelled');
    const failedImage = ios.bridge.download(0);
    ios.dialog.children[2].onerror();
    assert.equal(ios.dialog.children[3].disabled, true);
    assert.match(ios.dialog.children[0].textContent, /Safari/);
    ios.bridge.clear();
    assert.equal(await failedImage, 'cancelled');
    assert.equal(ios.dialog, undefined);
    assert.equal(ios.revoked.length, 2);
  }
  for (const device of [
    {userAgent: 'Mozilla/5.0 (Linux; Android 15) Chrome/130.0.0.0 Mobile Safari/537.36'},
    {userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0.0.0 Safari/537.36'},
    {userAgent: 'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)'},
    {userAgent: 'Mozilla/5.0 (iPod touch; CPU iPhone OS 18_0 like Mac OS X)'},
    {userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X)', platform: 'MacIntel', maxTouchPoints: 5},
    {platform: 'MacIntel', maxTouchPoints: 0}
  ]) {
    const direct = browser(device);
    direct.bridge.prepare([new Uint8Array([1])]);
    const saving = direct.bridge.download(0);
    assert.deepEqual(direct.clicks, ['G2G-1.png'], 'download starts synchronously on the tap');
    assert.equal(await saving, 'requested');
    assert.equal(direct.dialog, undefined, 'non-iPhone browsers download without the save view');
  }
  console.log('PASS: sharing, user activation, direct downloads outside iPhone, iPhone save confirmation, cancellation, failed image loading, URL cleanup.');
})().catch(error => { console.error(error); process.exitCode = 1; });
