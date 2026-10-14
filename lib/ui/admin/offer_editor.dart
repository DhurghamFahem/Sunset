import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/catalog.dart';
import '../../models/offer.dart';
import '../../repositories/order_repository.dart';
import '../../services/admin_service.dart';
import '../widgets/common.dart';

class OfferEditor extends StatefulWidget {
  const OfferEditor({super.key, this.offer});
  final TattooOffer? offer;
  @override
  State<OfferEditor> createState() => _OfferEditorState();
}

class _OfferEditorState extends State<OfferEditor> {
  final form = GlobalKey<FormState>();
  late final id = widget.offer?.id ?? newOrderToken();
  late final name = TextEditingController(text: widget.offer?.name);
  late final price = TextEditingController(
    text: widget.offer?.price.toString(),
  );
  final search = TextEditingController();
  late final selected = <String, Tattoo>{
    for (final p in widget.offer?.products ?? <Tattoo>[]) p.id: p,
  };
  late bool active = widget.offer?.active ?? true;
  List<Tattoo> products = [];
  bool started = false, loading = false, more = false, saving = false;
  String? loadError, saveError;
  int generation = 0, offset = 0;
  Timer? debounce;

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
    name.dispose();
    price.dispose();
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
      final page = await AppScope.of(context).catalog.products(
        CatalogQuery(admin: true, search: search.text, offset: start),
      );
      if (!mounted || ticket != generation) return;
      setState(() {
        products = [...(next ? products : <Tattoo>[]), ...page];
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

  void toggle(Tattoo product, bool value) {
    if (value && selected.length >= 100) {
      showNotice(context, 'يمكن إضافة 100 وشم مختلف كحد أقصى');
      return;
    }
    setState(() {
      if (value) {
        selected[product.id] = product;
      } else {
        selected.remove(product.id);
      }
      saveError = null;
    });
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    if (selected.isEmpty) {
      setState(() => saveError = 'اختار وشماً واحداً على الأقل للعرض.');
      return;
    }
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await AppScope.of(context).offers.save(
        id: id,
        name: name.text,
        price: int.parse(price.text),
        productIds: selected.keys.toList(),
        active: active,
      );
      if (!mounted) return;
      setState(() => saving = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = e is CatalogInputException
              ? e.message
              : 'تعذر حفظ العرض. أعد المحاولة.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.offer == null ? 'إضافة عرض' : 'تعديل العرض'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: AbsorbPointer(
            absorbing: saving,
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'اجمع وشماً واحداً أو أكثر من تصاميمك بسعر واحد للعرض.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'اسم العرض'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'أدخل اسم العرض' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: price,
                    decoration: const InputDecoration(
                      labelText: 'سعر العرض الكامل (د.ع)',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      final number = int.tryParse(v ?? '');
                      return number == null || number < 0 || number > 2147483647
                          ? 'أدخل سعراً صحيحاً'
                          : null;
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إظهار العرض للزبائن'),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
                  const Text(
                    'يظهر العرض فقط عندما تكون كل وشوماته متاحة في الكتالوج. السعر لقطعة واحدة من كل تصميم، بدون التوصيل.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'وشومات العرض (${selected.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (selected.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('اختار الوشومات من القائمة أدناه.'),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in selected.values)
                        InputChip(
                          key: ValueKey('selected-${p.id}'),
                          label: Text('${p.displayName} • ${p.code}'),
                          onDeleted: () => toggle(p, false),
                        ),
                    ],
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
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('save-offer'),
                    onPressed: saving ? null : save,
                    icon: const Icon(Icons.check),
                    label: Text(saving ? 'جاري الحفظ…' : 'حفظ العرض'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      labelText: 'ابحث عن وشم أو رقم التصميم',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      debounce?.cancel();
                      // Invalidate in-flight reads immediately, before the debounce.
                      generation++;
                      setState(() {
                        products = [];
                        more = false;
                        loading = true;
                      });
                      debounce = Timer(const Duration(milliseconds: 300), load);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (loading) const LinearProgressIndicator(),
                  if (loadError != null) ...[
                    Text(loadError!),
                    TextButton(
                      onPressed: load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                  if (!loading && loadError == null && products.isEmpty)
                    const Text('ماكو وشومات مطابقة للبحث.'),
                  for (final p in products)
                    CheckboxListTile(
                      key: ValueKey('offer-product-${p.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: selected.containsKey(p.id),
                      onChanged: (v) => toggle(p, v ?? false),
                      secondary: SizedBox(
                        width: 52,
                        height: 52,
                        child: CatalogImage(p.thumbnail, padding: 2),
                      ),
                      title: Text(p.displayName),
                      subtitle: Text(
                        [
                          p.code,
                          p.formattedPrice,
                          if (!p.active) 'مخفي',
                        ].where((s) => s.isNotEmpty).join(' • '),
                      ),
                    ),
                  if (more)
                    OutlinedButton(
                      onPressed: loading ? null : () => load(next: true),
                      child: const Text('عرض المزيد'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
