import 'dart:async';

import '../models/catalog.dart';
import '../models/order.dart';
import '../repositories/test_catalog_repository.dart';
import 'admin_service.dart';

/// A local demo account. Never authenticates with or writes to Supabase.
class TestAdminService implements CatalogAdmin {
  TestAdminService(this.catalog);
  final TestCatalogRepository catalog;
  final _changes = StreamController<bool>.broadcast();
  bool _signedIn = false;
  Employee? currentEmployee;
  final Map<String, (Employee, String)> _employeeLogins = {};

  void registerEmployee(Employee employee, String? password) {
    _requireAdmin();
    final secret = password ?? _employeeLogins[employee.email]?.$2;
    if (secret == null) throw const OrderException('أدخل كلمة المرور');
    _employeeLogins[employee.email] = (employee, secret);
  }

  @override
  Stream<bool> get authChanges => _changes.stream;
  @override
  bool get signedIn => _signedIn;
  @override
  Future<bool> isAdmin() async => signedIn && currentEmployee == null;
  @override
  Future<StaffAccess> staffAccess() async => signedIn
      ? (currentEmployee == null
            ? StaffAccess.administrator
            : StaffAccess.employee)
      : StaffAccess.none;

  @override
  Future<void> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final login = _employeeLogins[normalized];
    if (normalized == 'test@gmail.com' && password == '1234') {
      currentEmployee = null;
    } else if (login != null && login.$2 == password) {
      currentEmployee = login.$1;
    } else {
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
    currentEmployee = null;
    _changes.add(false);
  }

  void _requireAdmin() {
    if (!signedIn || currentEmployee != null) {
      throw CatalogInputException('سجّل دخول الإدارة أولاً.');
    }
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
  Future<void> deleteTattoo(String id) async {
    _requireAdmin();
    catalog.deleteTattoo(id);
  }

  @override
  Future<UploadedImage?> pickAndUpload({bool category = false}) async {
    _requireAdmin();
    final image = await pickCatalogImage();
    if (image == null) return null;
    _requireAdmin();
    final thumbnail = Uri.dataFromBytes(
      image.thumbnail,
      mimeType: image.thumbnailMime,
    ).toString();
    final original = Uri.dataFromBytes(
      image.bytes,
      mimeType: image.mime,
    ).toString();
    return UploadedImage(original, thumbnail, {});
  }

  @override
  Future<void> discard(Map<String, List<String>> objects) async {}

  Future<void> dispose() => _changes.close();
}
