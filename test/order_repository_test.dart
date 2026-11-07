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
  test('saving a completed manual order confirms it; incomplete drafts stay pending', () async {
    var manual = await repo.createManual(newOrderToken(), {'1': 1});
    manual = await repo.save(manual, {'customer_name': 'Draft'});
    expect(manual.status, OrderStatus.pending);
    manual = await repo.save(manual, {
      ...details,
      'status': 'pending',
      'prime_state_id': 'BGD',
      'prime_district_id': 17,
    });
    expect(manual.status, OrderStatus.confirmed);
    final savedAgain = await repo.save(manual, {
      'delivery_notes': 'Call first',
    });
    expect(savedAgain.status, OrderStatus.confirmed);
    var customer = await repo.create(newOrderToken(), {'1': 1});
    customer = await repo.save(customer, {
      ...details,
      'status': 'pending',
      'prime_state_id': 'BGD',
      'prime_district_id': 17,
    });
    expect(customer.status, OrderStatus.pending);
  });
  test(
    'staff can add, remove and replace tattoos in every pre-shipping status',
    () async {
      final token = newOrderToken();
      var order = await repo.create(token, {'1': 1});
      final original = order.items.single.toJson();
      final addition = {
        'product_id': '2',
        'name': fixture(2).displayName,
        'code': fixture(2).code,
        'quantity': 2,
        'original_price': 3000,
        'unit_price': 2500,
        'accepted_quantity': 0,
      };
      for (final status in [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.uploaded,
        OrderStatus.packed,
      ]) {
        if (status != OrderStatus.pending) {
          order = await repo.save(order, {...details, 'status': status.name});
        }
        order = await repo.save(order, {
          'items': [addition, original],
        });
        expect(order.pieces, 3);
        expect(order.subtotal, 10000);
        await expectLater(
          repo.save(order, {
            'items': [original],
          }, token: token),
          throwsA(isA<OrderException>()),
        );
        order = await repo.save(order, {
          'items': [addition],
        });
        expect(order.items.single.productId, '2');
        order = await repo.save(order, {
          'items': [original],
        });
        expect(order.status, status);
      }
      final stale = order;
      order = await repo.save(order, {'status': 'shipped'});
      await expectLater(
        repo.save(stale, {
          'items': [addition],
        }),
        throwsA(isA<OrderException>()),
      );
      for (final items in [
        [addition],
        [original, addition],
        <Map<String, dynamic>>[],
      ]) {
        await expectLater(
          repo.save(order, {'items': items}),
          throwsA(isA<OrderException>()),
        );
      }
      expect((await repo.get(order.id)).items.single.productId, '1');
    },
  );

  test('selection changes reject empty, duplicate, unavailable and forged snapshots', () async {
    var order = await repo.create(newOrderToken(), {'2': 1});
    final item = {
      'product_id': '1',
      'name': fixture(1).displayName,
      'code': fixture(1).code,
      'quantity': 1,
      'original_price': 5000,
      'unit_price': 4000,
    };
    for (final items in [
      [],
      [item, item],
      [
        {...item, 'product_id': 'missing'},
      ],
      [
        {...item, 'original_price': 6000},
      ],
      [
        {...item, 'name': 'forged'},
      ],
      [
        {...item, 'quantity': 0},
      ],
      [
        {...item, 'accepted_quantity': 1},
      ],
      List.generate(101, (i) => {...item, 'product_id': '$i'}),
    ]) {
      await expectLater(
        repo.save(order, {'items': items}),
        throwsA(isA<OrderException>()),
      );
    }
    order = await repo.save(order, {
      'items': [item],
    });
    // Retained snapshots remain valid even if the tattoo leaves the catalog.
    (repo.catalog as MemoryCatalog).data.clear();
    order = await repo.save(order, {
      'items': [
        {...item, 'quantity': 3},
      ],
    });
    expect(order.subtotal, 12000);
    expect(order.items.single.originalPrice, 5000);
  });
  test(
    'delivery upload preserves details and follows staff permissions',
    () async {
      final token = newOrderToken();
      var order = await repo.create(token, {'1': 1});
      expect(order.landmark, isEmpty);
      expect(order.deliveryNotes, isEmpty);
      await expectLater(
        repo.save(order, {'status': 'uploaded'}),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {
        ...details,
        'landmark': 'قرب جامع الرحمن',
        'delivery_notes': 'الاتصال قبل الوصول',
      });
      await expectLater(
        repo.save(order, {'status': 'uploaded'}, token: token),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.save(order, {'status': 'packed'}),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {'status': 'uploaded'});
      expect(
        (await repo.list(status: OrderStatus.uploaded)).single.id,
        order.id,
      );
      expect(
        (await repo.get(order.id, token: token)).landmark,
        'قرب جامع الرحمن',
      );
      expect(
        order.bookingMessage,
        contains('ملاحظات للمندوب: الاتصال قبل الوصول'),
      );
      for (final key in ['landmark', 'delivery_notes']) {
        await expectLater(
          repo.save(order, {key: 'changed'}, token: token),
          throwsA(isA<OrderException>()),
        );
      }
      order = await repo.save(order, {'delivery_notes': 'الاتصال مرتين'});
      order = await repo.save(order, {'status': 'packed'});
      order = await repo.save(order, {'status': 'shipped'});
      for (final key in ['landmark', 'delivery_notes']) {
        await expectLater(
          repo.save(order, {key: 'changed'}),
          throwsA(isA<OrderException>()),
        );
      }
      expect(order.deliveryNotes, 'الاتصال مرتين');
    },
  );
  test('unnamed order items display codes while preserving snapshots', () {
    for (final name in [null, '', '  \t\n']) {
      final item = OrderItem.fromJson({
        'product_id': '1',
        'name': name,
        'code': '001-A',
        'quantity': 1,
        'original_price': 5000,
        'unit_price': 5000,
      });
      expect(item.displayName, '001-A');
      expect(item.toJson()['name'], name);
    }
  });
  test(
    'sharing destination is capability restricted, pending only and idempotent',
    () async {
      final token = newOrderToken();
      final order = await repo.create(token, {'1': 1});
      await expectLater(
        repo.setShareSource(order.id, newOrderToken(), OrderSource.whatsapp),
        throwsA(isA<OrderException>()),
      );
      await expectLater(
        repo.setShareSource(order.id, token, OrderSource.website),
        throwsA(isA<OrderException>()),
      );
      final whatsapp = await repo.setShareSource(
        order.id,
        token,
        OrderSource.whatsapp,
      );
      expect(whatsapp.source, OrderSource.whatsapp);
      expect(whatsapp.version, order.version + 1);
      expect(
        (await repo.setShareSource(
          order.id,
          token,
          OrderSource.whatsapp,
        )).version,
        whatsapp.version,
      );
      final instagram = await repo.setShareSource(
        order.id,
        token,
        OrderSource.instagram,
      );
      expect(instagram.source, OrderSource.instagram);
      await repo.save(instagram, details);
      await expectLater(
        repo.setShareSource(order.id, token, OrderSource.whatsapp),
        throwsA(isA<OrderException>()),
      );
      final manual = await repo.createManual(newOrderToken(), {'1': 1});
      expect(manual.source, OrderSource.instagram);
    },
  );
  test('concurrent retries share one order, unique codes, quantities, delivery snapshot', () async {
    await repo.setDeliveryCost(5000);
    final token = newOrderToken();
    final results = await Future.wait(
      List.generate(8, (_) => repo.create(token, {'1': 3})),
    );
    expect(results.map((o) => o.id).toSet().length, 1);
    expect(results.first.code, matches(RegExp(r'^[A-Z0-9]{4}$')));
    expect(results.first.total, 20000);
    expect(results.first.source, OrderSource.instagram);
    expect(results.first.items.single.code, fixture(1).code);
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
  for (final itemDiscount in [false, true]) {
    for (final extraDiscount in [false, true]) {
      test(
        'message discounts: items=$itemDiscount extra=$extraDiscount',
        () async {
          final order = await repo.create(newOrderToken(), {'1': 2});
          final unitPrice = itemDiscount ? 4000 : 5000;
          final saved = await repo.save(order, {
            ...details,
            'source': 'website',
            'items': [
              {...order.items.single.toJson(), 'unit_price': unitPrice},
            ],
            'final_total': unitPrice * 2 - (extraDiscount ? 1000 : 0),
          });
          expect(saved.bookingMessage.contains('خصم القطع:'), itemDiscount);
          expect(saved.bookingMessage.contains('خصم إضافي:'), extraDiscount);
          expect(
            saved.bookingMessage.contains('المجموع قبل الخصم:'),
            itemDiscount || extraDiscount,
          );
          expect(
            saved.bookingMessage.contains('إجمالي الخصم:'),
            itemDiscount || extraDiscount,
          );
          expect(saved.items.single.code, fixture(1).code);
          expect(saved.source, OrderSource.website);
        },
      );
    }
  }
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
      var order = await repo.create(newOrderToken(), {'1': 3});
      order = await repo.save(order, {...details, 'final_total': 17000});
      await expectLater(
        repo.save(order, {'status': 'delivered'}),
        throwsA(isA<OrderException>()),
      );
      order = await repo.save(order, {'status': 'uploaded'});
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
        (r) => r['name'] == 'بدون موظف',
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
        OrderStatus.uploaded,
        OrderStatus.packed,
      ]) {
        final token = newOrderToken();
        var order = await repo.create(token, {'1': 2});
        if (state != OrderStatus.pending) {
          order = await repo.save(order, details);
        }
        if ([OrderStatus.uploaded, OrderStatus.packed].contains(state)) {
          order = await repo.save(order, {'status': 'uploaded'});
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
        order = await repo.save(order, {'status': 'uploaded'});
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
      order = await repo.save(order, {'status': 'uploaded'});
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
