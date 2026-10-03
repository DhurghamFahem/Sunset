import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/catalog.dart';

class CatalogInputException implements Exception {
  CatalogInputException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UploadedImage {
  UploadedImage(this.imageUrl, this.thumbnailUrl, this.objects);
  final String imageUrl, thumbnailUrl;
  final Map<String, List<String>> objects;
}

abstract interface class CatalogAdmin {
  Stream<Object?> get authChanges;
  bool get signedIn;
  Future<bool> isAdmin();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> save(String table, Json data, {String? id});
  Future<void> deleteCategory(String id);
  Future<UploadedImage?> pickAndUpload({bool category = false});
  Future<void> discard(Map<String, List<String>> objects);
}

class AdminService implements CatalogAdmin {
  AdminService(this.client);
  final SupabaseClient client;
  @override
  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;
  @override
  bool get signedIn => client.auth.currentSession != null;
  @override
  Future<bool> isAdmin() async =>
      signedIn && await client.rpc('is_admin') == true;
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (!await isAdmin()) {
      await client.auth.signOut();
      throw CatalogInputException('هذا الحساب ما عنده صلاحية الإدارة.');
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<void> save(String table, Json data, {String? id}) async {
    if (!{'products', 'categories'}.contains(table)) {
      throw ArgumentError('Invalid table');
    }
    try {
      if (table == 'products') {
        // Save the product and all category memberships in one transaction.
        await client.rpc(
          'save_catalog_product',
          params: {'p_data': data, 'p_id': id},
        );
      } else if (id == null) {
        await client.from(table).insert(data);
      } else {
        await client.from(table).update(data).eq('id', id);
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw CatalogInputException('رقم التصميم مستخدم. اختار رقم ثاني.');
      }
      throw CatalogInputException(
        'ما قدرنا نحفظ. تأكد من البيانات واتصالك وحاول مرة ثانية.',
      );
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    try {
      await client.from('categories').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw CatalogInputException(
          'القسم بيه وشومات. انقلها لقسم ثاني قبل الحذف.',
        );
      }
      throw CatalogInputException('تعذر حذف القسم. حاول مرة ثانية.');
    }
  }

  @override
  Future<UploadedImage?> pickAndUpload({bool category = false}) async {
    final image = await pickCatalogImage();
    if (image == null) return null;
    final (:bytes, :thumbnail, :extension, :mime) = image;
    final path =
        '${client.auth.currentUser!.id}/${DateTime.now().microsecondsSinceEpoch}';
    final objects = <String, List<String>>{};
    try {
      final bucket = category ? 'category-images' : 'tattoo-images';
      final object = category ? '$path.png' : '$path.$extension';
      await client.storage
          .from(bucket)
          .uploadBinary(
            object,
            category ? thumbnail : bytes,
            fileOptions: FileOptions(
              contentType: category ? 'image/png' : mime,
              cacheControl: '31536000',
            ),
          );
      objects[bucket] = [object];
      final originalUrl = client.storage.from(bucket).getPublicUrl(object);
      if (category) return UploadedImage(originalUrl, originalUrl, objects);
      await client.storage
          .from('tattoo-thumbnails')
          .uploadBinary(
            '$path.png',
            thumbnail,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              cacheControl: '31536000',
            ),
          );
      objects['tattoo-thumbnails'] = ['$path.png'];
      return UploadedImage(
        originalUrl,
        client.storage.from('tattoo-thumbnails').getPublicUrl('$path.png'),
        objects,
      );
    } catch (_) {
      await discard(objects);
      rethrow;
    }
  }

  @override
  Future<void> discard(Map<String, List<String>> objects) async {
    for (final entry in objects.entries) {
      try {
        await client.storage.from(entry.key).remove(entry.value);
      } catch (_) {
        /* Retry cleanup from Storage dashboard. */
      }
    }
  }
}

// Shared validation for both local test images and Supabase uploads.
typedef PickedCatalogImage = ({
  Uint8List bytes,
  Uint8List thumbnail,
  String extension,
  String mime,
});

Future<PickedCatalogImage?> pickCatalogImage() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  if (file == null) return null;
  final length = await file.length();
  if (length == null || length > AppConfig.maxUploadBytes) {
    throw CatalogInputException('اختار صورة أصغر من 10 ميغابايت.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > AppConfig.maxUploadBytes) {
    throw CatalogInputException(
      'اختار صورة PNG أو JPG أو WebP أصغر من 10 ميغابايت.',
    );
  }
  final extension = (file.extension ?? '').toLowerCase();
  final String mime;
  if (bytes.length > 12 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      extension == 'png') {
    mime = 'image/png';
  } else if (bytes.length > 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      ['jpg', 'jpeg'].contains(extension)) {
    mime = 'image/jpeg';
  } else if (bytes.length > 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP' &&
      extension == 'webp') {
    mime = 'image/webp';
  } else {
    throw CatalogInputException('نوع الصورة غير مدعوم أو الملف تالف.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 24000000) {
    throw CatalogInputException('اختار صورة واضحة بحجم أقل من 24 ميغابكسل.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw CatalogInputException('ما قدرنا نفتح الصورة. جرّب ملف ثاني.');
  }
  final thumbImage = decoded.width > 600 || decoded.height > 600
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 600 : null,
          height: decoded.height > decoded.width ? 600 : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  // PNG retains transparency; full original tattoo bytes are never transformed.
  final thumbnail = Uint8List.fromList(img.encodePng(thumbImage));
  if (thumbnail.length > 2097152) {
    throw CatalogInputException('الصورة معقدة جداً. جرّب صورة أصغر.');
  }
  return (bytes: bytes, thumbnail: thumbnail, extension: extension, mime: mime);
}
