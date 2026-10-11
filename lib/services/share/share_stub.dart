import 'dart:typed_data';

class ShareService {
  bool prepare(List<Uint8List> pages) => false;
  Future<String> share() async => 'unsupported';
  Future<String> download(int index) async => 'unsupported';
  void dispose() {}
}
