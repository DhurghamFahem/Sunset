import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/catalog.dart';
import '../models/order.dart';
import 'widgets/common.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.order, this.token});
  final TattooOrder order;
  final String? token;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late TattooOrder order = widget.order;
  final form = GlobalKey<FormState>();
  late final phone = TextEditingController(text: order.phone);
  late final governorate = TextEditingController(text: order.governorate);
  late final area = TextEditingController(text: order.area);
  late final name = TextEditingController(text: order.customerName);
  late final username = TextEditingController(text: order.username);
  late final delivery = TextEditingController(text: '${order.deliveryCost}');
  late final finalPrice = TextEditingController(
    text: order.finalTotal?.toString() ?? '',
  );
  late final quantities = order.items
      .map((i) => TextEditingController(text: '${i.quantity}'))
      .toList();
  late final originals = order.items
      .map(
        (i) => TextEditingController(text: i.originalPrice?.toString() ?? ''),
      )
      .toList();
  late final prices = order.items
      .map((i) => TextEditingController(text: i.unitPrice?.toString() ?? ''))
      .toList();
  late final accepted = order.items
      .map((i) => TextEditingController(text: '${i.acceptedQuantity}'))
      .toList();
  late OrderSource source = order.source;
  late String? employeeId = order.employeeId;
  List<Employee> employees = [];
  bool busy = false, loaded = false;
  String? error;
  bool get staff => widget.token == null;
  bool get editable => staff && order.status.editable;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      if (staff) loadEmployees();
    }
  }

  Future<void> loadEmployees() async {
    try {
      final rows = await AppScope.of(context).orders.employees();
      if (mounted) setState(() => employees = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'تعذر تحميل الموظفين. أغلق الطلب وأعد المحاولة.',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      phone,
      governorate,
      area,
      name,
      username,
      delivery,
      finalPrice,
      ...quantities,
      ...originals,
      ...prices,
      ...accepted,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<OrderItem> draftItems() => [
    for (var n = 0; n < order.items.length; n++)
      OrderItem.fromJson({
        ...order.items[n].toJson(),
        'quantity': int.tryParse(quantities[n].text) ?? 0,
        'original_price': int.tryParse(originals[n].text),
        'unit_price': int.tryParse(prices[n].text),
        'accepted_quantity': int.tryParse(accepted[n].text) ?? -1,
      }),
  ];
  TattooOrder get draft => TattooOrder.fromJson({
    ...order.toJson(),
    'items': draftItems().map((i) => i.toJson()).toList(),
    'delivery_cost': int.tryParse(delivery.text) ?? 0,
    'final_total': int.tryParse(finalPrice.text),
  });

  Future<void> copyMessage() async {
    try {
      await Clipboard.setData(ClipboardData(text: order.bookingMessage))
          .timeout(const Duration(seconds: 3));
      if (mounted) showNotice(context, 'تم نسخ تفاصيل الطلب — جاهزة للإرسال');
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'المتصفح لم يسمح بالنسخ التلقائي. استخدم زر النسخ أو حدد الرسالة.',
        );
      }
    }
  }

  Future<void> save(OrderStatus target) async {
    if (busy) return;
    if (target != OrderStatus.cancelled && !form.currentState!.validate()) {
      return;
    }
    if (target == OrderStatus.cancelled &&
        !await confirm(
          context,
          'إلغاء الطلب ${order.code}؟',
          'سيتم إغلاق هذا الطلب.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final Json changes = {'status': target.name};
      if (target != OrderStatus.cancelled) {
        if (staff && order.status.editable) {
          changes.addAll({
            'phone': phone.text.trim(),
            'governorate': governorate.text.trim(),
            'area': area.text.trim(),
            'customer_name': name.text.trim(),
            'username': username.text.trim(),
            'source': source.name,
          });
          if (staff) {
            changes.addAll({
              'items': draftItems().map((i) => i.toJson()).toList(),
              'delivery_cost': int.parse(delivery.text),
              'final_total': int.tryParse(finalPrice.text),
              'employee_id': employeeId,
            });
          }
        } else if (order.status == OrderStatus.shipped) {
          changes['items'] = draftItems().map((i) => i.toJson()).toList();
        }
      }
      final previous = order.status;
      final saved = await AppScope.of(context).orders
          .save(order, changes, token: widget.token);
      if (!mounted) return;
      setState(() {
        order = saved;
        for (var n = 0; n < saved.items.length; n++) {
          accepted[n].text = '${saved.items[n].acceptedQuantity}';
        }
      });
      if (previous == OrderStatus.pending &&
          saved.status == OrderStatus.confirmed) {
        await copyMessage();
      } else if (mounted) {
        showNotice(context, 'تم حفظ الطلب');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is OrderException
              ? e.message
              : 'تعذر حفظ الطلب. حاول مرة ثانية.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool numeric = false,
    int maxLength = 120,
    bool? enabled,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !busy && (enabled ?? editable),
      maxLength: maxLength,
      keyboardType: controller == phone
          ? TextInputType.phone
          : numeric
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'هذا الحقل مطلوب';
        }
        if (controller == phone && v!.isNotEmpty) return validatePhone(v);
        if (numeric &&
            v!.isNotEmpty &&
            (int.tryParse(v) == null ||
                int.parse(v) < 0 ||
                int.parse(v) > 100000000)) {
          return 'أدخل مبلغاً صحيحاً غير سالب';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final totals = draft;
    return Scaffold(
      appBar: AppBar(title: Text('الطلب ${order.code}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(order.status.label)),
                    Chip(
                      label: Text(
                        order.createdAt.toLocal().toString().substring(0, 16),
                      ),
                    ),
                  ],
                ),
                if (order.status == OrderStatus.pending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      staff
                          ? 'أكمل معلومات العميل والتوصيل لتأكيد الطلب.'
                          : 'طلبك محفوظ بانتظار تأكيد الموظف.',
                    ),
                  ),
                Text('الوشومات', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                for (var n = 0; n < order.items.length; n++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            order.items[n].name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (staff && order.status.editable) ...[
                            field(
                              'الكمية (1–99)',
                              quantities[n],
                              required: true,
                              numeric: true,
                              maxLength: 2,
                            ),
                            field(
                              'السعر الأصلي للقطعة',
                              originals[n],
                              numeric: true,
                              enabled: order.items[n].originalPrice == null,
                            ),
                            field(
                              'سعر القطعة بعد الخصم',
                              prices[n],
                              numeric: true,
                            ),
                          ] else
                            Text(
                              'الكمية: ${order.items[n].quantity} • ${order.items[n].unitPrice == null ? 'بانتظار التسعير' : AppConfig.money(order.items[n].unitPrice!)} / قطعة',
                            ),
                          if (order.status == OrderStatus.shipped)
                            field(
                              'الكمية المستلمة (للاستلام الجزئي)',
                              accepted[n],
                              required: true,
                              numeric: true,
                              maxLength: 2,
                              enabled: true,
                            ),
                          if ([
                            OrderStatus.delivered,
                            OrderStatus.partial,
                            OrderStatus.rejected,
                          ].contains(order.status))
                            Text(
                              'المستلم: ${order.items[n].acceptedQuantity} من ${order.items[n].quantity}',
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (staff) ...[
                  Text(
                    'معلومات العميل والتوصيل',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  field('رقم الهاتف *', phone, maxLength: 26),
                  field('المحافظة *', governorate),
                  field('المنطقة والعنوان التفصيلي *', area, maxLength: 300),
                  field('اسم العميل (اختياري)', name),
                  field('اسم المستخدم (اختياري)', username),
                  DropdownButtonFormField<OrderSource>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'مصدر الطلب'),
                    items: OrderSource.values
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.label)),
                        )
                        .toList(),
                    onChanged: editable && !busy
                        ? (s) => setState(() => source = s!)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('${employees.length}-$employeeId'),
                    initialValue: employees.any((e) => e.id == employeeId)
                        ? employeeId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'الموظف المسؤول',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('بدون موظف'),
                      ),
                      ...employees.map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      ),
                    ],
                    onChanged: editable && !busy
                        ? (v) => setState(() => employeeId = v == '' ? null : v)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  field(
                    'كلفة التوصيل',
                    delivery,
                    required: true,
                    numeric: true,
                  ),
                  field(
                    'المبلغ النهائي (اتركه فارغاً للحساب التلقائي)',
                    finalPrice,
                    numeric: true,
                  ),
                  const Text(
                    'الخصم النهائي يُضاف إلى خصم القطع. لا يمكن زيادة السعر فوق المجموع بعد خصم القطع.',
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!totals.priced)
                          const Text(
                            'توجد قطع بدون سعر. ستحدد الإدارة أسعارها قبل التأكيد.',
                          ),
                        Text(
                          'قيمة القطع الأصلية: ${AppConfig.money(totals.originalSubtotal)}',
                        ),
                        Text(
                          'التوصيل: ${AppConfig.money(totals.deliveryCost)}',
                        ),
                        Text(
                          'المجموع قبل الخصم: ${AppConfig.money(totals.originalTotal)}',
                        ),
                        Text(
                          'خصم القطع: ${AppConfig.money(totals.itemDiscount)}',
                        ),
                        Text(
                          'خصم إضافي: ${AppConfig.money(totals.extraDiscount)}',
                        ),
                        Text(
                          'إجمالي الخصم: ${AppConfig.money(totals.discount)}',
                        ),
                        Text(
                          'المبلغ النهائي: ${AppConfig.money(totals.total)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (order.status == OrderStatus.partial)
                          Text(
                            'قيمة المستلم مع التوصيل: ${AppConfig.money(order.acceptedTotal)}',
                          ),
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                if (staff && order.status.editable)
                  OutlinedButton(
                    onPressed: busy ? null : () => save(order.status),
                    child: const Text('حفظ التعديلات'),
                  ),
                ...order.status.next
                    .where(
                      (s) =>
                          staff ||
                          order.status == OrderStatus.shipped ||
                          s == OrderStatus.cancelled,
                    )
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: s == OrderStatus.cancelled
                            ? TextButton(
                                onPressed: busy ? null : () => save(s),
                                child: const Text('إلغاء الطلب'),
                              )
                            : FilledButton(
                                onPressed: busy ? null : () => save(s),
                                child: Text(
                                  s == OrderStatus.confirmed
                                      ? 'تأكيد الطلب ونسخ الرسالة'
                                      : s.label,
                                ),
                              ),
                      ),
                    ),
                if (order.priced &&
                    ![
                      OrderStatus.pending,
                      OrderStatus.cancelled,
                    ].contains(order.status)) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: copyMessage,
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ تفاصيل الحجز'),
                  ),
                  ExpansionTile(
                    title: const Text('رسالة الطلب الجاهزة للإرسال'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(order.bookingMessage),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
