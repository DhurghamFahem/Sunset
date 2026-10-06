// Dependency-free tests of persistent browser cache behavior.
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {webcrypto} = require('node:crypto');
const source = readFileSync('web/share.js', 'utf8');
const entries = new Map();
const cache = {
  async match(key) { return entries.get(key)?.clone(); },
  async put(key, response) { entries.set(key, response); },
  async keys() { return [...entries.keys()]; },
  async delete(key) { return entries.delete(key); }
};
function browser(storage = {open: async () => cache}) {
  const ctx = {window: {}, caches: storage, crypto: webcrypto, TextEncoder,
    Uint8Array, URL, Response, document: {baseURI: 'https://example.test/catalog/'}};
  vm.runInNewContext(source, ctx);
  return ctx.window.g2gCatalogImages;
}
(async () => {
  const first = browser();
  assert.equal(await first.read('filter-A-price-5000'), '');
  assert.equal(await first.write('filter-A-price-5000', '["saved-png"]'), true);
  assert.equal(await browser().read('filter-A-price-5000'), '["saved-png"]', 'survives a new page session');
  assert.equal(await first.read('filter-A-price-6000'), '', 'changed fingerprint misses');
  for (let i = 0; i < 12; i++) await first.write(`set-${i}`, '["png"]');
  assert.equal(entries.size, 12);
  assert.equal(await first.read('filter-A-price-5000'), '', 'oldest entry evicted');
  assert.equal(await first.write('oversize', 'a'.repeat(32 * 1024 * 1024 + 1)), false);
  const blocked = browser({open: async () => { throw Error('blocked'); }});
  assert.equal(await blocked.read('anything'), '');
  assert.equal(await blocked.write('anything', '[]'), false);
  console.log('PASS: persisted reuse, content invalidation, bounded eviction, unavailable storage.');
})().catch(error => { console.error(error); process.exitCode = 1; });
