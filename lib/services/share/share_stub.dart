import 'dart:typed_data';

class ShareService {
  bool prepare(List<Uint8List> pages) => false;
  Future<String> share() async => 'unsupported';
  void download(int index) {}
  void dispose() {}
}
