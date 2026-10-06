import 'dart:typed_data';

abstract interface class CatalogImageStorage {
  Future<List<Uint8List>?> read(String key);
  Future<bool> write(String key, List<Uint8List> pages);
}
