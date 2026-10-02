import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/ui/admin/admin_screen.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/customer/catalog_filter_sheet.dart';
import 'package:sunset/ui/customer/share_screen.dart';
import 'package:sunset/ui/widgets/tattoo_card.dart';

import 'support/fixtures.dart';

class PreviewAdmin implements AdminService {
  @override
  Stream<Never> get authChanges => const Stream.empty();
  @override
  bool get signedIn => true;
  @override
  Future<bool> isAdmin() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
    await (FontLoader(
      'G2GSymbols',
    )..addFont(rootBundle.load('assets/fonts/G2GSymbols.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'serif',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
  });
  void viewport(WidgetTester tester, double width, [double height = 900]) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<SelectionStore> start(
    WidgetTester tester, {
    MemoryCatalog? catalog,
    GlobalKey? capture,
    AdminService? admin,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final analytics = NoopAnalytics();
    final selection = SelectionStore(
      await SharedPreferences.getInstance(),
      analytics,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: G2GApp(
          services: AppServices(
            catalog: catalog ?? TestCatalogRepository(),
            selection: selection,
            analytics: analytics,
            admin: admin,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selection;
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    if (!const bool.fromEnvironment('CAPTURE_UX')) return;
    await tester.runAsync(() async {
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      for (final image in images) {
        await precacheImage(
          image.image,
          tester.element(find.byType(Image).first),
        );
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('test-results').create(recursive: true);
      await File('test-results/ux-$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [360.0, 390.0, 430.0, 1200.0]) {
    testWidgets(
      'immediate browsing and persistent review action at $width px',
      (tester) async {
        viewport(tester, width, 740);
        final capture = GlobalKey();
        final selection = await start(tester, capture: capture);
        expect(find.text('تفاصيل صغيرة، تشبهك.'), findsOneWidget);
        expect(find.byType(FilterChip), findsNothing);
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(find.text('اختيار').first.hitTestable(), findsOneWidget);
        await screenshot(tester, capture, 'browse-${width.toInt()}');
        await tester.tap(find.text('اختيار').first);
        await tester.pumpAndSettle();
        expect(selection.count, 1);
        expect(
          find.byKey(const ValueKey('review-selections')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('review-selections')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('prepare-selections')).hitTestable(),
          findsOneWidget,
        );
        await screenshot(tester, capture, 'review-${width.toInt()}');
        await tester.tap(find.text('كمل التصفح'));
        await tester.pumpAndSettle();
        expect(find.text('تم الاختيار'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await selection.flush();
        await tester.pumpWidget(const SizedBox());
        selection.dispose();
      },
    );
  }

  for (final width in [360.0, 1200.0]) {
    testWidgets('redesigned secondary screens remain usable at $width px', (
      tester,
    ) async {
      viewport(tester, width, 800);
      final capture = GlobalKey();
      final selection = await start(tester, capture: capture);
      final router = GoRouter.of(tester.element(find.byType(TattooCard).first));
      await tester.tap(find.byTooltip('تصفح التصنيفات'));
      await tester.pumpAndSettle();
      expect(find.text('لكل ذوق، حكاية.'), findsOneWidget);
      await screenshot(tester, capture, 'categories-${width.toInt()}');
      final product = (await TestCatalogRepository().products(
        const CatalogQuery(),
      )).first;
      router.go('/tattoo/${product.id}');
      await tester.pumpAndSettle();
      expect(find.text('أضف لاختياراتي').hitTestable(), findsOneWidget);
      await screenshot(tester, capture, 'detail-${width.toInt()}');
      router.go('/selections');
      await tester.pumpAndSettle();
      expect(find.text('تصفح الوشومات').hitTestable(), findsOneWidget);
      await screenshot(tester, capture, 'empty-${width.toInt()}');
      router.go('/admin');
      await tester.pumpAndSettle();
      expect(find.text('تسجيل دخول الإدارة'), findsOneWidget);
      await screenshot(tester, capture, 'login-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    });

    testWidgets('management and editor actions fit at $width px', (
      tester,
    ) async {
      viewport(tester, width, 800);
      final capture = GlobalKey();
      final selection = await start(
        tester,
        capture: capture,
        admin: PreviewAdmin(),
      );
      final router = GoRouter.of(tester.element(find.byType(TattooCard).first));
      router.go('/admin');
      await tester.pumpAndSettle();
      expect(find.byType(AdminScreen), findsOneWidget);
      await screenshot(tester, capture, 'admin-products-${width.toInt()}');
      await tester.tap(find.byTooltip('إضافة وشم'));
      await tester.pumpAndSettle();
      expect(find.text('حفظ').hitTestable(), findsOneWidget);
      await screenshot(tester, capture, 'editor-${width.toInt()}');
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();
      router.go('/admin/categories');
      await tester.pumpAndSettle();
      await screenshot(tester, capture, 'admin-categories-${width.toInt()}');
      await tester.tap(find.byTooltip('إضافة تصنيف'));
      await tester.pumpAndSettle();
      expect(find.text('حفظ').hitTestable(), findsOneWidget);
      await screenshot(tester, capture, 'category-editor-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    });
  }

  testWidgets(
    'optional filters combine and survive closing, review, and return',
    (tester) async {
      viewport(tester, 390);
      final capture = GlobalKey();
      final selection = await start(tester, capture: capture);
      await tester.tap(find.widgetWithText(ChoiceChip, 'رجالي'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-filters')));
      await tester.pumpAndSettle();
      await screenshot(tester, capture, 'filters');
      await tapVisible(tester, find.byKey(const ValueKey('filter-المعصم')));
      // Collapse placement to keep the next choices close by.
      await tapVisible(tester, find.text('مكان الوشم'));
      await tapVisible(tester, find.text('التصنيف'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'أغصان وأوراق'));
      await tapVisible(tester, find.text('التصنيف'));
      await tapVisible(tester, find.text('القياس'));
      await tapVisible(tester, find.byKey(const ValueKey('filter-3 × 5 سم')));
      await tapVisible(tester, find.text('القياس'));
      await tapVisible(tester, find.text('الوسوم'));
      await tapVisible(tester, find.byKey(const ValueKey('filter-floral')));
      await tester.tap(find.text('عرض الوشومات'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'زَهْرَة');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<TattooCard>(find.byType(TattooCard))
          .toList();
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.product.audiences, contains(TattooAudience.men));
        expect(card.product.bodyPlacements, contains(BodyPlacement.wrist));
        expect(card.product.categoryIds, contains('test-branches'));
        expect(card.product.size, const TattooSize(3, 5));
        expect(card.product.tags, contains('floral'));
        expect(find.text(card.product.code), findsNothing);
      }
      await tapVisible(tester, find.text('اختيار').first);
      await tester.tap(find.byKey(const ValueKey('review-selections')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كمل التصفح'));
      await tester.pumpAndSettle();
      expect(find.text('فلترة (4)'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'زَهْرَة',
      );
      await tapVisible(tester, find.byKey(const ValueKey('open-filters')));
      // Reopening retains applied choices; dismissal does not clear them.
      expect(find.text('المعصم'), findsWidgets);
      await tester.tap(find.byTooltip('إغلاق الفلاتر'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('عرض الكل'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('فلترة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await selection.flush();
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );

  testWidgets(
    'filter drafts cancel without requests and apply in one request',
    (tester) async {
      viewport(tester, 390);
      final catalog = MemoryCatalog();
      final selection = await start(tester, catalog: catalog);
      final initial = catalog.queries.length;
      await tester.tap(find.byKey(const ValueKey('open-filters')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('filter-الذراع')));
      await tester.tap(find.byTooltip('إغلاق الفلاتر'));
      await tester.pumpAndSettle();
      expect(catalog.queries.length, initial);
      await tester.tap(find.byKey(const ValueKey('open-filters')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('filter-الذراع')))
            .selected,
        isFalse,
      );
      await tapVisible(tester, find.byKey(const ValueKey('filter-الذراع')));
      await tapVisible(tester, find.byKey(const ValueKey('filter-الظهر')));
      expect(catalog.queries.length, initial);
      await tester.tap(find.text('عرض الوشومات'));
      await tester.pumpAndSettle();
      expect(catalog.queries.length, initial + 1);
      expect(
        catalog.queries.last.bodyPlacements,
        containsAll([BodyPlacement.arm, BodyPlacement.back]),
      );
      expect(find.byType(CatalogFilterSheet), findsNothing);
      expect(find.text('عرض كل الوشومات'), findsOneWidget);
      await tester.tap(find.text('عرض كل الوشومات'));
      await tester.pumpAndSettle();
      expect(catalog.queries.last.bodyPlacements, isEmpty);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );

  testWidgets(
    'removal has undo and review action remains visible for long lists',
    (tester) async {
      viewport(tester, 360, 640);
      final selection = await start(tester);
      final products = await TestCatalogRepository().products(
        const CatalogQuery(),
      );
      for (final p in products.take(15)) {
        selection.toggle(p);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-selections')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prepare-selections')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byTooltip('إزالة ${products.first.displayName}').first,
      );
      await tester.pumpAndSettle();
      expect(selection.count, 14);
      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(selection.count, 15);
      expect(tester.takeException(), isNull);
      await selection.flush();
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );

  testWidgets(
    'detail selection stays visible and the complete export returns to review',
    (tester) async {
      viewport(tester, 360, 640);
      final selection = await start(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(TattooCard).first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('أضف لاختياراتي').hitTestable(), findsOneWidget);
      await tester.tap(find.text('أضف لاختياراتي'));
      await tester.pumpAndSettle();
      expect(selection.count, 1);
      await tester.tap(find.byKey(const ValueKey('review-selections')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prepare-selections')));
      for (
        var i = 0;
        i < 50 && find.byType(ShareScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(ShareScreen), findsOneWidget);
      expect(find.text('حفظ الصورة').hitTestable(), findsOneWidget);
      // The sharing route covers the catalog shell rather than nesting app bars.
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.text('تعديل'));
      await tester.pumpAndSettle();
      expect(selection.count, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('prepare-selections')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await selection.flush();
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );

  testWidgets(
    'save flow advances per image then offers Instagram without clearing choices',
    (tester) async {
      viewport(tester, 360, 640);
      final capture = GlobalKey();
      final selection = await start(tester, capture: capture);
      final bytes = (await rootBundle.load('assets/test_catalog/flower.png'))
          .buffer
          .asUint8List();
      final context = tester.element(find.byType(TattooCard).first);
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ShareScreen(pages: [bytes, bytes]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('حفظ الصورة 1 / 2').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-next')));
      await tester.pumpAndSettle();
      expect(find.text('حفظ الصورة 2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-next')));
      await tester.pumpAndSettle();
      expect(find.text('فتح Instagram').hitTestable(), findsOneWidget);
      await screenshot(tester, capture, 'share');
      await tester.tap(find.text('تعديل'));
      await tester.pumpAndSettle();
      expect(find.byType(ShareScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );
}
