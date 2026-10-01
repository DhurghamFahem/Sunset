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
    final app = AppScope.of(context);
    setState(() {
      busy = true;
      progress = 0;
    });
    app.analytics.event('share_started');
    try {
      final removed = await app.selection.reconcile(app.catalog);
      if (!mounted) return;
      if (removed > 0) {
        showNotice(
          context,
          'شِلنا $removed تصاميم مو متوفرة حالياً. راجع اختياراتك ودزها مرة ثانية.',
        );
        return;
      }
      final images = await SelectionRenderer().render(
        app.selection.items,
        onProgress: (value) {
          if (mounted) {
            setState(() {
              progress = value;
            });
          }
        },
      );
      if (!mounted || images.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ShareScreen(pages: images)),
      );
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'ما قدرنا نجهز الصور. اختياراتك محفوظة؛ تأكد من اتصالك وحاول مرة ثانية.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
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
            title: 'بعدك ما مختار أي وشم 🌿',
            detail: 'تصفح الموديلات واختار التصاميم اللي تعجبك.',
            action: FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('تصفح الوشومات'),
            ),
          );
        }
        final products = selection.items;
        final priced = products.where((p) => p.price != null).toList();
        final total = priced.fold<int>(0, (sum, p) => sum + p.price!);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 40),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'اختياراتي',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await confirm(
                                context,
                                'مسح الاختيارات؟',
                                'تحب تبدأ اختيار جديد؟ راح تنمسح اختياراتك الحالية.',
                              )) {
                                selection.clear();
                              }
                            },
                      child: const Text('مسح الاختيارات'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'كل اللي عجبك، بمكان واحد.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                ...products.map(
                  (p) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7DE)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 100,
                            height: 115,
                            child: CatalogImage(p.thumbnail, label: p.code),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.code,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontFamily: 'sans-serif',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (p.dimensions.isNotEmpty)
                                Text(
                                  p.dimensions,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 13,
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
                          tooltip: 'إزالة ${p.code}',
                          onPressed: busy ? null : () => selection.toggle(p),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'عدد الوشومات: ${selection.count}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                if (priced.isNotEmpty)
                  Text(
                    '${priced.length == products.length ? 'المجموع' : 'مجموع التصاميم المسعّرة'}: ${AppConfig.money(total)}',
                  ),
                const SizedBox(height: 8),
                const Text(
                  'نكمل تفاصيل الطلب وياك على الإنستغرام.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 22),
                if (busy) ...[
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'نجهز صور اختياراتك…',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: busy ? null : generate,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('إرسال اختياراتي عبر Instagram'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
