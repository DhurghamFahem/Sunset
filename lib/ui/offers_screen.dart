import 'package:flutter/material.dart';

import 'widgets/offer_inquiry.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/offer.dart';
import 'admin/offer_editor.dart';
import 'widgets/common.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key, this.admin = false});
  final bool admin;
  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<TattooOffer> offers = [];
  bool started = false, loading = false, more = false;
  String? error;
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
  void didUpdateWidget(OffersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admin != widget.admin) {
      offers = [];
      more = false;
      load();
    }
  }

  Future<void> load({bool next = false}) async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await AppScope.of(context).offers
          .list(admin: widget.admin, offset: next ? offers.length : 0);
      if (!mounted || ticket != generation) return;
      setState(() {
        offers = [...(next ? offers : <TattooOffer>[]), ...page];
        more = page.length == AppConfig.pageSize;
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = 'تعذر تحميل العروض. أعد المحاولة.');
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> edit([TattooOffer? offer]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OfferEditor(offer: offer)),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> remove(TattooOffer offer) async {
    if (!await confirm(
      context,
      'حذف العرض؟',
      'ينحذف العرض فقط وتبقى الوشومات في الكتالوج.',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await AppScope.of(context).offers.delete(offer.id);
      if (mounted) await load();
    } catch (_) {
      if (mounted) showNotice(context, 'تعذر حذف العرض. أعد المحاولة.');
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'العروض',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث العروض',
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh),
                ),
                if (widget.admin)
                  FilledButton.icon(
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة عرض'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.admin && AppConfig.useTestData)
              const Text(
                'وضع التجربة: العروض مؤقتة وتنحذف عند إعادة تحميل الصفحة.',
              ),
            if (!widget.admin)
              const Text(
                'تصميم واحد أو مجموعة وشومات بسعر عرض واحد. قطعة من كل تصميم، بدون التوصيل.',
              ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(onPressed: load, child: const Text('إعادة المحاولة')),
            ],
            if (!loading && error == null && offers.isEmpty)
              MessagePanel(
                title: widget.admin
                    ? 'أضف أول عرض من وشوماتك'
                    : 'ماكو عروض حالياً',
              ),
            for (final offer in offers)
              Card(
                key: ValueKey('offer-${offer.id}'),
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        offer.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${offer.formattedPrice} • ${offer.products.length} وشم',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (widget.admin)
                        Text(
                          !offer.active
                              ? 'مخفي'
                              : offer.publicVisible
                              ? 'ظاهر للزبائن'
                              : 'غير ظاهر: أحد الوشومات غير متاح',
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 148,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: offer.products.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final p = offer.products[i];
                            return SizedBox(
                              width: 118,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: CatalogImage(
                                      p.thumbnail,
                                      padding: 4,
                                    ),
                                  ),
                                  Text(
                                    p.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    p.dimensions,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.admin)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => edit(offer),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('تعديل العرض'),
                              ),
                            ),
                            IconButton(
                              tooltip: 'حذف العرض',
                              onPressed: () => remove(offer),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      else ...[
                        OutlinedButton.icon(
                          onPressed: () => inquireAboutOffer(
                            context,
                            offer,
                            instagram: true,
                          ),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('استفسر عن العرض على إنستغرام'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => inquireAboutOffer(context, offer),
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('استفسر عن العرض على واتساب'),
                        ),
                      ],
                    ],
                  ),
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
  );
}
