import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog.dart';
import '../models/order.dart';
import '../services/test_admin_service.dart';
import 'catalog_repository.dart';

String newOrderToken() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

abstract class OrderRepository {
  Future<TattooOrder> create(String token, Map<String, int> quantities);
  Future<TattooOrder> createManual(String token, Map<String, int> quantities);
  Future<TattooOrder> setShareSource(
    String id,
    String token,
    OrderSource source,
  );
  Future<TattooOrder> get(String id, {String? token});
  Future<TattooOrder> save(TattooOrder order, Json changes, {String? token});
  Future<List<TattooOrder>> list({
    String search = '',
    OrderStatus? status,
    int offset = 0,
  });
  Future<List<Employee>> employees();
  Future<void> saveEmployee({
    String? id,
    required String name,
    required String phone,
    required String email,
    String? password,
  });
  Future<int> deliveryCost();
  Future<void> setDeliveryCost(int cost);
  Future<List<Json>> performance();
}

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository(this.client);
  final SupabaseClient client;
  Future<TattooOrder> _rpc(String name, Json params) async {
    try {
      return TattooOrder.fromJson(
        Map<String, dynamic>.from(await client.rpc(name, params: params)),
      );
    } on PostgrestException catch (e) {
      if (e.message.startsWith('ORDER:')) {
        throw OrderException(e.message.substring(6));
      }
      rethrow;
    }
  }

  @override
  Future<TattooOrder> create(String token, Map<String, int> quantities) =>
      _rpc('create_selection_order', {
        'p_token': token,
        'p_items': quantities.entries
            .map((e) => {'product_id': e.key, 'quantity': e.value})
            .toList(),
      });
  @override
  Future<TattooOrder> createManual(String token, Map<String, int> quantities) =>
      _rpc('create_manual_order', {
        'p_token': token,
        'p_items': quantities.entries
            .map((e) => {'product_id': e.key, 'quantity': e.value})
            .toList(),
      });
  @override
  Future<TattooOrder> setShareSource(
    String id,
    String token,
    OrderSource source,
  ) => _rpc('set_order_share_source', {
    'p_id': id,
    'p_token': token,
    'p_source': source.name,
  });
  @override
  Future<TattooOrder> get(String id, {String? token}) =>
      _rpc('get_selection_order', {'p_id': id, 'p_token': token});
  @override
  Future<TattooOrder> save(TattooOrder order, Json changes, {String? token}) =>
      _rpc('update_selection_order', {
        'p_id': order.id,
        'p_version': order.version,
        'p_data': changes,
        'p_token': token,
      });
  @override
  Future<List<TattooOrder>> list({
    String search = '',
    OrderStatus? status,
    int offset = 0,
  }) async {
    final rows = await client.rpc(
      'list_selection_orders',
      params: {
        'p_search': search.trim(),
        'p_status': status?.name,
        'p_offset': offset,
      },
    );
    return (rows as List)
        .map((j) => TattooOrder.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  @override
  Future<List<Employee>> employees() async =>
      (await client.from('employees').select().order('name'))
          .map(Employee.fromJson)
          .toList();
  @override
  Future<void> saveEmployee({
    String? id,
    required String name,
    required String phone,
    required String email,
    String? password,
  }) async {
    try {
      await client.functions.invoke(
        'save-employee',
        body: {
          'id': id ?? newOrderToken(),
          'name': name.trim(),
          'phone': phone.trim(),
          'email': email.trim().toLowerCase(),
          'password': ?password,
        },
      );
    } on FunctionException catch (e) {
      final details = e.details;
      throw OrderException(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'تعذر حفظ حساب الموظف. حاول مرة ثانية.',
      );
    }
  }

  @override
  Future<int> deliveryCost() async =>
      (await client
              .from('order_settings')
              .select('delivery_cost')
              .eq('id', true)
              .single())['delivery_cost']
          as int;
  @override
  Future<void> setDeliveryCost(int cost) async => await client
      .from('order_settings')
      .update({'delivery_cost': cost})
      .eq('id', true);
  @override
  Future<List<Json>> performance() async =>
      List<Json>.from(await client.rpc('order_employee_performance'));
}

/// Demo mode uses the same validations, but intentionally has no remote storage.
class MemoryOrderRepository implements OrderRepository {
  MemoryOrderRepository(this.catalog, {this.demoAdmin});
  final TestAdminService? demoAdmin;
  final CatalogRepository catalog;
  final Map<String, TattooOrder> _orders = {};
  final Map<String, String> _tokens = {};
  final Map<String, Employee> _employees = {};
  int _delivery = 0;
  @override
  Future<TattooOrder> createManual(
    String token,
    Map<String, int> quantities,
  ) async {
    final existed = _tokens.containsKey(token);
    final order = await create(token, quantities);
    if (existed || order.createdBy != null) return order;
    final employee = demoAdmin?.currentEmployee;
    return _orders[order.id] = TattooOrder.fromJson({
      ...order.toJson(),
      'created_by': employee?.userId ?? 'demo-admin',
      'created_by_name': employee?.name ?? 'الإدارة',
      'employee_id': employee?.id,
    });
  }

  @override
  Future<TattooOrder> create(String token, Map<String, int> quantities) async {
    if (_tokens[token] case final String id) return _orders[id]!;
    if (quantities.isEmpty ||
        quantities.length > 100 ||
        quantities.values.any((q) => q < 1 || q > 99)) {
      throw const OrderException('اختر من 1 إلى 99 قطعة لكل وشم');
    }
    final products = await catalog.selected(quantities.keys.toList());
    if (products.length != quantities.length) {
      throw const OrderException('بعض الوشومات لم تعد متوفرة');
    }
    // Recheck after the await to coalesce concurrent retries.
    if (_tokens[token] case final String id) return _orders[id]!;
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    String code;
    do {
      code = List.generate(
        4,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    } while (_orders.values.any((o) => o.code == code));
    final order = TattooOrder(
      id: newOrderToken(),
      code: code,
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
      createdBy: demoAdmin?.signedIn == true
          ? (demoAdmin?.currentEmployee?.userId ?? 'demo-admin')
          : null,
      createdByName: demoAdmin?.signedIn == true
          ? (demoAdmin?.currentEmployee?.name ?? 'الإدارة')
          : 'الزبون',
      employeeId: demoAdmin?.currentEmployee?.id,
      deliveryCost: _delivery,
      items: products
          .map(
            (p) => OrderItem(
              productId: p.id,
              name: p.displayName,
              code: p.code,
              quantity: quantities[p.id]!,
              originalPrice: p.price,
              unitPrice: p.price,
            ),
          )
          .toList(),
    );
    _tokens[token] = order.id;
    return _orders[order.id] = order;
  }

  @override
  Future<TattooOrder> setShareSource(
    String id,
    String token,
    OrderSource source,
  ) async {
    await get(id, token: token);
    final old = _orders[id]!;
    if (![OrderSource.instagram, OrderSource.whatsapp].contains(source)) {
      throw const OrderException('اختر Instagram أو WhatsApp');
    }
    if (old.status != OrderStatus.pending) {
      throw const OrderException(
        'تم تأكيد الطلب. تغيير المصدر متاح للموظفين فقط',
      );
    }
    if (old.source == source) return old;
    return _orders[id] = TattooOrder.fromJson({
      ...old.toJson(),
      'source': source.name,
      'version': old.version + 1,
    });
  }

  @override
  Future<TattooOrder> get(String id, {String? token}) async {
    if (token != null && _tokens[token] != id) {
      throw const OrderException('الطلب غير موجود');
    }
    return _orders[id] ?? (throw const OrderException('الطلب غير موجود'));
  }

  @override
  Future<TattooOrder> save(
    TattooOrder order,
    Json changes, {
    String? token,
  }) async {
    await get(order.id, token: token);
    final addedIds = changes.containsKey('items')
        ? (changes['items'] as List)
              .map((i) => i['product_id'] as String)
              .where((id) => !order.items.any((i) => i.productId == id))
              .toSet()
              .toList()
        : <String>[];
    final available = addedIds.isEmpty
        ? <Tattoo>[]
        : await catalog.selected(addedIds);
    // Re-read after the catalog lookup so concurrent saves still conflict.
    final old = _orders[order.id]!;
    if (old.version != order.version) {
      throw const OrderException(
        'تم تعديل الطلب. أغلقه وافتحه لتحديث البيانات',
      );
    }
    final customer = token != null;
    if (changes.keys.any(
      (k) => ![
        'status',
        'items',
        'delivery_cost',
        'final_total',
        'phone',
        'governorate',
        'area',
        'landmark',
        'delivery_notes',
        'customer_name',
        'username',
        'source',
      ].contains(k),
    )) {
      throw const OrderException('حقول غير مسموحة');
    }
    if (customer &&
        changes.keys.any(
          (k) =>
              k != 'status' &&
              !(old.status == OrderStatus.shipped && k == 'items'),
        )) {
      throw const OrderException('إكمال بيانات الطلب متاح للموظفين فقط');
    }
    final next = TattooOrder.fromJson({
      ...old.toJson(),
      ...changes,
      'version': old.version + 1,
    });
    if (next.landmark.length > 300 || next.deliveryNotes.length > 1000) {
      throw const OrderException('النقطة الدالة أو ملاحظات المندوب طويلة جداً');
    }
    if (next.status != old.status && !old.status.next.contains(next.status)) {
      throw const OrderException('تغيير الحالة غير مسموح');
    }
    if (customer &&
        next.status != OrderStatus.cancelled &&
        !(old.status == OrderStatus.shipped &&
            [
              OrderStatus.delivered,
              OrderStatus.partial,
              OrderStatus.rejected,
            ].contains(next.status))) {
      throw const OrderException('تغيير الحالة غير مسموح');
    }
    if (!old.status.editable &&
        changes.keys.any((k) => !['status', 'items'].contains(k))) {
      throw const OrderException('تم قفل الطلب بعد الشحن');
    }
    if (next.items.isEmpty ||
        next.items.length > 100 ||
        next.items.map((i) => i.productId).toSet().length !=
            next.items.length ||
        (!old.status.editable && next.items.length != old.items.length)) {
      throw const OrderException('قطع الطلب غير صحيحة');
    }
    for (var n = 0; n < next.items.length; n++) {
      final i = next.items[n];
      var before = old.status.editable
          ? old.items.where((item) => item.productId == i.productId).firstOrNull
          : old.items[n];
      if (before == null) {
        final product = available.where((p) => p.id == i.productId).firstOrNull;
        if (product == null) {
          throw const OrderException('بعض الوشومات لم تعد متوفرة');
        }
        before = OrderItem(
          productId: product.id,
          name: product.displayName,
          code: product.code,
          quantity: i.quantity,
          originalPrice: product.price,
          unitPrice: product.price,
        );
      }
      if (i.productId != before.productId ||
          i.name != before.name ||
          i.code != before.code ||
          (before.originalPrice != null &&
              i.originalPrice != before.originalPrice) ||
          i.quantity < 1 ||
          i.quantity > 99 ||
          i.acceptedQuantity < 0 ||
          i.acceptedQuantity > i.quantity ||
          (i.originalPrice != null &&
              (i.originalPrice! < 0 || i.originalPrice! > 100000000)) ||
          (i.unitPrice != null &&
              (i.unitPrice! < 0 ||
                  i.originalPrice == null ||
                  i.unitPrice! > i.originalPrice!))) {
        throw const OrderException('راجع الكميات والأسعار');
      }
      if (!old.status.editable &&
          (i.quantity != before.quantity ||
              i.unitPrice != before.unitPrice ||
              i.originalPrice != before.originalPrice)) {
        throw const OrderException('تم قفل الأسعار والكميات بعد الشحن');
      }
    }
    if (next.deliveryCost < 0 ||
        next.deliveryCost > 100000000 ||
        next.total < 0 ||
        next.total > next.subtotal + next.deliveryCost) {
      throw const OrderException(
        'المبلغ النهائي يجب ألا يتجاوز المجموع بعد خصم القطع',
      );
    }
    if (![OrderStatus.pending, OrderStatus.cancelled].contains(next.status) &&
        (validatePhone(next.phone) != null ||
            next.governorate.trim().isEmpty ||
            next.area.trim().isEmpty ||
            !next.priced)) {
      throw const OrderException(
        'أكمل الهاتف والمحافظة والمنطقة وأسعار القطع قبل التأكيد',
      );
    }
    var items = next.items;
    if (next.status == OrderStatus.delivered ||
        next.status == OrderStatus.rejected) {
      items = items
          .map(
            (i) => OrderItem.fromJson({
              ...i.toJson(),
              'accepted_quantity': next.status == OrderStatus.delivered
                  ? i.quantity
                  : 0,
            }),
          )
          .toList();
    } else if (next.status == OrderStatus.partial) {
      final accepted = items.fold(0, (v, i) => v + i.acceptedQuantity);
      if (accepted <= 0 || accepted >= next.pieces) {
        throw const OrderException(
          'حدد القطع المستلمة: أكثر من صفر وأقل من كامل الطلب',
        );
      }
    } else if (items.any((i) => i.acceptedQuantity != 0)) {
      throw const OrderException('سجل الاستلام بعد الشحن فقط');
    }
    if (!old.status.editable && old.status != OrderStatus.shipped) {
      throw const OrderException('الطلب مغلق');
    }
    return _orders[old.id] = TattooOrder.fromJson({
      ...next.toJson(),
      'items': items.map((i) => i.toJson()).toList(),
    });
  }

  @override
  Future<List<TattooOrder>> list({
    String search = '',
    OrderStatus? status,
    int offset = 0,
  }) async => _orders.values
      .where(
        (o) =>
            (status == null || o.status == status) &&
            '${o.code} ${o.phone} ${o.customerName} ${o.username}'
                .toLowerCase()
                .contains(search.trim().toLowerCase()),
      )
      .toList()
      .reversed
      .skip(offset)
      .take(50)
      .toList();
  @override
  Future<List<Employee>> employees() async => _employees.values.toList();
  @override
  Future<void> saveEmployee({
    String? id,
    required String name,
    required String phone,
    required String email,
    String? password,
  }) async {
    if (name.trim().isEmpty ||
        name.trim().length > 120 ||
        validatePhone(phone) != null) {
      throw const OrderException('أدخل الاسم ورقم هاتف صحيح');
    }
    final key = id ?? newOrderToken();
    final existing = _employees[key];
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const OrderException('أدخل بريداً إلكترونياً صحيحاً');
    }
    if (existing != null && existing.email != normalizedEmail) {
      throw const OrderException(
        'لا يمكن تغيير بريد حساب الدخول من هذه الشاشة',
      );
    }
    if (existing == null &&
        ((password?.length ?? 0) < 8 || password!.length > 128)) {
      throw const OrderException('أدخل كلمة مرور من 8 أحرف على الأقل');
    }
    if (_employees.values.any(
          (e) => e.id != key && e.email == normalizedEmail,
        ) ||
        normalizedEmail == 'test@gmail.com') {
      throw const OrderException('البريد الإلكتروني مستخدم بالفعل');
    }
    final employee = Employee(
      id: key,
      name: name.trim(),
      phone: phone.trim(),
      email: existing?.email ?? normalizedEmail,
      userId: existing?.userId ?? newOrderToken(),
    );
    demoAdmin?.registerEmployee(employee, existing == null ? password : null);
    _employees[key] = employee;
  }

  @override
  Future<int> deliveryCost() async => _delivery;
  @override
  Future<void> setDeliveryCost(int cost) async {
    if (cost < 0 || cost > 100000000) {
      throw const OrderException('كلفة التوصيل غير صحيحة');
    }
    _delivery = cost;
  }

  @override
  Future<List<Json>> performance() async => [
    for (final id in [null, ..._employees.keys])
      {
        'name': id == null ? 'بدون موظف' : _employees[id]!.name,
        'orders': _orders.values.where((o) => o.employeeId == id).length,
        'fulfilled': _orders.values
            .where(
              (o) =>
                  o.employeeId == id &&
                  [
                    OrderStatus.delivered,
                    OrderStatus.partial,
                  ].contains(o.status),
            )
            .length,
        'accepted_pieces': _orders.values
            .where((o) => o.employeeId == id)
            .fold<int>(
              0,
              (n, o) =>
                  n + o.items.fold<int>(0, (n, i) => n + i.acceptedQuantity),
            ),
        'revenue': _orders.values
            .where((o) => o.employeeId == id)
            .fold<int>(0, (n, o) => n + o.acceptedTotal),
      },
  ];
}
