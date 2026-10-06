/* File objects are prepared before the tap, preserving browser user activation. */
(() => {
  'use strict';
  let files = [];
  let urls = [];
  function clear() {
    urls.forEach(url => URL.revokeObjectURL(url));
    urls = [];
    files = [];
  }
  window.g2gShare = {
    clear,
    prepare(pages) {
      clear();
      files = pages.map((bytes, i) => new File([bytes], `G2G-${i + 1}.png`, {type: 'image/png'}));
      urls = files.map(file => URL.createObjectURL(file));
      try {
        return !!(window.isSecureContext && navigator.share && navigator.canShare && navigator.canShare({files}));
      } catch (_) { return false; }
    },
    share() {
      if (!files.length || !navigator.share || !navigator.canShare) return Promise.resolve('unsupported');
      try {
        if (!navigator.canShare({files})) return Promise.resolve('unsupported');
        return navigator.share({files, title: 'اختياراتي من G2G'})
          .then(() => 'shared', error => error.name === 'AbortError' ? 'cancelled' : 'failed');
      } catch (_) { return Promise.resolve('failed'); }
    },
    download(index) {
      if (!urls[index]) return;
      const a = document.createElement('a');
      a.href = urls[index];
      a.download = files[index].name;
      a.target = '_blank';
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      a.remove();
      // Keep URLs alive until screen disposal for browsers that open a preview.
    }
  };
})();

// Persistent, content-addressed catalog exports. No network fetches are made.
(() => {
  'use strict';
  const name = 'g2g-catalog-images-v1';
  const maxBytes = 32 * 1024 * 1024;
  async function address(key) {
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key));
    const hex = Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, '0')).join('');
    return new URL(`__g2g_catalog_images__/${hex}`, document.baseURI).href;
  }
  window.g2gCatalogImages = {
    async read(key) {
      try {
        const cache = await caches.open(name);
        const response = await cache.match(await address(key));
        return response ? await response.text() : '';
      } catch (_) { return ''; }
    },
    async write(key, value) {
      try {
        // Base64 JSON is ASCII, so character length equals stored byte length.
        if (value.length > maxBytes) return false;
        const cache = await caches.open(name);
        const url = await address(key);
        await cache.delete(url);
        const entries = [];
        let total = value.length;
        for (const request of await cache.keys()) {
          const response = await cache.match(request);
          const size = Number(response.headers.get('X-Export-Bytes')) || (await response.text()).length;
          entries.push({request, size});
          total += size;
        }
        while (entries.length && (entries.length >= 12 || total > maxBytes)) {
          const oldest = entries.shift();
          await cache.delete(oldest.request);
          total -= oldest.size;
        }
        await cache.put(url, new Response(value, {headers: {
          'Content-Type': 'application/json', 'X-Export-Bytes': String(value.length)
        }}));
        return true;
      } catch (_) { return false; }
    }
  };
})();
