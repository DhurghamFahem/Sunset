import '../config.dart';
import '../models/catalog.dart';
import '../models/catalog_search.dart';
import '../services/admin_service.dart';
import 'catalog_repository.dart';

/// Temporary, local-only inventory; never reads or writes Supabase.
class TestCatalogRepository implements CatalogRepository {
  TestCatalogRepository()
    : _categories = List.of(_seedCategories),
      _products = List.of(_seedProducts);

  final List<Category> _categories;
  final List<Tattoo> _products;
  int _nextId = 0;

  bool _visible(Tattoo product) =>
      product.active &&
      product.categoryIds.any(
        (id) => _categories.any((c) => c.id == id && c.active),
      );

  void save(String table, Json data, {String? id}) {
    final recordId = id ?? 'test-created-${++_nextId}';
    if (table == 'categories') {
      final record = Category.fromJson({...data, 'id': recordId});
      _categories.removeWhere((category) => category.id == recordId);
      _categories.add(record);
    } else if (table == 'products') {
      final record = Tattoo.fromJson({...data, 'id': recordId});
      if (_products.any((p) => p.id != recordId && p.code == record.code)) {
        throw CatalogInputException('رقم التصميم مستخدم. اختار رقم ثاني.');
      }
      if (record.categoryIds.isEmpty ||
          record.categoryIds.any(
            (id) => !_categories.any((category) => category.id == id),
          )) {
        throw CatalogInputException('اختار تصنيف موجود.');
      }
      _products.removeWhere((product) => product.id == recordId);
      _products.add(record);
    } else {
      throw ArgumentError('Invalid table');
    }
  }

  void deleteCategory(String id) {
    if (_products.any((product) => product.categoryIds.contains(id))) {
      throw CatalogInputException(
        'القسم بيه وشومات. انقلها لقسم ثاني قبل الحذف.',
      );
    }
    _categories.removeWhere((category) => category.id == id);
  }

  @override
  Future<List<String>> availableTags() async =>
      _products
          .where(_visible)
          .expand((product) => product.tags)
          .toSet()
          .toList()
        ..sort();
  static const _seedCategories = [
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
  static final _seedProducts = List<Tattoo>.generate(36, (index) {
    final category = _seedCategories[index % _seedCategories.length];
    final number = (index + 1).toString().padLeft(3, '0');
    return Tattoo(
      id: 'test-tattoo-$number',
      code: 'TEST-$number',
      name: '${category.name} ${index ~/ _seedCategories.length + 1}',
      tags: switch (index % 4) {
        0 => ['زهرة', 'نبات', 'ناعم', 'floral'],
        1 => ['أوراق', 'طبيعة', 'غصن', 'botanical'],
        2 => ['نجمة', 'سماء', 'بسيط', 'stars'],
        _ => ['حب', 'قلب', 'ناعم', 'love'],
      },
      categoryIds: [
        category.id,
        if (index % 3 == 0)
          _seedCategories[(index + 1) % _seedCategories.length].id,
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
      _categories.where((c) => admin || c.active).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<List<TattooSize>> availableSizes() async =>
      _products
          .where(_visible)
          .map((product) => product.size)
          .whereType<TattooSize>()
          .toSet()
          .toList()
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
      return (query.admin || _visible(product)) &&
          (query.categoryId == null ||
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
  Future<Tattoo?> product(String id) async => _products
      .where((product) => product.id == id && _visible(product))
      .firstOrNull;

  @override
  Future<List<Tattoo>> selected(List<String> ids) async {
    final selectedIds = ids.toSet();
    return _products
        .where(
          (product) => selectedIds.contains(product.id) && _visible(product),
        )
        .toList();
  }
}
