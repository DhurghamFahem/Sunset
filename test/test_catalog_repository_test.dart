import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/services/selection_renderer.dart';
import 'package:sunset/state/selection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = TestCatalogRepository();

  test('pages are stable, disjoint, and terminate', () async {
    final first = await repository.products(const CatalogQuery());
    final second = await repository.products(const CatalogQuery(offset: 24));
    expect(first, hasLength(24));
    expect(second, hasLength(12));
    expect({
      ...first.map((p) => p.id),
      ...second.map((p) => p.id),
    }, hasLength(36));
    expect(await repository.products(const CatalogQuery(offset: 36)), isEmpty);
  });

  test('category, Arabic name, code, and featured filters work', () async {
    final categories = await repository.categories();
    expect(categories, hasLength(4));
    final category = categories.first;
    final matches = await repository.products(
      CatalogQuery(categoryId: category.id, search: 'ورود'),
    );
    expect(matches, hasLength(9));
    expect(matches.every((p) => p.categoryIds.contains(category.id)), isTrue);
    final byCode = await repository.products(
      const CatalogQuery(search: 'test-002', admin: true),
    );
    expect(byCode.single.code, 'TEST-002');
    final featured = await repository.products(
      const CatalogQuery(sort: CatalogSort.featured),
    );
    expect(featured, hasLength(12));
    expect(featured.every((p) => p.featured), isTrue);
    expect(
      await repository.products(const CatalogQuery(search: 'missing')),
      isEmpty,
    );
  });

  test('price and size sort ascending with unknown values last', () async {
    for (final sort in [CatalogSort.price, CatalogSort.size]) {
      final products = [
        ...await repository.products(CatalogQuery(sort: sort)),
        ...await repository.products(CatalogQuery(sort: sort, offset: 24)),
      ];
      num? value(Tattoo p) => sort == CatalogSort.price
          ? p.price
          : p.width == null
          ? null
          : p.width! * p.height!;
      final known = products.map(value).whereType<num>().toList();
      expect(known, orderedEquals([...known]..sort()));
      expect(
        products.skip(known.length).every((p) => value(p) == null),
        isTrue,
      );
      if (sort == CatalogSort.price) {
        expect(known.length, lessThan(products.length));
      }
    }
    final newest = await repository.products(
      const CatalogQuery(sort: CatalogSort.newest),
    );
    expect(newest.first.code, 'TEST-036');
  });

  test('details and selection reconciliation handle missing IDs', () async {
    final product = (await repository.products(const CatalogQuery())).first;
    expect((await repository.product(product.id))?.code, product.code);
    expect(await repository.product('missing'), isNull);
    expect(await repository.selected([]), isEmpty);
    final selected = await repository.selected([
      product.id,
      'missing',
      product.id,
    ]);
    expect(selected.single.id, product.id);
  });

  test('test selections persist separately from real selections', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final live = SelectionStore(preferences, NoopAnalytics());
    final demo = SelectionStore(
      preferences,
      NoopAnalytics(),
      storageKey: 'g2g.test-selections.v1',
    );
    final products = await repository.products(const CatalogQuery());
    live.toggle(products[0]);
    demo.toggle(products[1]);
    await live.flush();
    await demo.flush();
    expect(
      SelectionStore(preferences, NoopAnalytics()).items.single.id,
      products[0].id,
    );
    expect(
      SelectionStore(
        preferences,
        NoopAnalytics(),
        storageKey: 'g2g.test-selections.v1',
      ).items.single.id,
      products[1].id,
    );
    live.dispose();
    demo.dispose();
  });

  test('bundled artwork exports without an HTTP image loader', () async {
    final products = await repository.products(const CatalogQuery());
    final images = await SelectionRenderer().render(products.take(4).toList());
    expect(images, hasLength(1));
    expect(images.single.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
