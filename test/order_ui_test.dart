import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/order.dart';
import 'package:sunset/repositories/order_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/order_screen.dart';
import 'package:sunset/ui/admin/order_management.dart';
import 'package:sunset/ui/theme.dart';

import 'support/fixtures.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Tajawal',
    )..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))).load();
    await (FontLoader(
      'ElMessiri',
    )..addFont(rootBundle.load('assets/fonts/ElMessiri-700.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    ),
  );
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  Future<AppServices> services({bool loseManualResponse = false}) async {
    SharedPreferences.setMockInitialValues({});
    final catalog = MemoryCatalog(products: [fixture(1)]);
    final analytics = NoopAnalytics();
    return AppServices(
      catalog: catalog,
      orders: loseManualResponse ? LostManualResponseRepository(catalog) : null,
      analytics: analytics,
      selection: SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      ),
    );
  }

  Widget wrap(AppServices app, Widget child) => AppScope(
    services: app,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: catalogTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UX')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('test-results').create(recursive: true);
      await File('test-results/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('employee creates and confirms a manual order on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = await services();
    app.selection.toggle(fixture(1));
    app.selection.setQuantity('1', 7);
    await tester.pumpWidget(
      RepaintBoundary(
        child: wrap(
          app,
          const Scaffold(body: OrderManagement(section: 'orders')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة طلب يدوي'));
    await tester.pumpAndSettle();
    final createButton = find.widgetWithText(
      FilledButton,
      'إنشاء الطلب وإكمال البيانات',
    );
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);
    await tester.tap(find.byTooltip('إضافة ${fixture(1).displayName}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quantity-1')), '0');
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('أدخل كمية من 1 إلى 99'), findsOneWidget);
    expect(await app.orders.list(), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('quantity-1')), '2');
    await tester.pumpAndSettle();
    await capture(tester, 'manual-order-mobile');
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    final order = (await app.orders.list()).single;
    expect(order.pieces, 2);
    expect(app.selection.quantity('1'), 7);
    expect(app.selection.savedOrders, isEmpty);
    expect(find.text('رمز الوشم: ${fixture(1).code}'), findsOneWidget);
    await capture(tester, 'order-employee');
    Future<void> fill(String label, String text) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.scrollUntilVisible(
        field,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field, text);
    }

    await fill('رقم الهاتف *', '07701234567');
    await fill('المحافظة *', 'بغداد');
    await fill('المنطقة والعنوان التفصيلي *', 'المنصور');
    final source = find.byType(DropdownButtonFormField<OrderSource>);
    expect(
      tester.widget<DropdownButtonFormField<OrderSource>>(source).initialValue,
      OrderSource.instagram,
    );
    final confirm = find.text('تأكيد الطلب ونسخ الرسالة');
    await tester.scrollUntilVisible(
      confirm,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await capture(tester, 'order-confirmed');
    expect((await app.orders.get(order.id)).status, OrderStatus.confirmed);
    expect(copied, contains(order.code));
    expect(copied, contains('10,000'));
    expect(copied, isNot(contains('خصم القطع:')));
    expect(copied, isNot(contains('خصم إضافي:')));
    expect(copied, isNot(contains('إجمالي الخصم:')));
    expect((await app.orders.get(order.id)).source, OrderSource.instagram);
    expect((await app.orders.get(order.id)).items.single.code, fixture(1).code);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.text('${order.code} • ${OrderStatus.confirmed.label}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'manual order retry recovers a committed order without duplication',
    (tester) async {
      final app = await services(loseManualResponse: true);
      await tester.pumpWidget(
        wrap(app, const Scaffold(body: OrderManagement(section: 'orders'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة طلب يدوي'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'بحث باسم الوشم أو رمزه'),
        fixture(1).code,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('إضافة ${fixture(1).displayName}'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('إزالة ${fixture(1).displayName}'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quantity-1')), findsNothing);
      await tester.tap(find.byTooltip('إضافة ${fixture(1).displayName}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنشاء الطلب وإكمال البيانات'));
      await tester.pumpAndSettle();
      expect((await app.orders.list()).length, 1);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('quantity-1')))
            .enabled,
        false,
      );
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect((await app.orders.list()).length, 1);
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'customers track orders without completion fields or confirmation',
    (tester) async {
      final app = await services();
      final token = newOrderToken();
      final order = await app.orders.create(token, {'1': 2});
      await tester.pumpWidget(
        wrap(app, OrderScreen(order: order, token: token)),
      );
      await tester.pumpAndSettle();
      expect(find.text('طلبك محفوظ بانتظار تأكيد الموظف.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('تأكيد الطلب ونسخ الرسالة'), findsNothing);
      expect(find.text('معلومات العميل والتوصيل'), findsNothing);
      expect(find.text('إلغاء الطلب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final section in ['orders', 'team', 'settings']) {
    testWidgets('admin $section fits a narrow viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await services();
      await app.orders.create(newOrderToken(), {'1': 2});
      await tester.pumpWidget(
        RepaintBoundary(
          child: wrap(app, Scaffold(body: OrderManagement(section: section))),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'admin-$section');
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }
  testWidgets(
    'admin can change quantities and combine discounts before confirming',
    (tester) async {
      final app = await services();
      await app.orders.setDeliveryCost(5000);
      final order = await app.orders.create(newOrderToken(), {'1': 2});
      await tester.pumpWidget(wrap(app, OrderScreen(order: order)));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String text) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.scrollUntilVisible(
          field,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(field, text);
      }

      await fill('الكمية (1–99)', '3');
      await fill('سعر القطعة بعد الخصم', '4000');
      await fill('رقم الهاتف *', '07701234567');
      await fill('المحافظة *', 'بغداد');
      await fill('المنطقة والعنوان التفصيلي *', 'المنصور');
      await fill('المبلغ النهائي (اتركه فارغاً للحساب التلقائي)', '15000');
      final button = find.text('تأكيد الطلب ونسخ الرسالة');
      await tester.scrollUntilVisible(
        button,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final saved = await app.orders.get(order.id);
      expect(saved.status, OrderStatus.confirmed);
      expect(saved.pieces, 3);
      expect(saved.discount, 5000);
      expect(tester.takeException(), isNull);
    },
  );
}

class LostManualResponseRepository extends MemoryOrderRepository {
  LostManualResponseRepository(super.catalog);
  bool lost = false;

  @override
  Future<TattooOrder> createManual(
    String token,
    Map<String, int> quantities,
  ) async {
    final order = await super.createManual(token, quantities);
    if (!lost) {
      lost = true;
      throw StateError('Response lost after commit');
    }
    return order;
  }
}
