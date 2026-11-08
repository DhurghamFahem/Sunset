import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/catalog.dart';
import '../../models/order.dart';
import '../widgets/common.dart';

class PreparationScreen extends StatefulWidget {
  const PreparationScreen({super.key});

  @override
  State<PreparationScreen> createState() => _PreparationScreenState();
}

class _PreparationScreenState extends State<PreparationScreen> {
  final caseId = TextEditingController();
  TattooOrder? order;
  Map<String, Tattoo> products = {};
  bool busy = false;
  String? error, notice;

  @override
  void dispose() {
    caseId.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PrimeQrScanner()),
    );
    if (!mounted || value == null) return;
    caseId.text = value;
    await lookup();
  }

  Future<void> lookup() async {
    if (busy) return;
    final value = caseId.text.trim();
    final services = AppScope.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      order = null;
      products = {};
      error = null;
      notice = null;
    });
    try {
      final found = await services.orders.getByPrimeCaseId(value);
      if (!mounted) return;
      setState(() => order = found);
      // Catalog availability must never hide the saved order contents.
      try {
        final images = await services.catalog.selected(
          found.items.map((item) => item.productId).toList(),
        );
        if (!mounted) return;
        setState(() => products = {for (final p in images) p.id: p});
      } catch (_) {
        // Saved names, codes and quantities remain sufficient for preparation.
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is OrderException
              ? e.message
              : 'تعذر تحميل الطلب. تحقق من الاتصال وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pack() async {
    final current = order;
    if (busy || current == null || current.status != OrderStatus.uploaded) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AppScope.of(context).orders.save(current, {'status': 'packed'});
      if (!mounted) return;
      setState(() {
        order = null;
        products = {};
        caseId.clear();
        notice = 'تم تغليف الطلب ${current.code}. امسح الطلب التالي.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A failed response can mean the write succeeded, or another staff
        // member edited this order. Require a fresh read before another action.
        order = null;
        products = {};
        error =
            '${e is OrderException ? e.message : 'تعذر تأكيد التغليف.'} '
            'أعد مسح الرمز أو عرض الطلب للتحقق من حالته.';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = order;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('التجهيز', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('امسح QR المطبوع من برايم لعرض قطع الطلب، ثم أكمل التغليف.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('مسح QR بالكاميرا'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('prime-case-input'),
          controller: caseId,
          readOnly: busy,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: 'رقم حالة برايم'),
          onSubmitted: (_) => lookup(),
          onChanged: (_) => setState(() {
            order = null;
            products = {};
            error = null;
            notice = null;
          }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : lookup,
          icon: const Icon(Icons.search),
          label: const Text('عرض الطلب'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(notice!),
          ),
        if (current != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الطلب ${current.code}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('برايم: ${current.primeCaseId}'),
                  Text('الحالة: ${current.status.label}'),
                  const Divider(),
                  Text(
                    current.customerName.isEmpty
                        ? 'بدون اسم عميل'
                        : current.customerName,
                  ),
                  Text(current.phone, textDirection: TextDirection.ltr),
                  Text('${current.governorate} — ${current.area}'),
                  if (current.landmark.isNotEmpty)
                    Text('النقطة الدالة: ${current.landmark}'),
                  if (current.deliveryNotes.isNotEmpty)
                    Text('ملاحظات: ${current.deliveryNotes}'),
                  const SizedBox(height: 8),
                  Text(
                    'إجمالي القطع: ${current.pieces}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    current.isPaid
                        ? 'مدفوع بالكامل'
                        : 'المبلغ المطلوب: ${AppConfig.money(current.collectAmount)}',
                  ),
                ],
              ),
            ),
          ),
          for (final item in current.items)
            Card(
              key: ValueKey('preparation-item-${item.productId}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (products[item.productId] case final product?) ...[
                      SizedBox(
                        width: 72,
                        height: 90,
                        child: CatalogImage(product.thumbnail),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('رمز الوشم: ${item.code}'),
                          const SizedBox(height: 8),
                          Text(
                            'الكمية: ${item.quantity}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (current.status == OrderStatus.uploaded)
            FilledButton.icon(
              key: const ValueKey('pack-order'),
              onPressed: busy ? null : pack,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('اكتمل التجهيز — تم التغليف'),
            )
          else
            Text(
              current.status == OrderStatus.packed
                  ? 'هذا الطلب مغلّف مسبقاً. امسح الطلب التالي.'
                  : 'لا يمكن تجهيز هذا الطلب بحالته الحالية: ${current.status.label}',
            ),
        ],
      ],
    );
  }
}

class PrimeQrScanner extends StatefulWidget {
  const PrimeQrScanner({super.key});

  @override
  State<PrimeQrScanner> createState() => _PrimeQrScannerState();
}

class _PrimeQrScannerState extends State<PrimeQrScanner> {
  bool detected = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مسح رمز برايم')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('وجّه الكاميرا إلى QR رقم حالة برايم المطبوع على الوصل.'),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              if (detected || !mounted) return;
              final values = capture.barcodes
                  .where((barcode) => barcode.format == BarcodeFormat.qrCode)
                  .map((barcode) => barcode.rawValue?.trim() ?? '')
                  .where((value) => value.isNotEmpty)
                  .toSet();
              // Require one label in frame rather than choosing between orders.
              if (values.length != 1) return;
              detected = true;
              Navigator.pop(context, values.single);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'تعذر فتح الكاميرا. اسمح باستخدام الكاميرا في إعدادات الجهاز أو المتصفح، ثم حاول مجدداً.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('الرجوع وإدخال الرقم يدوياً'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
