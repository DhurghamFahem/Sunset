import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/catalog.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';
import '../order_screen.dart';
import '../widgets/common.dart';
import 'manual_order_screen.dart';
import 'main_prime_settings.dart';

class OrderManagement extends StatefulWidget {
  const OrderManagement({super.key, required this.section});
  final String section;
  @override
  State<OrderManagement> createState() => _OrderManagementState();
}

class _OrderManagementState extends State<OrderManagement> {
  final search = TextEditingController(), delivery = TextEditingController();
  List<TattooOrder> orders = [];
  List<Employee> employees = [];
  List<Json> performance = [];
  OrderStatus? status;
  bool busy = true, started = false, more = false;
  String? error;
  Timer? debounce;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    delivery.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    final ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = AppScope.of(context).orders;
      if (widget.section == 'orders') {
        final rows = await repo.list(
          search: search.text,
          status: status,
          offset: next ? orders.length : 0,
        );
        if (!mounted || ticket != generation) return;
        setState(() {
          orders = next ? [...orders, ...rows] : rows;
          more = rows.length == 50;
        });
      } else if (widget.section == 'team') {
        final rows = await repo.employees();
        final stats = await repo.performance();
        if (!mounted || ticket != generation) return;
        setState(() {
          employees = rows;
          performance = stats;
        });
      } else {
        final cost = await repo.deliveryCost();
        if (!mounted || ticket != generation) return;
        delivery.text = '$cost';
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(
          () => error = 'تعذر تحميل البيانات. تأكد من تطبيق تحديث قاعدة البيانات وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<void> editEmployee([Employee? employee]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EmployeeEditor(employee: employee),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> createManualOrder() async {
    final order = await Navigator.push<TattooOrder>(
      context,
      MaterialPageRoute<TattooOrder>(builder: (_) => const ManualOrderScreen()),
    );
    if (!mounted) return;
    if (order != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => OrderScreen(order: order)),
      );
    }
    if (mounted) await load();
  }

  Future<void> saveDelivery() async {
    final amount = int.tryParse(delivery.text);
    if (amount == null || amount < 0 || amount > 100000000) {
      showNotice(context, 'أدخل مبلغ توصيل صحيحاً غير سالب');
      return;
    }
    setState(() => busy = true);
    try {
      await AppScope.of(context).orders.setDeliveryCost(amount);
      if (mounted) showNotice(context, 'تم حفظ كلفة التوصيل للطلبات الجديدة');
    } catch (_) {
      if (mounted) showNotice(context, 'تعذر الحفظ. حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        ListTile(
          title: Text(error!),
          trailing: IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.section == 'orders') ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'الطلبات',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: busy ? null : load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : createManualOrder,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('إضافة طلب يدوي'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                decoration: const InputDecoration(
                  labelText: 'بحث بالرمز أو الهاتف أو اسم العميل',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 300), load);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<OrderStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'حالة الطلب'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('كل الحالات'),
                  ),
                  ...OrderStatus.values.map(
                    (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                  ),
                ],
                onChanged: (s) {
                  setState(() => status = s);
                  load();
                },
              ),
              const SizedBox(height: 12),
              if (orders.isEmpty && !busy && error == null)
                const Text(
                  'لا توجد طلبات مطابقة. أضف طلباً يدوياً أو انتظر اختيارات العملاء.',
                ),
              for (final order in orders)
                Card(
                  child: ListTile(
                    title: Text('${order.code} • ${order.status.label}'),
                    subtitle: Text(
                      '${order.customerName.isEmpty ? 'عميل جديد' : order.customerName} • ${order.pieces} قطعة\n'
                      '${order.priced ? AppConfig.money(order.total) : 'بانتظار التسعير'} • ${order.createdAt.toLocal().toString().substring(0, 16)}',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      try {
                        final fresh = await AppScope.of(context).orders
                            .get(order.id);
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => OrderScreen(order: fresh),
                          ),
                        );
                        if (mounted) await load();
                      } catch (_) {
                        if (context.mounted) {
                          showNotice(context, 'تعذر تحميل الطلب');
                        }
                      }
                    },
                  ),
                ),
              if (more)
                OutlinedButton(
                  onPressed: busy ? null : () => load(next: true),
                  child: const Text('عرض المزيد'),
                ),
            ] else if (widget.section == 'team') ...[
              Text(
                'الموظفون والأداء',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : editEmployee,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('إضافة موظف'),
              ),
              for (final employee in employees)
                Card(
                  child: ListTile(
                    title: Text(employee.name),
                    subtitle: Text(
                      '${employee.phone}\n${employee.email.isEmpty ? 'لم يُضف حساب دخول بعد' : employee.email}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => editEmployee(employee),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'أداء جميع الأوقات • حسب منشئ الطلب. قيمة المستلم تشمل التوصيل مرة واحدة وتوزّع الخصم الإضافي على القطع بالتناسب.',
              ),
              const SizedBox(height: 12),
              for (final row in performance)
                Card(
                  child: ListTile(
                    title: Text(row['name'] as String),
                    subtitle: Text(
                      '${row['orders']} طلب • ${row['fulfilled']} طلب مستلم كلياً أو جزئياً\n'
                      '${row['accepted_pieces']} قطعة مستلمة • ${AppConfig.money((row['revenue'] as num).toInt())}',
                    ),
                  ),
                ),
            ] else ...[
              Text(
                'إعدادات التوصيل',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'تُحفظ كلفة التوصيل مع كل طلب عند إنشائه. تغيير الإعداد لا يغيّر الطلبات السابقة؛ يمكن تعديلها قبل الشحن من تفاصيل الطلب.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: delivery,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'كلفة التوصيل الافتراضية (د.ع)',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : saveDelivery,
                child: const Text('حفظ كلفة التوصيل'),
              ),
              const SizedBox(height: 32),
              const MainPrimeSettings(),
            ],
          ],
        ),
      ),
    ],
  );
}

class EmployeeEditor extends StatefulWidget {
  const EmployeeEditor({super.key, this.employee});
  final Employee? employee;
  @override
  State<EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends State<EmployeeEditor> {
  late final name = TextEditingController(text: widget.employee?.name);
  late final phone = TextEditingController(text: widget.employee?.phone);
  late final email = TextEditingController(text: widget.employee?.email);
  final password = TextEditingController();
  late final primeUsername = TextEditingController(
    text: widget.employee?.primeUsername,
  );
  final primePassword = TextEditingController();
  late final employeeId = widget.employee?.id ?? newOrderToken();
  bool get needsLogin => widget.employee?.userId == null;
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    password.dispose();
    primeUsername.dispose();
    primePassword.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await AppScope.of(context).orders.saveEmployee(
        id: employeeId,
        name: name.text,
        phone: phone.text,
        email: email.text,
        password: needsLogin ? password.text : null,
        primeUsername: primeUsername.text,
        primePassword: primePassword.text.isEmpty ? null : primePassword.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is OrderException
              ? e.message
              : 'تعذر حفظ الموظف. حاول مرة ثانية.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.employee == null ? 'إضافة موظف' : 'تعديل الموظف'),
    content: Form(
      key: form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) => v!.trim().isEmpty ? 'أدخل الاسم' : null,
            ),
            TextFormField(
              controller: phone,
              maxLength: 26,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              validator: (v) => validatePhone(v ?? ''),
            ),
            TextFormField(
              controller: email,
              maxLength: 254,
              readOnly: !needsLogin,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني للدخول',
              ),
              validator: (v) =>
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(v?.trim() ?? '')
                  ? null
                  : 'أدخل بريداً إلكترونياً صحيحاً',
            ),
            if (needsLogin)
              TextFormField(
                controller: password,
                maxLength: 128,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  helperText: '8 أحرف على الأقل',
                ),
                validator: (v) => (v?.length ?? 0) >= 8
                    ? null
                    : 'أدخل كلمة مرور من 8 أحرف على الأقل',
              ),
            const SizedBox(height: 16),
            const Text('حساب برايم للتوصيل'),
            TextFormField(
              controller: primeUsername,
              maxLength: 254,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم في برايم',
              ),
              validator: (v) =>
                  primePassword.text.isNotEmpty && (v?.trim().isEmpty ?? true)
                  ? 'أدخل اسم المستخدم في برايم'
                  : null,
            ),
            TextFormField(
              controller: primePassword,
              maxLength: 256,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'كلمة مرور برايم',
                helperText: widget.employee?.primeConfigured == true
                    ? 'اتركها فارغة للاحتفاظ بكلمة المرور الحالية'
                    : 'مطلوبة لرفع الطلبات إلى برايم',
              ),
              validator: (v) =>
                  primeUsername.text.trim().isNotEmpty &&
                      (widget.employee?.primeConfigured != true ||
                          primeUsername.text.trim() !=
                              widget.employee?.primeUsername) &&
                      (v?.isEmpty ?? true)
                  ? 'أدخل كلمة مرور برايم'
                  : null,
            ),
            const Text('يُختار أول متجر وأول منتج من برايم تلقائياً.'),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('صلاحيات الموظف: الطلبات والتجهيز وصور الزبون فقط.'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('رجوع'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'جاري الحفظ…' : 'حفظ'),
      ),
    ],
  );
}
