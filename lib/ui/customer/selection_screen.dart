import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/order.dart';
import '../../services/selection_renderer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'share_screen.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});
  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  bool busy = false;
  double progress = 0;

  Future<void> generate() async {
    if (busy) return;
    final app = AppScope.of(context);
    setState(() {
      busy = true;
      progress = 0;
    });
    try {
      final removed = await app.selection.reconcile(app.catalog);
      if (!mounted) return;
      if (removed > 0) {
        showNotice(
          context,
          'بعض الوشومات مو متوفرة حالياً. راجع اختياراتك قبل الإرسال.',
        );
        return;
      }
      if (app.selection.count == 0) return;
      final products = app.selection.items;
      final quantities = app.selection.quantities;
      final token = await app.selection.exportToken();
      final order = await app.orders.create(token, quantities);
      await app.selection.rememberOrder(order.id, token);
      final pages = await SelectionRenderer().render(
        products,
        orderCode: order.code,
        quantities: {
          for (final item in order.items) item.productId: item.quantity,
        },
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (!mounted) return;
      await app.selection.finishExport();
      if (!mounted) return;
      app.analytics.event('selection_exported');
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ShareScreen(
            pages: pages,
            initialSource: order.source == OrderSource.whatsapp
                ? OrderSource.whatsapp
                : OrderSource.instagram,
            onSourceChanged: (source) async {
              await app.orders.setShareSource(order.id, token, source);
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'ما قدرنا نجهز الصور. اختياراتك محفوظة، حاول مرة ثانية.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = AppScope.of(context).selection;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        if (selection.count == 0) {
          return MessagePanel(
            title: 'اختار أول وشم يعجبك 🌿',
            detail: 'اضغط «اختيار» تحت أي تصميم.',
            action: FilledButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
              child: const Text('تصفح الوشومات'),
            ),
          );
        }
        final products = selection.items;
        final priced = products
            .where((product) => product.price != null)
            .toList();
        final total = priced.fold<int>(
          0,
          (sum, product) =>
              sum + product.price! * selection.quantity(product.id),
        );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 24),
                        child: JourneySteps(current: 1),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'اختياراتك',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => context.canPop()
                                      ? context.pop()
                                      : context.go('/'),
                            child: const Text('كمل التصفح'),
                          ),
                          PopupMenuButton<String>(
                            enabled: !busy,
                            tooltip: 'خيارات القائمة',
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'clear',
                                child: Text('مسح الاختيارات'),
                              ),
                            ],
                            onSelected: (_) async {
                              if (await confirm(
                                context,
                                'مسح الاختيارات؟',
                                'تحب تبدأ اختيار جديد؟',
                              )) {
                                selection.clear();
                              }
                            },
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: Text(
                          'راجع اللي عجبك، وبعدين نجهز صورها للإرسال.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ),
                      ...products.map(
                        (p) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: paper,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: busy
                                    ? null
                                    : () => context.push('/tattoo/${p.id}'),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 88,
                                    height: 100,
                                    child: CatalogImage(
                                      p.thumbnail,
                                      label: p.displayName,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (p.dimensions.isNotEmpty)
                                      Text(
                                        p.dimensions,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (p.price != null)
                                      Text(
                                        p.formattedPrice,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'تقليل الكمية',
                                          visualDensity: VisualDensity.compact,
                                          onPressed:
                                              busy ||
                                                  selection.quantity(p.id) <= 1
                                              ? null
                                              : () => selection.setQuantity(
                                                  p.id,
                                                  selection.quantity(p.id) - 1,
                                                ),
                                          icon: const Icon(
                                            Icons.remove,
                                            size: 18,
                                          ),
                                        ),
                                        Text('${selection.quantity(p.id)}'),
                                        IconButton(
                                          tooltip: 'زيادة الكمية',
                                          visualDensity: VisualDensity.compact,
                                          onPressed:
                                              busy ||
                                                  selection.quantity(p.id) >= 99
                                              ? null
                                              : () => selection.setQuantity(
                                                  p.id,
                                                  selection.quantity(p.id) + 1,
                                                ),
                                          icon: const Icon(Icons.add, size: 18),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'إزالة ${p.displayName}',
                                onPressed: busy
                                    ? null
                                    : () {
                                        final removedQuantity = selection
                                            .quantity(p.id);
                                        selection.toggle(p);
                                        ScaffoldMessenger.of(context)
                                            .hideCurrentSnackBar();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'تمت إزالة ${p.displayName}',
                                            ),
                                            action: SnackBarAction(
                                              label: 'تراجع',
                                              onPressed: () {
                                                if (!selection.contains(p.id)) {
                                                  selection.toggle(p);
                                                  selection.setQuantity(
                                                    p.id,
                                                    removedQuantity,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.fromBorderSide(BorderSide(color: line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${selection.pieces} قطعة',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (priced.isNotEmpty)
                                Text(
                                  '${priced.length == products.length ? 'المجموع' : 'المسعّر'}: ${AppConfig.money(total)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (busy) ...[
                            LinearProgressIndicator(
                              value: progress > 0 ? progress : null,
                            ),
                            const SizedBox(height: 10),
                          ],
                          FilledButton.icon(
                            key: const ValueKey('prepare-selections'),
                            onPressed: busy ? null : generate,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              busy ? 'جاري تجهيز الصور…' : 'جهّز صور اختياراتي',
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'الخطوة الجاية: إرسالها على Instagram أو WhatsApp.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
