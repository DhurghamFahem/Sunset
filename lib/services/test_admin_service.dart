import 'dart:async';

import '../models/catalog.dart';
import '../repositories/test_catalog_repository.dart';
import 'admin_service.dart';

/// A local demo account. Never authenticates with or writes to Supabase.
class TestAdminService implements CatalogAdmin {
  TestAdminService(this.catalog);
  final TestCatalogRepository catalog;
  final _changes = StreamController<bool>.broadcast();
  bool _signedIn = false;

  @override
  Stream<bool> get authChanges => _changes.stream;
  @override
  bool get signedIn => _signedIn;
  @override
  Future<bool> isAdmin() async => signedIn;

  @override
  Future<void> signIn(String email, String password) async {
    if (email.trim().toLowerCase() != 'test@gmail.com' || password != '1234') {
      throw CatalogInputException(
        'تعذر تسجيل الدخول. تأكد من الحساب وكلمة المرور.',
      );
    }
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _changes.add(false);
  }

  void _requireAdmin() {
    if (!signedIn) throw CatalogInputException('سجّل دخول الإدارة أولاً.');
  }

  @override
  Future<void> save(String table, Json data, {String? id}) async {
    _requireAdmin();
    catalog.save(table, data, id: id);
  }

  @override
  Future<void> deleteCategory(String id) async {
    _requireAdmin();
    catalog.deleteCategory(id);
  }

  @override
  Future<UploadedImage?> pickAndUpload({bool category = false}) async {
    _requireAdmin();
    final image = await pickCatalogImage();
    if (image == null) return null;
    _requireAdmin();
    final thumbnail = Uri.dataFromBytes(
      image.thumbnail,
      mimeType: 'image/png',
    ).toString();
    final original = category
        ? thumbnail
        : Uri.dataFromBytes(image.bytes, mimeType: image.mime).toString();
    return UploadedImage(original, thumbnail, {});
  }

  @override
  Future<void> discard(Map<String, List<String>> objects) async {}

  Future<void> dispose() => _changes.close();
}
