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
