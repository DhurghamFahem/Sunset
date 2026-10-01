import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/services/selection_renderer.dart';
import 'package:sunset/ui/theme.dart';
import 'package:sunset/ui/widgets/tattoo_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cover = 'asset:assets/test_catalog/flower.png';
  const alternate = 'asset:assets/test_catalog/flower-alternate.png';
  const tattoo = Tattoo(
    id: 'gallery',
    code: 'TEST-001',
    imageUrl: cover,
    additionalImages: [TattooImage(url: alternate, thumbnailUrl: alternate)],
  );
  setUpAll(() async {
    await (FontLoader(
      'NotoArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
  });

  test(
    'old snapshots still have one image and galleries round trip in order',
    () {
      final old = Tattoo.fromJson({
        'id': 'old',
        'code': 'TEST-001',
        'image_url': cover,
      });
      expect(old.images.map((image) => image.url), [cover]);
      final restored = Tattoo.fromJson(tattoo.toJson());
      expect(restored.images.map((image) => image.url), [cover, alternate]);
      expect(restored.additionalImages.single.thumbnailUrl, alternate);
    },
  );

  test('selection export uses only the cover image', () async {
    final requested = <String>[];
    final renderer = SelectionRenderer(
      imageLoader: (url) async {
        requested.add(url);
        return (await rootBundle.load(url.substring('asset:'.length))).buffer
            .asUint8List();
      },
    );
    expect(await renderer.render([tattoo]), hasLength(1));
    expect(requested, [cover]);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('gallery supports RTL swipes, arrows, thumbnails at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: catalogTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: TattooGallery(images: tattoo.images, label: tattoo.code),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.drag(find.byType(PageView), Offset(width * .7, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('الصورة السابقة'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'الصورة التالية',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('single-image tattoos show the image without gallery controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TattooGallery(
            images: const [TattooImage(url: cover)],
            label: 'TEST-001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('الصورة التالية'), findsNothing);
    expect(find.byKey(const ValueKey('gallery-thumbnail-0')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
