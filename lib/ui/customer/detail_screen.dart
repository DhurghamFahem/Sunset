import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/catalog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tattoo_gallery.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.id});
  final String id;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Future<Tattoo?>? future;
  String? categoryName;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (future != null) return;
    final app = AppScope.of(context);
    app.analytics.event('tattoo_viewed', catalogId: widget.id);
    future = app.catalog.product(widget.id).then((p) async {
      if (p != null) {
        try {
          categoryName = (await app.catalog.categories())
              .where((c) => p.categoryIds.contains(c.id))
              .map((c) => c.name)
              .join(' • ');
        } catch (_) {}
      }
      return p;
    });
  }

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: muted, fontSize: 11)),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MessagePanel(
              title: 'تعذر تحميل الوشم. حاول مرة ثانية.',
              action: OutlinedButton(
                onPressed: () => setState(() {
                  future = AppScope.of(context).catalog.product(widget.id);
                }),
                child: const Text('إعادة المحاولة'),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: SkeletonBox(),
            );
          }
          final p = snapshot.data;
          if (p == null) {
            return MessagePanel(
              title: 'هذا الوشم مو متوفر حالياً',
              action: FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('تصفح الوشومات'),
              ),
            );
          }
          final selection = AppScope.of(context).selection;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final gallery = TattooGallery(
                          key: ValueKey(p.id),
                          images: p.images,
                          label: p.displayName,
                        );
                        final information = StudioPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'تفاصيل التصميم',
                                style: TextStyle(
                                  color: clay,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (constraints.maxWidth >= 800) ...[
                                Text(
                                  p.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                if (categoryName?.isNotEmpty ?? false)
                                  Text(
                                    categoryName!,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                if (p.price != null) ...[
                                  const SizedBox(height: 20),
                                  Text(
                                    p.formattedPrice,
                                    style: const TextStyle(
                                      color: forest,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 22),
                                child: Divider(),
                              ),
                              _detail(
                                Icons.people_outline,
                                'مناسب لـ',
                                p.audiences
                                    .map((value) => value.label)
                                    .join(' و '),
                              ),
                              if (p.dimensions.isNotEmpty)
                                _detail(
                                  Icons.straighten,
                                  'القياس',
                                  p.dimensions,
                                ),
                              if (p.bodyPlacements.isNotEmpty)
                                _detail(
                                  Icons.gesture,
                                  'أماكن الوشم',
                                  p.bodyPlacements
                                      .map((value) => value.label)
                                      .join('، '),
                                ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: sage,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.favorite_border,
                                      size: 20,
                                      color: forest,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'عجبك التصميم؟ أضفه لاختياراتك وشاركنا صورته على Instagram أو WhatsApp.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: forest,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                        if (constraints.maxWidth >= 800) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: gallery),
                                const SizedBox(width: 32),
                                Expanded(flex: 4, child: information),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    p.displayName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  if (categoryName?.isNotEmpty ?? false)
                                    Text(
                                      categoryName!,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (p.price != null)
                                    Text(
                                      p.formattedPrice,
                                      style: const TextStyle(
                                        color: forest,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            gallery,
                            const SizedBox(height: 24),
                            information,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width < 800
                        ? double.infinity
                        : 560,
                    child: ListenableBuilder(
                      listenable: selection,
                      builder: (context, _) => FilledButton.icon(
                        onPressed: () => selection.toggle(p),
                        icon: Icon(
                          selection.contains(p.id) ? Icons.check : Icons.add,
                        ),
                        label: Text(
                          selection.contains(p.id)
                              ? 'تم الاختيار ✓'
                              : 'أضف لاختياراتي',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
