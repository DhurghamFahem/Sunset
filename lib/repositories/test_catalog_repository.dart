import '../config.dart';
import '../models/catalog.dart';
import '../models/catalog_search.dart';
import 'catalog_repository.dart';

/// Temporary, local-only inventory; never reads or writes Supabase.
class TestCatalogRepository implements CatalogRepository {
  @override
  Future<List<String>> availableTags() async =>
      _products.expand((product) => product.tags).toSet().toList()..sort();
  static const _categories = [
    Category(
      id: 'test-flowers',
      name: 'ورود',
      imageUrl: 'asset:assets/test_catalog/flower.png',
    ),
    Category(
      id: 'test-branches',
      name: 'أغصان وأوراق',
      imageUrl: 'asset:assets/test_catalog/branch.png',
      sortOrder: 1,
    ),
    Category(
      id: 'test-stars',
      name: 'نجوم',
      imageUrl: 'asset:assets/test_catalog/star.png',
      sortOrder: 2,
    ),
    Category(
      id: 'test-hearts',
      name: 'قلوب',
      imageUrl: 'asset:assets/test_catalog/heart.png',
      sortOrder: 3,
    ),
  ];

  // More than one page, with varied prices, sizes, and badges for testing.
  // Increasing IDs represent increasing creation dates for newest sorting.
  static final _products = List<Tattoo>.generate(36, (index) {
    final category = _categories[index % _categories.length];
    final number = (index + 1).toString().padLeft(3, '0');
    return Tattoo(
      id: 'test-tattoo-$number',
      code: 'TEST-$number',
      name: '${category.name} ${index ~/ _categories.length + 1}',
      tags: switch (index % 4) {
        0 => ['زهرة', 'نبات', 'ناعم', 'floral'],
        1 => ['أوراق', 'طبيعة', 'غصن', 'botanical'],
        2 => ['نجمة', 'سماء', 'بسيط', 'stars'],
        _ => ['حب', 'قلب', 'ناعم', 'love'],
      },
      categoryIds: [
        category.id,
        if (index % 3 == 0) _categories[(index + 1) % _categories.length].id,
      ],
      audiences: switch (index % 3) {
        0 => const [TattooAudience.men],
        1 => const [TattooAudience.women],
        _ => const [TattooAudience.men, TattooAudience.women],
      },
      bodyPlacements: [
        BodyPlacement.values[index % BodyPlacement.values.length],
        BodyPlacement.values[(index + 3) % BodyPlacement.values.length],
      ],
      imageUrl: category.imageUrl!,
      additionalImages: [
        TattooImage(
          url: category.imageUrl!.replaceFirst('.png', '-alternate.png'),
        ),
      ],
      width: const [3.0, 5.0, 8.0, 10.0, 12.0, 15.0][index % 6],
      height: const [5.0, 8.0, 10.0, 15.0, 18.0, 20.0][index % 6],
      price: index % 8 == 0 ? null : 3000 + (index % 10) * 1000,
      featured: index % 3 == 0,
      isNew: index >= 28,
      sortOrder: index,
    );
  });

  @override
  Future<List<Category>> categories({bool admin = false}) async =>
      List.of(_categories);

  @override
  Future<List<TattooSize>> availableSizes() async =>
      _products.map((product) => product.size!).toSet().toList()
        ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));

  @override
  Future<List<Tattoo>> products(CatalogQuery query) async {
    final terms = catalogSearchTerms(query.search);
    final matches = _products.where((product) {
      final searchable = normalizeCatalogSearch(
        [
          product.name ?? '',
          ...product.tags,
          if (query.admin) product.code,
        ].join(' '),
      );
      return (query.categoryId == null ||
              product.categoryIds.contains(query.categoryId)) &&
          (query.audience == null ||
              product.audiences.contains(query.audience)) &&
          (query.bodyPlacements.isEmpty ||
              product.bodyPlacements.any(query.bodyPlacements.contains)) &&
          (query.sizes.isEmpty || query.sizes.contains(product.size)) &&
          (query.tags.isEmpty || product.tags.any(query.tags.contains)) &&
          terms.every(searchable.contains) &&
          (query.sort != CatalogSort.featured || product.featured);
    }).toList();
    matches.sort((a, b) {
      final order = switch (query.sort) {
        CatalogSort.newest => b.sortOrder.compareTo(a.sortOrder),
        CatalogSort.price => _nullableCompare(a.price, b.price),
        CatalogSort.size => _nullableCompare(_area(a), _area(b)),
        _ => a.sortOrder.compareTo(b.sortOrder),
      };
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return matches.skip(query.offset).take(AppConfig.pageSize).toList();
  }

  static double? _area(Tattoo product) =>
      product.width == null || product.height == null
      ? null
      : product.width! * product.height!;

  static int _nullableCompare(num? a, num? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  @override
  Future<Tattoo?> product(String id) async =>
      _products.where((product) => product.id == id).firstOrNull;

  @override
  Future<List<Tattoo>> selected(List<String> ids) async {
    final selectedIds = ids.toSet();
    return _products
        .where((product) => selectedIds.contains(product.id))
        .toList();
  }
}
