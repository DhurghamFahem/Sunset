import 'dart:typed_data';

import 'catalog_image_storage.dart';

// Native exports are not shipped yet; keep previews usable in tests/native demos.
class DeviceCatalogImageStorage implements CatalogImageStorage {
  static final _pages = <String, List<Uint8List>>{};
  @override
  Future<List<Uint8List>?> read(String key) async => _pages[key];
  @override
  Future<bool> write(String key, List<Uint8List> pages) async {
    if (_pages.length >= 12) _pages.remove(_pages.keys.first);
    _pages[key] = pages;
    return false; // No durable native storage.
  }
}
