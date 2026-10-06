import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'catalog_image_storage.dart';

@JS('g2gCatalogImages.read')
external JSPromise<JSString> _read(JSString key);
@JS('g2gCatalogImages.write')
external JSPromise<JSBoolean> _write(JSString key, JSString value);

class DeviceCatalogImageStorage implements CatalogImageStorage {
  @override
  Future<List<Uint8List>?> read(String key) async {
    final value = (await _read(key.toJS).toDart).toDart;
    if (value.isEmpty) return null;
    return (jsonDecode(value) as List)
        .map((value) => base64Decode(value as String))
        .toList();
  }

  @override
  Future<bool> write(String key, List<Uint8List> pages) async => (await _write(
    key.toJS,
    jsonEncode(pages.map(base64Encode).toList()).toJS,
  ).toDart).toDart;
}
