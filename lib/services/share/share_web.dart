import 'dart:js_interop';
import 'dart:typed_data';

@JS('g2gShare.prepare')
external JSBoolean _prepare(JSArray<JSUint8Array> pages);
@JS('g2gShare.share')
external JSPromise<JSString> _share();
@JS('g2gShare.download')
external void _download(JSNumber index);
@JS('g2gShare.clear')
external void _clear();

class ShareService {
  bool prepare(List<Uint8List> pages) =>
      _prepare(pages.map((p) => p.toJS).toList().toJS).toDart;
  // Invoke synchronously from the button, before any await, preserving the
  // transient activation required by iOS Safari's native share sheet.
  Future<String> share() => _share().toDart.then((result) => result.toDart);
  void download(int index) => _download(index.toJS);
  void dispose() => _clear();
}
