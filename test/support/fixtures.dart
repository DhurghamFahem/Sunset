import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/catalog_repository.dart';

Tattoo fixture(int i, {String category = 'bracelets', int? price = 5000}) =>
    Tattoo(
      id: '$i',
      code: 'G2G-${i.toString().padLeft(3, '0')}',
      name: 'وشم تجريبي $i',
      imageUrl: 'https://example.invalid/$i.png',
      thumbnailUrl: 'https://example.invalid/thumb-$i.png',
      categoryIds: [category],
      width: 28,
      height: 7,
      price: price,
    );

class MemoryCatalog implements CatalogRepository {
  @override
  Future<List<TattooSize>> availableSizes() async => data
      .map((product) => product.size)
      .whereType<TattooSize>()
      .toSet()
      .toList();
  MemoryCatalog({List<Tattoo>? products})
    : data = products ?? List.generate(30, (i) => fixture(i + 1));
  final List<Tattoo> data;
  bool offline = false;
  final queries = <CatalogQuery>[];
  @override
  Future<List<Category>> categories({bool admin = false}) async => [
    const Category(id: 'bracelets', name: 'وشومات سوار'),
    const Category(id: 'flowers', name: 'ورود'),
  ];
  @override
  Future<List<Tattoo>> products(CatalogQuery query) async {
    queries.add(query);
    if (offline) throw StateError('offline');
    return data
        .where(
          (p) =>
              (query.categoryId == null ||
                  p.categoryIds.contains(query.categoryId)) &&
              (query.audience == null ||
                  p.audiences.contains(query.audience)) &&
              (query.bodyPlacements.isEmpty ||
                  p.bodyPlacements.any(query.bodyPlacements.contains)) &&
              p.code.contains(query.search),
        )
        .skip(query.offset)
        .take(24)
        .toList();
  }

  @override
  Future<Tattoo?> product(String id) async =>
      data.where((p) => p.id == id).firstOrNull;
  @override
  Future<List<Tattoo>> selected(List<String> ids) async {
    if (offline) throw StateError('offline');
    return data.where((p) => ids.contains(p.id)).toList();
  }
}
