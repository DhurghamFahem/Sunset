import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/order.dart';
import 'package:sunset/models/prime_location.dart';
import 'package:sunset/repositories/order_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/widgets/prime_address_fields.dart';

import 'support/fixtures.dart';

class LocationOrders extends MemoryOrderRepository {
  LocationOrders(super.catalog);
  bool failStates = false;
  final pending = <String, Completer<List<PrimeLocation>>>{};
  @override
  Future<List<PrimeLocation>> primeLocations(
    String orderId, {
    String? stateId,
  }) {
    if (stateId == null && failStates) {
      return Future.error(const OrderException('تعذر الاتصال ببرايم'));
    }
    return pending[stateId]?.future ??
        super.primeLocations(orderId, stateId: stateId);
  }
}

void main() {
  Future<AppServices> services(LocationOrders orders) async {
    SharedPreferences.setMockInitialValues({});
    final analytics = NoopAnalytics();
    return AppServices(
      catalog: orders.catalog,
      orders: orders,
      analytics: analytics,
      selection: SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      ),
    );
  }

  Widget wrap(
    AppServices app,
    TattooOrder order,
    void Function(PrimeLocation?, PrimeLocation?) onChanged,
  ) => AppScope(
    services: app,
    child: MaterialApp(
      home: Scaffold(
        body: Form(
          child: PrimeAddressFields(
            order: order,
            enabled: true,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'changing states discards old districts and ignores a late response',
    (tester) async {
      final orders = LocationOrders(MemoryCatalog(products: [fixture(1)]));
      final app = await services(orders);
      final order = await orders.create(newOrderToken(), {'1': 1});
      orders.pending['BGD'] = Completer();
      orders.pending['BSR'] = Completer();
      PrimeLocation? selectedState, selectedDistrict;
      await tester.pumpWidget(
        wrap(app, order, (s, d) {
          selectedState = s;
          selectedDistrict = d;
        }),
      );
      await tester.pumpAndSettle();
      Future<void> chooseState(String name) async {
        await tester.tap(
          find.widgetWithText(
            DropdownButtonFormField<PrimeLocation>,
            'المحافظة *',
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(name).last);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await chooseState('بغداد');
      expect(selectedState?.id, 'BGD');
      expect(selectedDistrict, isNull);
      await chooseState('البصرة');
      expect(selectedState?.id, 'BSR');
      expect(selectedDistrict, isNull);
      orders.pending['BSR']!.complete(const [PrimeLocation('25', 'العشار')]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<PrimeLocation>,
          'المنطقة *',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('العشار').last);
      await tester.pumpAndSettle();
      expect(selectedDistrict?.id, '25');
      orders.pending['BGD']!.complete(const [PrimeLocation('17', 'المنصور')]);
      await tester.pumpAndSettle();
      expect(selectedState?.id, 'BSR');
      expect(selectedDistrict?.id, '25');
      expect(find.text('المنصور'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.selection.dispose();
    },
  );

  testWidgets('failed lookup can retry and restores existing IDs', (
    tester,
  ) async {
    final orders = LocationOrders(MemoryCatalog(products: [fixture(1)]));
    final app = await services(orders);
    final initial = await orders.create(newOrderToken(), {'1': 1});
    final order = await orders.save(initial, {
      'governorate': 'Old name',
      'area': 'Old district',
      'prime_state_id': 'BGD',
      'prime_district_id': 17,
    });
    orders.failStates = true;
    PrimeLocation? district;
    await tester.pumpWidget(wrap(app, order, (_, d) => district = d));
    await tester.pumpAndSettle();
    expect(find.text('تعذر الاتصال ببرايم'), findsOneWidget);
    expect(district, isNull);
    orders.failStates = false;
    await tester.tap(find.text('إعادة تحميل عناوين برايم'));
    await tester.pumpAndSettle();
    expect(district?.id, '17');
    expect(district?.name, 'المنصور');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.selection.dispose();
  });
}
