import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/ui/admin/catalog_editor.dart';
import 'package:sunset/ui/theme.dart';

class RecordingAdmin implements AdminService {
  final uploads = <UploadedImage>[];
  final discarded = <String>[];
  Json? saved;
  String? savedId;
  @override
  Future<void> save(String table, Json data, {String? id}) async {
    saved = data;
    savedId = id;
  }

  @override
  Future<UploadedImage?> pickAndUpload({bool category = false}) async =>
      uploads.isEmpty ? null : uploads.removeAt(0);

  @override
  Future<void> discard(Map<String, List<String>> objects) async {
    discarded.addAll(objects.values.expand((value) => value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
  });
  const product = Tattoo(
    id: 'existing',
    code: 'G2G-001',
    imageUrl: 'asset:assets/test_catalog/flower.png',
    additionalImages: [
      TattooImage(url: 'asset:assets/test_catalog/flower-alternate.png'),
    ],
    categoryIds: ['flowers', 'minimal'],
    audiences: [TattooAudience.men, TattooAudience.women],
    bodyPlacements: [BodyPlacement.arm, BodyPlacement.back],
  );
  Future<RecordingAdmin> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final admin = RecordingAdmin();
    await tester.pumpWidget(
      MaterialApp(
        theme: catalogTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: CatalogEditor(
            admin: admin,
            isCategory: false,
            product: product,
            categories: const [
              Category(id: 'flowers', name: 'ورود'),
              Category(id: 'minimal', name: 'بسيط'),
            ],
            onSaved: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return admin;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'editing retains multiple categories and saves changed audience and places',
    (tester) async {
      final admin = await openEditor(tester);
      for (final label in [
        'رجالي',
        'نسائي',
        'الذراع',
        'الظهر',
        'ورود',
        'بسيط',
      ]) {
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, label))
              .selected,
          isTrue,
        );
      }
      await tapVisible(tester, find.widgetWithText(FilterChip, 'نسائي'));
      await tapVisible(tester, find.widgetWithText(FilterChip, 'المعصم'));
      await tapVisible(tester, find.text('حفظ وإضافة وشم آخر'));
      expect(admin.savedId, 'existing');
      expect(admin.saved!['audiences'], ['men']);
      expect(
        admin.saved!['body_placements'],
        containsAll(['arm', 'back', 'wrist']),
      );
      expect(admin.saved!['category_ids'], containsAll(['flowers', 'minimal']));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editor rejects empty audiences, placements, and categories', (
    tester,
  ) async {
    final admin = await openEditor(tester);
    for (final label in ['رجالي', 'نسائي', 'الذراع', 'الظهر', 'ورود', 'بسيط']) {
      await tapVisible(tester, find.widgetWithText(FilterChip, label));
    }
    await tapVisible(tester, find.text('حفظ'));
    expect(admin.saved, isNull);
    expect(find.text('اختار خيار واحد على الأقل'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'editor adds images, changes cover, removes an image, and saves the gallery',
    (tester) async {
      final admin = await openEditor(tester);
      admin.uploads.add(
        UploadedImage(
          'asset:assets/test_catalog/star.png',
          'asset:assets/test_catalog/star.png',
          {
            'tattoo-images': ['new-image'],
          },
        ),
      );
      await tapVisible(tester, find.text('إضافة صورة PNG / JPG / WebP'));
      await tapVisible(tester, find.byTooltip('تعيين الصورة 3 كرئيسية'));
      await tapVisible(tester, find.byTooltip('حذف الصورة 2'));
      await tapVisible(tester, find.text('حفظ وإضافة وشم آخر'));
      expect(admin.saved!['image_url'], 'asset:assets/test_catalog/star.png');
      expect(
        admin.saved!['thumbnail_url'],
        'asset:assets/test_catalog/star.png',
      );
      expect(admin.saved!['additional_images'], [
        {
          'image_url': 'asset:assets/test_catalog/flower-alternate.png',
          'thumbnail_url': null,
        },
      ]);
      await tester.pumpWidget(const SizedBox());
      expect(admin.discarded, isEmpty);
    },
  );

  testWidgets(
    'removed and cancelled uploads are cleaned up without deleting saved images',
    (tester) async {
      final admin = await openEditor(tester);
      admin.uploads.addAll([
        UploadedImage(
          'asset:assets/test_catalog/star.png',
          'asset:assets/test_catalog/star.png',
          {
            'tattoo-images': ['first-upload'],
          },
        ),
        UploadedImage(
          'asset:assets/test_catalog/heart.png',
          'asset:assets/test_catalog/heart.png',
          {
            'tattoo-images': ['second-upload'],
          },
        ),
      ]);
      await tapVisible(tester, find.text('إضافة صورة PNG / JPG / WebP'));
      await tapVisible(tester, find.text('إضافة صورة PNG / JPG / WebP'));
      await tapVisible(tester, find.byTooltip('حذف الصورة 3'));
      expect(admin.discarded, ['first-upload']);
      await tester.pumpWidget(const SizedBox());
      expect(admin.discarded, ['first-upload', 'second-upload']);
      expect(admin.saved, isNull);
    },
  );

  testWidgets('at least one tattoo image is required', (tester) async {
    final admin = await openEditor(tester);
    await tapVisible(tester, find.byTooltip('حذف الصورة 2'));
    await tapVisible(tester, find.byTooltip('حذف الصورة 1'));
    await tapVisible(tester, find.text('حفظ'));
    expect(admin.saved, isNull);
    expect(find.text('ارفع صورة الوشم أولاً.'), findsOneWidget);
    expect(admin.discarded, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
