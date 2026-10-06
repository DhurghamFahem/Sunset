import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/catalog.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';
import '../widgets/common.dart';

class ManualOrderScreen extends StatefulWidget {
  const ManualOrderScreen({super.key});

  @override
  State<ManualOrderScreen> createState() => _ManualOrderScreenState();
}

class _ManualOrderScreenState extends State<ManualOrderScreen> {
  final search = TextEditingController();
  final form = GlobalKey<FormState>();
  final selected = <String, Tattoo>{};
  final quantities = <String, int>{};
  List<Tattoo> products = [];
  Timer? debounce;
  int generation = 0, offset = 0;
  bool started = false, loading = false, more = false, saving = false;
  String? loadError, saveError, requestToken;

  bool get locked => saving || requestToken != null;

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
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    final ticket = ++generation;
    final start = next ? offset : 0;
    setState(() {
      loading = true;
      loadError = null;
      if (!next) {
        products = [];
        more = false;
      }
    });
    try {
      final catalog = AppScope.of(context).catalog;
      final page = await catalog.products(
        CatalogQuery(admin: true, search: search.text, offset: start),
      );
      // Admin search includes codes. Only offer products that can be ordered;
      // hidden products/categories are excluded by the public selection read.
      final available = page.isEmpty
          ? <Tattoo>[]
          : await catalog.selected(page.map((p) => p.id).toList());
      final ids = available.map((p) => p.id).toSet();
      if (!mounted || ticket != generation) return;
      setState(() {
        final visible = page.where((p) => ids.contains(p.id));
        products = [...(next ? products : <Tattoo>[]), ...visible];
        offset = start + page.length;
        more = page.length == AppConfig.pageSize;
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => loadError = 'تعذر تحميل الوشومات. أعد المحاولة.');
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  void add(Tattoo product) {
    if (locked || selected.containsKey(product.id)) return;
    if (selected.length == 100) {
      showNotice(context, 'يمكن إضافة 100 وشم مختلف كحد أقصى');
      return;
    }
    setState(() {
      selected[product.id] = product;
      quantities[product.id] = 1;
      saveError = null;
    });
  }

  Future<void> create() async {
    if (saving || selected.isEmpty || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      saveError = null;
      requestToken ??= newOrderToken();
    });
    try {
      final order = await AppScope.of(context).orders
          .createManual(requestToken!, Map.of(quantities));
      if (!mounted) return;
      // The manual request never enters the customer's selections or receipts.
      setState(() => saving = false);
      Navigator.pop(context, order);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        if (e is OrderException) {
          requestToken = null;
          saveError = e.message;
        } else {
          // A response may have been lost after the server committed. Keep
          // the same token and selection so retry cannot create a duplicate.
          saveError =
              'تعذر التحقق من حفظ الطلب. أعد المحاولة لاسترجاع نفس الطلب.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('إضافة طلب يدوي')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'اختر الوشومات والكميات للعميل، ثم أكمل معلوماته والتوصيل لتأكيد الطلب.',
                ),
                const SizedBox(height: 16),
                Text(
                  'الاختيارات (${selected.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (selected.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('أضف وشماً واحداً على الأقل من القائمة أدناه.'),
                  ),
                for (final product in selected.values)
                  Card(
                    key: ValueKey('selected-${product.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${product.displayName} • ${product.code}',
                                ),
                              ),
                              IconButton(
                                tooltip: 'إزالة ${product.displayName}',
                                onPressed: locked
                                    ? null
                                    : () => setState(() {
                                        selected.remove(product.id);
                                        quantities.remove(product.id);
                                      }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          TextFormField(
                            key: ValueKey('quantity-${product.id}'),
                            initialValue: '${quantities[product.id]}',
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            enabled: !locked,
                            decoration: const InputDecoration(
                              labelText: 'الكمية (1–99)',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            onChanged: (value) => quantities[product.id] =
                                int.tryParse(value) ?? 0,
                            validator: (value) {
                              final quantity = int.tryParse(value ?? '');
                              return quantity == null ||
                                      quantity < 1 ||
                                      quantity > 99
                                  ? 'أدخل كمية من 1 إلى 99'
                                  : null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (saveError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      saveError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: saving || selected.isEmpty ? null : create,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    saving
                        ? 'جاري إنشاء الطلب…'
                        : requestToken != null
                        ? 'إعادة المحاولة'
                        : 'إنشاء الطلب وإكمال البيانات',
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: search,
                  enabled: !locked,
                  decoration: const InputDecoration(
                    labelText: 'بحث باسم الوشم أو رمزه',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) {
                    // Invalidate in-flight results before the debounce fires.
                    generation++;
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 300), load);
                  },
                ),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                if (loadError != null)
                  ListTile(
                    title: Text(loadError!),
                    trailing: IconButton(
                      tooltip: 'إعادة تحميل الوشومات',
                      onPressed: () => load(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                if (!loading && loadError == null && products.isEmpty)
                  const Text('لا توجد وشومات متاحة مطابقة.'),
                for (final product in products)
                  Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: CatalogImage(product.thumbnail, padding: 4),
                      ),
                      title: Text(product.displayName),
                      subtitle: Text(
                        '${product.code} • ${product.price == null ? 'بانتظار التسعير' : product.formattedPrice}',
                      ),
                      trailing: IconButton(
                        tooltip: 'إضافة ${product.displayName}',
                        onPressed: locked || selected.containsKey(product.id)
                            ? null
                            : () => add(product),
                        icon: Icon(
                          selected.containsKey(product.id)
                              ? Icons.check
                              : Icons.add,
                        ),
                      ),
                    ),
                  ),
                if (more)
                  OutlinedButton(
                    onPressed: loading || locked
                        ? null
                        : () => load(next: true),
                    child: const Text('عرض المزيد'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
