import '../config.dart';
import 'catalog.dart';

enum OrderStatus {
  pending('بانتظار التأكيد'),
  confirmed('مؤكد'),
  packed('تم التغليف'),
  shipped('تم الشحن'),
  delivered('تم الاستلام'),
  partial('استلام جزئي'),
  rejected('مرفوض'),
  cancelled('ملغي');

  const OrderStatus(this.label);

  final String label;
  bool get editable => [pending, confirmed, packed].contains(this);
  List<OrderStatus> get next => switch (this) {
    pending => [confirmed, cancelled],
    confirmed => [packed, cancelled],
    packed => [shipped, cancelled],
    shipped => [delivered, partial, rejected],
    _ => [],
  };
}

enum OrderSource {
  instagram('Instagram'),
  whatsapp('WhatsApp'),
  tiktok('TikTok'),
  facebook('Facebook'),
  website('الموقع'),
  other('أخرى');

  const OrderSource(this.label);
  final String label;
}

class Employee {
  const Employee({required this.id, required this.name, required this.phone});
  final String id, name, phone;
  factory Employee.fromJson(Json j) =>
      Employee(id: j['id'], name: j['name'], phone: j['phone']);
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    this.code = '',
    required this.quantity,
    required this.originalPrice,
    required this.unitPrice,
    this.acceptedQuantity = 0,
  });
  final String productId, name, code;
  final int quantity, acceptedQuantity;
  final int? originalPrice, unitPrice;
  factory OrderItem.fromJson(Json j) => OrderItem(
    productId: j['product_id'],
    name: j['name'],
    code: j['code'] ?? '',
    quantity: j['quantity'],
    originalPrice: j['original_price'],
    unitPrice: j['unit_price'],
    acceptedQuantity: j['accepted_quantity'] ?? 0,
  );
  Json toJson() => {
    'product_id': productId,
    'name': name,
    'code': code,
    'quantity': quantity,
    'original_price': originalPrice,
    'unit_price': unitPrice,
    'accepted_quantity': acceptedQuantity,
  };
}

class TattooOrder {
  const TattooOrder({
    required this.id,
    required this.code,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.deliveryCost,
    this.version = 1,
    this.finalTotal,
    this.phone = '',
    this.governorate = '',
    this.area = '',
    this.customerName = '',
    this.username = '',
    this.source = OrderSource.instagram,
    this.employeeId,
  });
  final String id, code, phone, governorate, area, customerName, username;
  final OrderStatus status;
  final OrderSource source;
  final DateTime createdAt;
  final List<OrderItem> items;
  final int deliveryCost, version;
  final int? finalTotal;
  final String? employeeId;
  bool get priced =>
      items.every((i) => i.originalPrice != null && i.unitPrice != null);
  int get pieces => items.fold(0, (v, i) => v + i.quantity);
  int get originalSubtotal =>
      items.fold(0, (v, i) => v + (i.originalPrice ?? 0) * i.quantity);
  int get subtotal =>
      items.fold(0, (v, i) => v + (i.unitPrice ?? 0) * i.quantity);
  int get originalTotal => originalSubtotal + deliveryCost;
  int get total => finalTotal ?? subtotal + deliveryCost;
  int get itemDiscount => originalSubtotal - subtotal;
  int get extraDiscount => subtotal + deliveryCost - total;
  int get discount => originalTotal - total;
  // Allocate the order-level discount proportionally to merchandise; shipping
  // is charged once if any pieces are accepted. Integer rounding is explicit.
  int get acceptedTotal {
    final accepted = items.fold(
      0,
      (v, i) => v + (i.unitPrice ?? 0) * i.acceptedQuantity,
    );
    if (items.every((i) => i.acceptedQuantity == 0)) return 0;
    final shipping = total < deliveryCost ? total : deliveryCost;
    return shipping +
        (subtotal == 0
            ? 0
            : ((total - shipping) * accepted / subtotal).round());
  }

  factory TattooOrder.fromJson(Json j) => TattooOrder(
    id: j['id'],
    code: j['code'],
    status: OrderStatus.values.byName(j['status']),
    createdAt: DateTime.parse(j['created_at']),
    version: j['version'] ?? 1,
    items: (j['items'] as List)
        .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i)))
        .toList(),
    deliveryCost: j['delivery_cost'],
    finalTotal: j['final_total'],
    phone: j['phone'] ?? '',
    governorate: j['governorate'] ?? '',
    area: j['area'] ?? '',
    customerName: j['customer_name'] ?? '',
    username: j['username'] ?? '',
    source: OrderSource.values.byName(j['source'] ?? 'instagram'),
    employeeId: j['employee_id'],
  );
  Json toJson() => {
    'id': id,
    'code': code,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'version': version,
    'items': items.map((i) => i.toJson()).toList(),
    'delivery_cost': deliveryCost,
    'final_total': finalTotal,
    'phone': phone,
    'governorate': governorate,
    'area': area,
    'customer_name': customerName,
    'username': username,
    'source': source.name,
    'employee_id': employeeId,
  };

  String get bookingMessage => [
    '🌿 تم تأكيد طلبك من G2G',
    'رقم الطلب: $code',
    if (customerName.isNotEmpty) 'أهلاً $customerName',
    'الهاتف: $phone',
    'العنوان: $governorate — $area',
    '',
    ...items.map(
      (i) =>
          '${i.name} × ${i.quantity}\n'
          'سعر القطعة: ${AppConfig.money(i.originalPrice ?? 0)}'
          '${i.originalPrice != i.unitPrice ? ' ← ${AppConfig.money(i.unitPrice ?? 0)}' : ''}'
          ' | المجموع: ${AppConfig.money((i.unitPrice ?? 0) * i.quantity)}',
    ),
    '',
    'قيمة الوشومات الأصلية: ${AppConfig.money(originalSubtotal)}',
    'التوصيل: ${AppConfig.money(deliveryCost)}',
    'المجموع قبل الخصم: ${AppConfig.money(originalTotal)}',
    if (itemDiscount != 0) 'خصم القطع: ${AppConfig.money(itemDiscount)}',
    if (extraDiscount != 0) 'خصم إضافي: ${AppConfig.money(extraDiscount)}',
    if (discount != 0) 'إجمالي الخصم: ${AppConfig.money(discount)}',
    'المبلغ النهائي: ${AppConfig.money(total)}',
    '',
    'شكراً لاختيارك G2G 💚',
  ].join('\n');
}

class OrderException implements Exception {
  const OrderException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? validatePhone(String value) =>
    RegExp(r'^\+?[0-9][0-9 ()-]{6,24}$').hasMatch(value.trim())
    ? null
    : 'أدخل رقم هاتف صحيح بالأرقام الإنجليزية';
