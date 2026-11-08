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
import 'package:sunset/models/prime_location.dart';
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
  Future<AppServices> services({
    bool loseManualResponse = false,
    OrderRepository? repository,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final catalog = MemoryCatalog(products: [fixture(1), fixture(2)]);
    final analytics = NoopAnalytics();
    return AppServices(
      catalog: catalog,
      orders:
          repository ??
          (loseManualResponse ? LostManualResponseRepository(catalog) : null),
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

  testWidgets('staff replaces tattoos and saves the existing packed order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await services();
    var order = await app.orders.create(newOrderToken(), {'1': 1});
    order = await app.orders.save(order, {
      'phone': '07701234567',
      'governorate': 'بغداد',
      'area': 'المنصور',
      'status': 'confirmed',
      'final_total': 4000,
    });
    order = await app.orders.save(order, {'status': 'uploaded'});
    order = await app.orders.save(order, {'status': 'packed'});
    await tester.pumpWidget(wrap(app, OrderScreen(order: order)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إزالة ${fixture(1).displayName}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة وشومات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إضافة ${fixture(2).displayName}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quantity-2')), '2');
    await tester.tap(find.text('إضافة إلى الطلب'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-item-1')), findsNothing);
    expect(find.byKey(const ValueKey('order-item-2')), findsOneWidget);
    expect((await app.orders.get(order.id)).items.single.productId, '1');
    final save = find.text('حفظ التعديلات');
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = await app.orders.get(order.id);
    expect(saved.items.single.productId, '2');
    expect(saved.pieces, 2);
    expect(saved.total, 10000);
    expect(saved.finalTotal, isNull);
    expect(saved.status, OrderStatus.packed);
    expect((await app.orders.list()).length, 1);
    final ship = find.widgetWithText(FilledButton, OrderStatus.shipped.label);
    await tester.ensureVisible(ship);
    await tester.pumpAndSettle();
    await tester.tap(ship);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('الوشومات'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('إضافة وشومات'), findsNothing);
    expect(find.byTooltip('إزالة ${fixture(2).displayName}'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
      if (label == 'المحافظة *' || label == 'المنطقة *') {
        final picker = find.widgetWithText(
          DropdownMenuFormField<PrimeLocation>,
          label,
        );
        await tester.ensureVisible(picker);
        await tester.tap(
          find.descendant(of: picker, matching: find.byType(TextField)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: picker, matching: find.byType(TextField)),
          text,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
        return;
      }
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
    await fill('المنطقة *', 'المنصور');
    await fill('أقرب نقطة دالة', 'قرب جامع الرحمن');
    await fill('ملاحظات للمندوب (اختياري)', 'الاتصال قبل الوصول');
    final paidSwitch = find.widgetWithText(
      SwitchListTile,
      'مدفوع بالكامل (مع التوصيل)',
    );
    await tester.ensureVisible(paidSwitch);
    await tester.tap(paidSwitch);
    await tester.pumpAndSettle();
    final source = find.byType(DropdownButtonFormField<OrderSource>);
    expect(
      tester.widget<DropdownButtonFormField<OrderSource>>(source).initialValue,
      OrderSource.instagram,
    );
    final confirm = find.text('حفظ وتأكيد الطلب للرفع إلى برايم');
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
    expect(copied, contains('أقرب نقطة دالة: قرب جامع الرحمن'));
    expect(copied, contains('ملاحظات للمندوب: الاتصال قبل الوصول'));
    expect(find.widgetWithText(FilledButton, 'مرفوع للتوصيل'), findsNothing);
    final confirmed = await app.orders.get(order.id);
    expect(confirmed.isPaid, isTrue);
    expect(confirmed.collectAmount, 0);
    expect(confirmed.primeStateId, 'BGD');
    expect(confirmed.primeDistrictId, 17);
    expect(confirmed.customerName, confirmed.code);
    expect(confirmed.status, OrderStatus.confirmed);
    expect(confirmed.landmark, 'قرب جامع الرحمن');
    expect(confirmed.deliveryNotes, 'الاتصال قبل الوصول');
    // Simulate a server worker receipt while this screen stays open.
    await app.orders.save(confirmed, {'status': 'uploaded'});
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('تم التغليف'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.text('${order.code} • ${OrderStatus.uploaded.label}'),
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
      await tester.scrollUntilVisible(
        find.text('إلغاء الطلب'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
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
    'confirmed orders can request Prime upload and refresh the returned ID',
    (tester) async {
      final repo = QueuedPrimeOrders(MemoryCatalog(products: [fixture(1)]));
      final app = await services(repository: repo);
      addTearDown(app.selection.dispose);
      var order = await repo.create(newOrderToken(), {'1': 1});
      order = await repo.save(order, {
        'status': 'confirmed',
        'phone': '07701234567',
        'governorate': 'بغداد',
        'area': 'المنصور',
        'prime_state_id': 'BGD',
        'prime_district_id': 17,
      });
      await tester.pumpWidget(wrap(app, OrderScreen(order: order)));
      await tester.pumpAndSettle();
      final button = find.text('رفع الطلب إلى برايم');
      final notes = find.widgetWithText(
        TextFormField,
        'ملاحظات للمندوب (اختياري)',
      );
      await tester.scrollUntilVisible(
        notes,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(notes, 'Saved before upload');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect((await repo.get(order.id)).deliveryNotes, 'Saved before upload');
      expect(button, findsOneWidget);
      // A returned ID and status must refresh without discarding subsequent edits.
      await tester.scrollUntilVisible(
        notes,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(notes, 'Unsaved next edit');
      repo.completed = true;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(notes).controller!.text,
        'Unsaved next edit',
      );
      await tester.scrollUntilVisible(
        find.text('تم التغليف'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Prime upload button is hidden for customers, pending orders and existing IDs',
    (tester) async {
      final app = await services();
      addTearDown(app.selection.dispose);
      final token = newOrderToken();
      final pending = await app.orders.create(token, {'1': 1});
      final confirmed = await app.orders.save(pending, {
        'status': 'confirmed',
        'phone': '07701234567',
        'governorate': 'بغداد',
        'area': 'المنصور',
        'prime_state_id': 'BGD',
        'prime_district_id': 17,
      });
      for (final screen in [
        OrderScreen(order: pending),
        OrderScreen(order: confirmed, token: token),
        OrderScreen(
          order: TattooOrder.fromJson({
            ...confirmed.toJson(),
            'prime_case_id': '987654',
          }),
        ),
      ]) {
        await tester.pumpWidget(wrap(app, screen));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -6000),
        );
        await tester.pumpAndSettle();
        expect(find.text('رفع الطلب إلى برايم'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('main Prime settings validate, save and preserve credentials', (
    tester,
  ) async {
    final app = await services();
    addTearDown(app.selection.dispose);
    Future<void> open() async {
      await tester.pumpWidget(
        wrap(app, const Scaffold(body: OrderManagement(section: 'settings'))),
      );
      await tester.pumpAndSettle();
    }

    await open();
    final username = find.widgetWithText(
      TextFormField,
      'اسم المستخدم في برايم',
    );
    final password = find.widgetWithText(TextFormField, 'كلمة مرور برايم');
    final save = find.widgetWithText(FilledButton, 'حفظ حساب برايم');
    Future<void> fill(Finder field, String text) async {
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    Future<void> submit() async {
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    await fill(username, 'main-prime');
    await submit();
    expect(find.text('أدخل كلمة مرور برايم'), findsOneWidget);
    expect((await app.orders.mainPrimeAccount()).configured, isFalse);
    await fill(password, 'main-secret');
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: password, matching: find.byType(TextField)),
          )
          .obscureText,
      isTrue,
    );
    await submit();
    expect((await app.orders.mainPrimeAccount()).username, 'main-prime');
    expect((await app.orders.mainPrimeAccount()).configured, isTrue);
    expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
    await submit();
    expect((await app.orders.mainPrimeAccount()).configured, isTrue);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(
      tester.widget<TextFormField>(username).controller!.text,
      'main-prime',
    );
    expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
    await fill(username, 'renamed-prime');
    await submit();
    expect(find.text('أدخل كلمة مرور برايم'), findsOneWidget);
    expect((await app.orders.mainPrimeAccount()).username, 'main-prime');
    await fill(username, '');
    await submit();
    expect((await app.orders.mainPrimeAccount()).configured, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'admin can change quantities and combine discounts before confirming',
    (tester) async {
      final app = await services();
      await app.orders.setDeliveryCost(5000);
      final order = await app.orders.create(newOrderToken(), {'1': 2});
      await tester.pumpWidget(wrap(app, OrderScreen(order: order)));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String text) async {
        if (label == 'المحافظة *' || label == 'المنطقة *') {
          final picker = find.widgetWithText(
            DropdownMenuFormField<PrimeLocation>,
            label,
          );
          await tester.ensureVisible(picker);
          await tester.tap(
            find.descendant(of: picker, matching: find.byType(TextField)),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(of: picker, matching: find.byType(TextField)),
            text,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(text).last);
          await tester.pumpAndSettle();
          return;
        }
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
      await fill('المنطقة *', 'المنصور');
      await fill('أقرب نقطة دالة', 'قرب جامع الرحمن');
      await fill('ملاحظات للمندوب (اختياري)', 'الاتصال قبل الوصول');
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

class QueuedPrimeOrders extends MemoryOrderRepository {
  QueuedPrimeOrders(super.catalog);
  int requests = 0;
  bool completed = false;
  @override
  Future<TattooOrder> requestPrimeUpload(TattooOrder order) async {
    requests++;
    return order;
  }

  @override
  Future<TattooOrder> get(String id, {String? token}) async {
    final order = await super.get(id, token: token);
    return completed
        ? TattooOrder.fromJson({
            ...order.toJson(),
            'status': 'uploaded',
            'prime_case_id': '987654',
            'version': order.version + 1,
          })
        : order;
  }
}
