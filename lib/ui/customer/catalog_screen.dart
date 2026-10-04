import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/catalog.dart';
import '../../state/catalog_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tattoo_card.dart';
import 'catalog_filter_sheet.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.categoryId});
  final String? categoryId;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  CatalogController? _controller;
  final scroll = ScrollController();
  final search = TextEditingController();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final services = AppScope.of(context);
    _controller = CatalogController(
      services.catalog,
      categoryId: widget.categoryId,
    )..initialize();
    if (widget.categoryId != null) {
      services.analytics.event('category_opened', catalogId: widget.categoryId);
    }
    scroll.addListener(() {
      if (scroll.position.extentAfter < 650 && !_controller!.failed) {
        _controller!.loadMore();
      }
    });
  }

  void reset() {
    search.clear();
    _controller!.resetAll();
  }

  Future<void> filters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => CatalogFilterSheet(controller: _controller!),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth > 1240 ? 1200.0 : box.maxWidth - 32;
          final columns = width >= 1000
              ? 4
              : width >= 650
              ? 3
              : 2;
          final category = c.categories
              .where((value) => value.id == c.categoryId)
              .firstOrNull;
          return Center(
            child: SizedBox(
              width: width,
              child: CustomScrollView(
                controller: scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                key: PageStorageKey('catalog-${widget.categoryId ?? 'all'}'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CatalogIntro(
                            title: category?.name,
                            wide: width >= 650,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: search,
                                  onChanged: c.setSearch,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  decoration: InputDecoration(
                                    hintText: 'تدور على شي معيّن؟',
                                    hintStyle: const TextStyle(fontSize: 13),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 22,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    suffixIcon: search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'مسح البحث',
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              search.clear();
                                              c.setSearch('');
                                            },
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                key: const ValueKey('open-filters'),
                                onPressed: filters,
                                icon: const Icon(Icons.tune, size: 19),
                                label: Text(
                                  c.filterCount == 0
                                      ? 'فلترة'
                                      : 'فلترة (${c.filterCount})',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('الجميع'),
                                selected: c.audience == null,
                                onSelected: (_) => c.setAudience(null),
                              ),
                              for (final value in TattooAudience.values)
                                ChoiceChip(
                                  label: Text(value.label),
                                  selected: c.audience == value,
                                  onSelected: (_) => c.setAudience(value),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'اكتشف التصاميم',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                c.loading
                                    ? 'جاري التحميل…'
                                    : '${c.products.length}${c.hasMore ? '+' : ''} تصميم',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                          if (c.hasFilters)
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'حسب اختيارك',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: reset,
                                  child: const Text('عرض الكل'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => index >= c.products.length
                          ? const SkeletonBox()
                          : TattooCard(c.products[index]),
                      childCount:
                          c.products.length + (c.loading ? columns * 2 : 0),
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: width < 600 ? 12 : 20,
                      mainAxisExtent:
                          (width < 400
                              ? 292.0
                              : width < 650
                              ? 330.0
                              : (MediaQuery.sizeOf(context).height - 440).clamp(
                                  300.0,
                                  420.0,
                                )) +
                          (MediaQuery.textScalerOf(context).scale(14) - 14) * 5,
                    ),
                  ),
                  if (c.failed)
                    SliverToBoxAdapter(
                      child: MessagePanel(
                        title: 'تعذر تحميل الوشومات',
                        detail: 'اختياراتك بعدها محفوظة.',
                        icon: Icons.wifi_off_outlined,
                        action: OutlinedButton(
                          onPressed: c.loadMore,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ),
                    ),
                  if (!c.failed && !c.loading && c.products.isEmpty)
                    SliverToBoxAdapter(
                      child: MessagePanel(
                        title: c.hasFilters
                            ? 'ما لقينا وشم يطابق اختيارك'
                            : 'قريباً نضيف موديلات جديدة 🌿',
                        detail: c.hasFilters
                            ? 'جرّب تشوف باقي التصاميم.'
                            : null,
                        action: c.hasFilters
                            ? FilledButton(
                                onPressed: reset,
                                child: const Text('عرض كل الوشومات'),
                              )
                            : null,
                      ),
                    ),
                  if (!c.loading && c.hasMore && !c.failed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton(
                          onPressed: c.loadMore,
                          child: const Text('وشومات أكثر'),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CatalogIntro extends StatelessWidget {
  const _CatalogIntro({this.title, required this.wide});
  final String? title;
  final bool wide;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Stack(
      children: [
        Positioned(
          left: wide ? 36 : -22,
          top: -10,
          bottom: -20,
          width: wide ? 220 : 130,
          child: const BotanicalMark(),
        ),
        Padding(
          padding: EdgeInsets.all(wide ? 24 : 18),
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: wide ? 240 : 58),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'G2G  /  HERBAL TATTOOS',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: Color(0xFF8DB36F),
                    fontSize: 10,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title ?? 'تفاصيل صغيرة، تشبهك.',
                  style: TextStyle(
                    fontFamily: displayFont,
                    color: paper,
                    fontSize: wide ? 34 : 22,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'اختار وشمك، وخلي الباقي علينا.',
                  style: TextStyle(
                    color: const Color(0xFFE8E0CF),
                    fontSize: wide ? 14 : 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
