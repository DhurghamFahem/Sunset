import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/catalog.dart';
import '../../state/catalog_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tattoo_card.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.categoryId});
  final String? categoryId;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  CatalogController? _controller;
  final scroll = ScrollController();
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

  @override
  void dispose() {
    scroll.dispose();
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
          final columns = width >= 1050
              ? 5
              : width >= 820
              ? 4
              : width >= 560
              ? 3
              : 2;
          final categoryName = c.categories
              .where((x) => x.id == widget.categoryId)
              .firstOrNull
              ?.name;
          return Center(
            child: SizedBox(
              width: width,
              child: CustomScrollView(
                controller: scroll,
                key: PageStorageKey('catalog-${widget.categoryId ?? 'all'}'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.categoryId == null) ...[
                            Text(
                              'اختار وشمك 🌿',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: forest,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'تصفح الموديلات، اختار اللي يعجبك، ودز اختياراتك إلنا على الإنستغرام.',
                              style: TextStyle(color: muted, fontSize: 14),
                            ),
                          ] else ...[
                            TextButton.icon(
                              onPressed: () => context.go('/categories'),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('التصنيفات'),
                            ),
                            Text(
                              categoryName ?? 'الوشومات',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
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
                          const SizedBox(height: 12),
                          const Text('مكان الوشم على الجسم'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              for (final value in BodyPlacement.values)
                                FilterChip(
                                  label: Text(value.label),
                                  selected: c.bodyPlacements.contains(value),
                                  onSelected: (_) =>
                                      c.toggleBodyPlacement(value),
                                ),
                            ],
                          ),
                          if (c.availableSizes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('القياسات المتوفرة (العرض × الارتفاع)'),
                            const SizedBox(height: 6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final size in c.availableSizes)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: 10,
                                      ),
                                      child: FilterChip(
                                        label: Text(
                                          size.label,
                                          textDirection: TextDirection.ltr,
                                        ),
                                        selected: c.sizes.contains(size),
                                        onSelected: (_) => c.toggleSize(size),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (c.audience != null ||
                              c.bodyPlacements.isNotEmpty ||
                              c.sizes.isNotEmpty)
                            TextButton(
                              onPressed: c.clearFilters,
                              child: const Text(
                                'مسح فلاتر النوع والمكان والقياس',
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            onChanged: c.setSearch,
                            decoration: const InputDecoration(
                              hintText: 'ابحث باسم الوشم أو وصفه أو وسومه',
                              hintStyle: TextStyle(fontSize: 14),
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.categoryId == null && c.categories.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'على ذوقك',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton(
                            onPressed: () => c.setCategory(null),
                            child: Text(
                              c.categoryId == null
                                  ? 'كل التصنيفات'
                                  : 'عرض كل التصنيفات',
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 128,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: c.categories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (context, i) {
                            final category = c.categories[i];
                            return SizedBox(
                              width: 90,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => c.setCategory(
                                  c.categoryId == category.id
                                      ? null
                                      : category.id,
                                ),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: SizedBox(
                                        height: 78,
                                        width: 86,
                                        child: CatalogImage(
                                          category.imageUrl,
                                          label: category.name,
                                          padding: 7,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${c.categoryId == category.id ? '✓ ' : ''}${category.name}',
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.55,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.categoryId == null
                                  ? 'اكتشف التصاميم'
                                  : 'موديلات القسم',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<CatalogSort>(
                              value: c.sort,
                              borderRadius: BorderRadius.circular(14),
                              style: const TextStyle(
                                fontFamily: 'NotoArabic',
                                fontSize: 13,
                                color: forest,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: CatalogSort.curated,
                                  child: Text('الكل'),
                                ),
                                DropdownMenuItem(
                                  value: CatalogSort.newest,
                                  child: Text('الأحدث'),
                                ),
                                DropdownMenuItem(
                                  value: CatalogSort.featured,
                                  child: Text('المميز'),
                                ),
                                DropdownMenuItem(
                                  value: CatalogSort.price,
                                  child: Text('السعر'),
                                ),
                                DropdownMenuItem(
                                  value: CatalogSort.size,
                                  child: Text('الحجم'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) c.setSort(v);
                              },
                            ),
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
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      mainAxisExtent: width < 400 ? 282 : 315,
                    ),
                  ),
                  if (c.failed)
                    SliverToBoxAdapter(
                      child: MessagePanel(
                        title: 'تعذر تحميل الموديلات. حاول مرة ثانية.',
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
                        title:
                            c.search.isNotEmpty ||
                                c.audience != null ||
                                c.bodyPlacements.isNotEmpty ||
                                c.sizes.isNotEmpty
                            ? 'ما لقينا وشم يطابق هالفلاتر'
                            : 'قريباً نضيف موديلات جديدة لهذا القسم 🌿',
                        detail:
                            c.search.isNotEmpty ||
                                c.audience != null ||
                                c.bodyPlacements.isNotEmpty ||
                                c.sizes.isNotEmpty
                            ? 'جرّب تغيّر البحث أو النوع أو مكان الوشم أو القياس.'
                            : null,
                      ),
                    ),
                  if (!c.loading && c.hasMore && !c.failed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton(
                          onPressed: c.loadMore,
                          child: const Text('عرض المزيد'),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
