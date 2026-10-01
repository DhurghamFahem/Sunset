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

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('رجوع للموديلات'),
                ),
              ),
              TattooGallery(
                key: ValueKey(p.id),
                images: p.images,
                label: p.displayName,
              ),
              const SizedBox(height: 16),
              Text(
                p.displayName,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              if (categoryName != null)
                Text(categoryName!, style: const TextStyle(color: muted)),
              const SizedBox(height: 8),
              Text(
                'مناسب لـ: ${p.audiences.map((value) => value.label).join(' و ')}',
              ),
              if (p.bodyPlacements.isNotEmpty)
                Text(
                  'أماكن الوشم: ${p.bodyPlacements.map((value) => value.label).join('، ')}',
                ),
              if (p.dimensions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(p.dimensions),
                ),
              if (p.price != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    p.formattedPrice,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              ListenableBuilder(
                listenable: selection,
                builder: (context, _) => FilledButton.icon(
                  onPressed: () => selection.toggle(p),
                  icon: Icon(
                    selection.contains(p.id)
                        ? Icons.check
                        : Icons.favorite_border,
                  ),
                  label: Text(
                    selection.contains(p.id)
                        ? 'إزالة من اختياراتي'
                        : 'أضف لاختياراتي',
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
