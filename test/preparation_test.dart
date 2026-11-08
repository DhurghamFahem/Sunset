import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/order.dart';
import 'package:sunset/repositories/order_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/admin/preparation_screen.dart';

import 'support/fixtures.dart';

class TestCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  bool denied = false;
  int stops = 0;
  int disposals = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox.expand();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  void emit(List<String> values) => captures.add(
    BarcodeCapture(
      barcodes: [
        for (final value in values)
          Barcode(rawValue: value, format: BarcodeFormat.qrCode),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryOrderRepository repo;
  late AppServices services;
  late TestCamera camera;
  late TattooOrder uploaded;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final catalog = MemoryCatalog(products: [fixture(1), fixture(2)]);
    repo = MemoryOrderRepository(catalog);
    final analytics = NoopAnalytics();
    services = AppServices(
      catalog: catalog,
      orders: repo,
      analytics: analytics,
      selection: SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      ),
    );
    var order = await repo.create(newOrderToken(), {'1': 2, '2': 1});
    order = await repo.save(order, {
      'status': 'confirmed',
      'customer_name': 'عميل التجهيز',
      'phone': '07701234567',
      'governorate': 'بغداد',
      'area': 'المنصور',
      'delivery_notes': 'اتصل قبل التوصيل',
    });
    uploaded = await repo.requestPrimeUpload(order);
    camera = TestCamera();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    services.selection.dispose();
    await camera.captures.close();
  });

  Widget app() => AppScope(
    services: services,
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(body: PreparationScreen()),
    ),
  );
  Future<void> lookup(WidgetTester tester, String value) async {
    await tester.enterText(
      find.byKey(const ValueKey('prime-case-input')),
      value,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  Future<void> pack(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pack-order')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('pack-order')));
    await tester.pumpAndSettle();
  }

  test('Prime lookup is exact and trims scanner whitespace', () async {
    expect(
      (await repo.getByPrimeCaseId(' ${uploaded.primeCaseId}\n')).id,
      uploaded.id,
    );
    for (final value in [
      '',
      uploaded.code,
      uploaded.primeCaseId!.substring(5),
      'unknown',
    ]) {
      await expectLater(
        repo.getByPrimeCaseId(value),
        throwsA(isA<OrderException>()),
      );
    }
  });

  testWidgets('camera scan displays the order and packs it once on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.tap(find.text('مسح QR بالكاميرا'));
    await tester.pumpAndSettle();
    expect(find.byType(PrimeQrScanner), findsOneWidget);
    camera.emit([uploaded.primeCaseId!, 'another-label']);
    await tester.pumpAndSettle();
    expect(find.byType(PrimeQrScanner), findsOneWidget);
    camera.emit([uploaded.primeCaseId!]);
    camera.emit([uploaded.primeCaseId!]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(PrimeQrScanner), findsNothing);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(find.byType(PrimeQrScanner, skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(camera.stops + camera.disposals, greaterThan(0));
    expect(find.text('عميل التجهيز'), findsOneWidget);
    expect(find.text('إجمالي القطع: 3'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('الكمية: 2'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('رمز الوشم: G2G-001'), findsOneWidget);
    await pack(tester);
    expect((await repo.get(uploaded.id)).status, OrderStatus.packed);
    expect((await repo.get(uploaded.id)).version, uploaded.version + 1);
    expect(find.byKey(const ValueKey('pack-order')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prime-case-input')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await lookup(tester, uploaded.primeCaseId!);
    await tester.scrollUntilVisible(
      find.text('هذا الطلب مغلّف مسبقاً. امسح الطلب التالي.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('pack-order')), findsNothing);
    expect((await repo.get(uploaded.id)).version, uploaded.version + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown scan clears the previous order; stale pack requires re-read',
    (tester) async {
      await tester.pumpWidget(app());
      await lookup(tester, uploaded.primeCaseId!);
      await lookup(tester, 'missing');
      expect(find.text('لا يوجد طلب بهذا الرقم في برايم'), findsOneWidget);
      expect(find.text('عميل التجهيز'), findsNothing);
      expect(find.byKey(const ValueKey('pack-order')), findsNothing);
      await lookup(tester, uploaded.primeCaseId!);
      final updated = await repo.save(uploaded, {
        'delivery_notes': 'Changed by coworker',
      });
      await pack(tester);
      expect((await repo.get(uploaded.id)).status, OrderStatus.uploaded);
      expect(find.byKey(const ValueKey('pack-order')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('prime-case-input')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await lookup(tester, uploaded.primeCaseId!);
      await pack(tester);
      expect((await repo.get(uploaded.id)).version, updated.version + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled order cannot be packed', (tester) async {
    await repo.save(uploaded, {'status': 'cancelled'});
    await tester.pumpWidget(app());
    await lookup(tester, uploaded.primeCaseId!);
    await tester.scrollUntilVisible(
      find.text('لا يمكن تجهيز هذا الطلب بحالته الحالية: ملغي'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('pack-order')), findsNothing);
  });

  testWidgets('camera permission failure allows manual entry', (tester) async {
    camera.denied = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('مسح QR بالكاميرا'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الرجوع وإدخال الرقم يدوياً'));
    await tester.pumpAndSettle();
    await lookup(tester, uploaded.primeCaseId!);
    expect(find.text('عميل التجهيز'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
