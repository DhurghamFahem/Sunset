import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import '../../state/catalog_controller.dart';
import '../theme.dart';

/// Changes stay local until Apply; dismissing the sheet leaves browsing intact.
class CatalogFilterSheet extends StatefulWidget {
  const CatalogFilterSheet({super.key, required this.controller});
  final CatalogController controller;
  @override
  State<CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<CatalogFilterSheet> {
  late String? category = widget.controller.categoryId;
  late final placements = widget.controller.bodyPlacements.toSet();
  late final sizes = widget.controller.sizes.toSet();
  late final tags = widget.controller.tags.toSet();
  late CatalogSort sort = widget.controller.sort;

  void reset() => setState(() {
    category = null;
    placements.clear();
    sizes.clear();
    tags.clear();
    sort = CatalogSort.curated;
  });

  Widget section(
    String title,
    String summary,
    List<Widget> choices, {
    bool open = false,
  }) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line),
    ),
    child: ExpansionTile(
      key: PageStorageKey(title),
      initiallyExpanded: open,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 12),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Wrap(spacing: 8, runSpacing: 4, children: choices)],
    ),
  );

  Widget chip<T>(T value, String label, Set<T> selected) => FilterChip(
    key: ValueKey('filter-$label'),
    label: Text(label),
    selected: selected.contains(value),
    onSelected: (checked) => setState(() {
      checked ? selected.add(value) : selected.remove(value);
    }),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'خلّيها على ذوقك',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق الفلاتر',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'حدّد التفاصيل اللي تحبها، ونقرّب لك الاختيار.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    section(
                      'مكان الوشم',
                      placements.isEmpty
                          ? 'أي مكان'
                          : placements.map((value) => value.label).join('، '),
                      [
                        for (final value in BodyPlacement.values)
                          chip(value, value.label, placements),
                      ],
                      open: true,
                    ),
                    if (c.categories.isNotEmpty)
                      section(
                        'التصنيف',
                        c.categories
                                .where((value) => value.id == category)
                                .firstOrNull
                                ?.name ??
                            'كل التصنيفات',
                        [
                          ChoiceChip(
                            label: const Text('الكل'),
                            selected: category == null,
                            onSelected: (_) => setState(() => category = null),
                          ),
                          for (final value in c.categories)
                            ChoiceChip(
                              label: Text(value.name),
                              selected: category == value.id,
                              onSelected: (_) =>
                                  setState(() => category = value.id),
                            ),
                        ],
                      ),
                    if (c.availableSizes.isNotEmpty)
                      section(
                        'القياس',
                        sizes.isEmpty
                            ? 'كل القياسات • العرض × الارتفاع'
                            : sizes.map((value) => value.label).join('، '),
                        [
                          for (final value in c.availableSizes)
                            chip(value, value.label, sizes),
                        ],
                      ),
                    if (c.availableTags.isNotEmpty)
                      section(
                        'الوسوم',
                        tags.isEmpty ? 'أي وسم' : tags.join('، '),
                        [
                          for (final value in c.availableTags)
                            chip(value, value, tags),
                        ],
                      ),
                    section('الترتيب', _sortLabels[sort]!, [
                      for (final entry in _sortLabels.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: sort == entry.key,
                          onSelected: (_) => setState(() => sort = entry.key),
                        ),
                    ]),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(onPressed: reset, child: const Text('مسح')),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          c.applyFilters(
                            category: category,
                            placements: placements.toList(),
                            selectedSizes: sizes.toList(),
                            selectedTags: tags.toList(),
                            order: sort,
                          );
                          Navigator.pop(context);
                        },
                        child: const Text('عرض الوشومات'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

const _sortLabels = {
  CatalogSort.curated: 'المقترحة',
  CatalogSort.newest: 'الأحدث',
  CatalogSort.featured: 'المميزة',
  CatalogSort.price: 'الأقل سعراً',
  CatalogSort.size: 'الأصغر حجماً',
};
