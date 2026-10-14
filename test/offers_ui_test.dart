import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/app.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/services/test_admin_service.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/admin/offer_editor.dart';
import 'package:sunset/ui/offers_screen.dart';
import 'package:sunset/ui/theme.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'Tajawal': 'assets/fonts/Tajawal-Regular.ttf',
      'ElMessiri': 'assets/fonts/ElMessiri-700.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  Future<AppServices> services() async {
    SharedPreferences.setMockInitialValues({});
    final catalog = TestCatalogRepository();
    final admin = TestAdminService(catalog);
    await admin.signIn('test@gmail.com', '1234');
    addTearDown(admin.dispose);
    final analytics = NoopAnalytics();
    return AppServices(
      catalog: catalog,
      admin: admin,
      analytics: analytics,
      selection: SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      ),
    );
  }

  Widget wrap(AppServices app, Widget screen) => AppScope(
    services: app,
    child: MaterialApp(
      theme: catalogTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: screen),
    ),
  );

  testWidgets(
    'create multiple-tattoo offer across searches, edit to one, publish and hide',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await services();
      final tattoos = [
        ...await app.catalog.products(const CatalogQuery(admin: true)),
        ...await app.catalog.products(
          const CatalogQuery(admin: true, offset: 24),
        ),
      ];
      await tester.pumpWidget(wrap(app, const OffersScreen(admin: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة عرض'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'اسم العرض'),
        'عرض الصيف',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'سعر العرض الكامل (د.ع)'),
        '12000',
      );
      await tester.tap(find.byKey(const ValueKey('save-offer')));
      await tester.pumpAndSettle();
      expect(find.text('اختار وشماً واحداً على الأقل للعرض.'), findsOneWidget);
      final search = find.widgetWithText(
        TextField,
        'ابحث عن وشم أو رقم التصميم',
      );
      for (final p in [tattoos.first, tattoos.last]) {
        await tester.ensureVisible(search);
        await tester.enterText(search, p.code);
        await tester.pumpAndSettle();
        final checkbox = find.byKey(ValueKey('offer-product-${p.id}'));
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('save-offer')));
      await tester.tap(find.byKey(const ValueKey('save-offer')));
      await tester.pumpAndSettle();
      expect(find.byType(OfferEditor), findsNothing);
      expect((await app.offers.list()).single.products, hasLength(2));
      expect(find.text('عرض الصيف'), findsOneWidget);
      await tester.tap(find.text('تعديل العرض'));
      await tester.pumpAndSettle();
      final chip = find.byKey(ValueKey('selected-${tattoos.last.id}'));
      await tester.ensureVisible(chip);
      await tester.tap(
        find.descendant(of: chip, matching: find.byTooltip('حذف')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-offer')));
      await tester.tap(find.byKey(const ValueKey('save-offer')));
      await tester.pumpAndSettle();
      expect((await app.offers.list()).single.products, hasLength(1));
      await tester.pumpWidget(wrap(app, const OffersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('عرض الصيف'), findsOneWidget);
      expect(find.text('استفسر عن العرض على واتساب'), findsOneWidget);
      expect(find.text('تعديل العرض'), findsNothing);
      expect(app.selection.count, 0);
      final offer = (await app.offers.list()).single;
      await app.offers.save(
        id: offer.id,
        name: offer.name,
        price: offer.price,
        productIds: offer.products.map((p) => p.id).toList(),
        active: false,
      );
      await tester.tap(find.byTooltip('تحديث العروض'));
      await tester.pumpAndSettle();
      expect(find.text('عرض الصيف'), findsNothing);
      expect(find.text('ماكو عروض حالياً'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('customer offers route and navigation fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await services();
    final tattoos = await app.catalog.products(const CatalogQuery());
    await app.offers.save(
      id: 'bundle',
      name: 'عرض الورود',
      price: 12000,
      productIds: tattoos.take(3).map((p) => p.id).toList(),
      active: true,
    );
    await app.offers.save(
      id: 'single',
      name: 'عرض الوشم الواحد',
      price: 4000,
      productIds: [tattoos.first.id],
      active: true,
    );
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: G2GApp(services: app),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-offers')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('إنستغرام').hitTestable(), findsOneWidget);
    expect(find.text('واتساب').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('العرض التالي'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('offers-pages')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('إيقاف التنقل التلقائي'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('تشغيل التنقل التلقائي'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_UX')) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('test-results').create(recursive: true);
        await File('test-results/offers-home-mobile.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('كل العروض'));
    await tester.pumpAndSettle();
    expect(find.text('عرض الورود'), findsOneWidget);
    expect(find.text('عرض الوشم الواحد'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_UX')) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('test-results').create(recursive: true);
        await File('test-results/offers-mobile.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
