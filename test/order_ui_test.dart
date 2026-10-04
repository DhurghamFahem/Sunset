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
  Future<AppServices> services() async {
    SharedPreferences.setMockInitialValues({});
    final catalog = MemoryCatalog(products: [fixture(1)]);
    final analytics = NoopAnalytics();
    return AppServices(
      catalog: catalog,
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

  testWidgets('employee confirms on mobile and the booking message is copied', (
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
    final token = newOrderToken();
    final order = await app.orders.create(token, {'1': 2});
    await tester.pumpWidget(
      RepaintBoundary(child: wrap(app, OrderScreen(order: order))),
    );
    await tester.pumpAndSettle();
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
    expect(
      (await app.orders.get(order.id, token: token)).status,
      OrderStatus.confirmed,
    );
    expect(copied, contains(order.code));
    expect(copied, contains('10,000'));
    expect(tester.takeException(), isNull);
  });
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
