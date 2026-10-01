import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../config.dart';
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
      final pages = await SelectionRenderer().render(
        app.selection.items,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (!mounted) return;
      app.analytics.event('selection_exported');
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => ShareScreen(pages: pages)),
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
          (sum, product) => sum + product.price!,
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7DE)),
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
                                    width: 78,
                                    height: 88,
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
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'إزالة ${p.displayName}',
                                onPressed: busy
                                    ? null
                                    : () {
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
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E5DC))),
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
                                  '${selection.count} وشم',
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
                            'الخطوة الجاية: إرسالها على Instagram.',
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
