import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/models/order.dart';
import 'package:sunset/repositories/order_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryOrderRepository repo;
  setUp(
    () => repo = MemoryOrderRepository(
      MemoryCatalog(products: [fixture(1), fixture(2, price: null)]),
    ),
  );
  const details = {
    'phone': '07701234567',
    'governorate': 'بغداد',
    'area': 'المنصور',
    'status': 'confirmed',
  };
  test('concurrent retries share one order, unique codes, quantities, delivery snapshot', () async {
    await repo.setDeliveryCost(5000);
    final token = newOrderToken();
    final results = await Future.wait(
      List.generate(8, (_) => repo.create(token, {'1': 3})),
    );
    expect(results.map((o) => o.id).toSet().length, 1);
    expect(results.first.code, matches(RegExp(r'^[A-Z0-9]{4}$')));
    expect(results.first.total, 20000);
    await repo.setDeliveryCost(3000);
    expect((await repo.get(results.first.id)).deliveryCost, 5000);
    final next = await repo.create(newOrderToken(), {'1': 1});
    expect(next.code, isNot(results.first.code));
    expect(next.deliveryCost, 3000);
    await expectLater(
      repo.get(next.id, token: newOrderToken()),
      throwsA(isA<OrderException>()),
    );
  });
  test(
    'booking requirements, customer price tampering and missing price',
    () async {
      final token = newOrderToken();
      final pending = await repo.create(token, {'1': 2});
      await expectLater(
        repo.save(pending, {'status': 'confirmed'}, token: token),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(pending, {...details, 'final_total': 1}, token: token),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(pending, details, token: token),
        throwsA(isA<OrderException>()),
      );
      for (final key in [
        'phone',
        'governorate',
        'area',
        'customer_name',
        'username',
        'source',
      ]) {
        await expectLater(
          repo.save(pending, {
            key: 'test',
            'status': 'cancelled',
          }, token: token),
          throwsA(isA<OrderException>()),
        );
      }
      await expectLater(
        repo.save(pending, {'status': 'confirmed'}),
        throwsA(isA<OrderException>()),
      );
      final booked = await repo.save(pending, details);
      expect(booked.status, OrderStatus.confirmed);
      final readyToken = newOrderToken();
      final customerOrder = await repo.create(readyToken, {'1': 1});
      final filled = await repo.save(customerOrder, {
        ...details,
        'status': 'pending',
      });
      await expectLater(
        repo.save(filled, {'status': 'confirmed'}, token: readyToken),
        throwsA(isA<OrderException>()),
      );

      expect(booked.bookingMessage, contains(booked.code));
      expect(booked.bookingMessage, contains('× 2'));
      final unpriced = await repo.create(newOrderToken(), {'2': 1});
      await expectLater(
        repo.save(unpriced, details),
        throwsA(isA<OrderException>()),
      );
      final priced = await repo.save(unpriced, {
        ...details,
        'items': [
          {
            ...unpriced.items.single.toJson(),
            'original_price': 4000,
            'unit_price': 3500,
          },
        ],
      });
      expect(priced.discount, 500);
    },
  );
  test(
    'discount math, quantity edits, immutable original, stale writes',
    () async {
      await repo.setDeliveryCost(5000);
      final order = await repo.create(newOrderToken(), {'1': 2});
      final changed = await repo.save(order, {
        ...details,
        'items': [
          {...order.items.single.toJson(), 'quantity': 3, 'unit_price': 4000},
        ],
        'final_total': 15000,
      });
      expect(changed.originalTotal, 20000);
      expect(changed.itemDiscount, 3000);
      expect(changed.extraDiscount, 2000);
      expect(changed.discount, 5000);
      expect(changed.total, 15000);
      await expectLater(
        repo.save(order, details),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(changed, {'final_total': 18000}),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(changed, {
          'items': [
            {...changed.items.single.toJson(), 'original_price': 6000},
          ],
        }),
        throwsA(isA<OrderException>()),
      );
    },
  );
  test(
    'packing, shipping, partial acceptance, reporting and terminal states',
    () async {
      await repo.setDeliveryCost(5000);
      await repo.saveEmployee(name: 'موظف', phone: '07701234567');
      final employee = (await repo.employees()).single;
      var order = await repo.create(newOrderToken(), {'1': 3});
      order = await repo.save(order, {
        ...details,
        'employee_id': employee.id,
        'final_total': 17000,
      });
      await expectLater(
        repo.save(order, {'status': 'delivered'}),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {'status': 'packed'});
      order = await repo.save(order, {'status': 'shipped'});
      await expectLater(
        repo.save(order, {'status': 'cancelled'}),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(order, {'final_total': 100}),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(order, {'status': 'partial'}),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {
        'status': 'partial',
        'items': [
          {...order.items.single.toJson(), 'accepted_quantity': 1},
        ],
      });
      expect(order.acceptedTotal, 9000);
      final stats = (await repo.performance()).singleWhere(
        (r) => r['name'] == employee.name,
      );
      expect(stats['revenue'], 9000);
      expect(stats['accepted_pieces'], 1);
      await expectLater(
        repo.save(order, {'status': 'partial'}),
        throwsA(isA<OrderException>()),
      );
    },
  );
  test(
    'customer can cancel until shipped; fully delivered and rejected counts',
    () async {
      for (final state in [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.packed,
      ]) {
        final token = newOrderToken();
        var order = await repo.create(token, {'1': 2});
        if (state != OrderStatus.pending) {
          order = await repo.save(order, details);
        }
        if (state == OrderStatus.packed) {
          order = await repo.save(order, {'status': 'packed'});
        }
        order = await repo.save(order, {'status': 'cancelled'}, token: token);
        expect(order.status, OrderStatus.cancelled);
      }
      for (final state in [OrderStatus.delivered, OrderStatus.rejected]) {
        var order = await repo.create(newOrderToken(), {'1': 2});
        order = await repo.save(order, details);
        order = await repo.save(order, {'status': 'packed'});
        order = await repo.save(order, {'status': 'shipped'});
        order = await repo.save(order, {'status': state.name});
        expect(
          order.items.single.acceptedQuantity,
          state == OrderStatus.delivered ? 2 : 0,
        );
      }
    },
  );
  test(
    'selection counts and failed-export request identity survive reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SelectionStore(prefs, NoopAnalytics());
      store.toggle(fixture(1));
      store.setQuantity('1', 4);
      await store.flush();
      final token = await store.exportToken();
      final restored = SelectionStore(prefs, NoopAnalytics());
      expect(restored.pieces, 4);
      expect(await restored.exportToken(), token);
      await restored.rememberOrder('order', token);
      expect(restored.savedOrders.single.token, token);
      await restored.finishExport();
      expect(await restored.exportToken(), isNot(token));
    },
  );
  test(
    'customer receipt accepts quantities without permission to alter prices',
    () async {
      final token = newOrderToken();
      var order = await repo.create(token, {'1': 3});
      order = await repo.save(order, details);
      order = await repo.save(order, {'status': 'packed'});
      order = await repo.save(order, {'status': 'shipped'});
      await expectLater(
        repo.save(order, {
          'status': 'partial',
          'items': [
            {
              ...order.items.single.toJson(),
              'unit_price': 1,
              'accepted_quantity': 1,
            },
          ],
        }, token: token),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {
        'status': 'partial',
        'items': [
          {...order.items.single.toJson(), 'accepted_quantity': 1},
        ],
      }, token: token);
      expect(order.items.single.acceptedQuantity, 1);
    },
  );
}
