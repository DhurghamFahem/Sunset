/* File objects are prepared before the tap, preserving browser user activation. */
(() => {
  'use strict';
  let files = [];
  let urls = [];
  let closeSaveView;
  const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent || '') ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  function clear() {
    closeSaveView?.('cancelled');
    urls.forEach(url => URL.revokeObjectURL(url));
    urls = [];
    files = [];
  }
  function showSaveView(index) {
    closeSaveView?.('cancelled');
    // Flutter's canvas preview has no native image long-press menu. Use a real
    // <img> on iOS so Safari can offer Save Image / Add to Photos instead of
    // relying on a blob download (which may save to Files or be ignored).
    return new Promise(resolve => {
      const dialog = document.createElement('dialog');
      dialog.dir = 'rtl';
      dialog.setAttribute('aria-label', 'حفظ الصورة');
      dialog.style.cssText = 'position:fixed;inset:0;margin:auto;box-sizing:border-box;width:100%;max-width:650px;max-height:100%;overflow:auto;padding:20px;border:0;border-radius:16px;background:#fff;color:#151515;text-align:center;font:17px system-ui;z-index:2147483647;';
      const instructions = document.createElement('p');
      instructions.textContent = 'اضغط مطولاً على الصورة واختر «حفظ الصورة» أو «إضافة إلى الصور». بعد الحفظ اضغط «حفظت الصورة، متابعة».';
      const help = document.createElement('p');
      help.textContent = 'إذا ما ظهر خيار الحفظ داخل Instagram أو WhatsApp، افتح الموقع في Safari وحاول مرة ثانية.';
      help.style.cssText = 'font-size:14px;color:#555;';
      const image = document.createElement('img');
      image.alt = `اختياراتي ${index + 1} من ${files.length}`;
      image.style.cssText = 'display:block;width:100%;height:auto;object-fit:contain;-webkit-touch-callout:default;user-select:auto;-webkit-user-select:auto;';
      const confirm = document.createElement('button');
      confirm.textContent = 'حفظت الصورة، متابعة';
      confirm.disabled = true;
      confirm.style.cssText = 'margin:16px 4px;padding:14px 20px;border:0;border-radius:12px;background:#174d38;color:#fff;font:inherit;';
      const cancel = document.createElement('button');
      cancel.textContent = 'رجوع';
      cancel.style.cssText = 'margin:16px 4px;padding:14px 20px;border:1px solid #ddd;border-radius:12px;background:#fff;color:#151515;font:inherit;';
      const previousFocus = document.activeElement;
      let finished = false;
      function finish(result) {
        if (finished) return;
        finished = true;
        if (closeSaveView === finish) closeSaveView = undefined;
        dialog.remove();
        previousFocus?.focus();
        resolve(result);
      }
      closeSaveView = finish;
      image.onload = () => { confirm.disabled = false; };
      image.onerror = () => {
        instructions.textContent = 'تعذر فتح الصورة. ارجع وحاول مرة ثانية من Safari.';
        confirm.disabled = true;
      };
      confirm.onclick = () => finish('confirmed');
      cancel.onclick = () => finish('cancelled');
      dialog.oncancel = event => { event.preventDefault(); finish('cancelled'); };
      dialog.onclose = () => finish('cancelled');
      dialog.append(instructions, help, image, confirm, cancel);
      document.body.appendChild(dialog);
      image.src = urls[index];
      try {
        if (typeof dialog.showModal === 'function') dialog.showModal();
        else dialog.setAttribute('open', '');
        // Keep the image and instructions visible when opening a tall export.
        cancel.focus({preventScroll: true});
        dialog.scrollTop = 0;
      } catch (_) { finish('failed'); }
    });
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
      if (!urls[index]) return Promise.resolve('failed');
      if (isIOS()) return showSaveView(index);
      try {
        const a = document.createElement('a');
        a.href = urls[index];
        a.download = files[index].name;
        a.target = '_blank';
        a.rel = 'noopener';
        document.body.appendChild(a);
        try { a.click(); } finally { a.remove(); }
        // This reports a request, not confirmation that the browser saved it.
        // Keep URLs alive until screen disposal for browsers opening previews.
        return Promise.resolve('requested');
      } catch (_) { return Promise.resolve('failed'); }
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
