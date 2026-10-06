import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/services/catalog_image_exporter.dart';
import 'package:sunset/services/catalog_image_storage.dart';
import 'package:sunset/services/selection_renderer.dart';

import 'support/fixtures.dart';

class TestStorage implements CatalogImageStorage {
  final values = <String, List<Uint8List>>{};
  bool fail = false;
  @override
  Future<List<Uint8List>?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, List<Uint8List> pages) async {
    if (fail) throw StateError('quota');
    values[key] = pages;
    return true;
  }
}

class TestRenderer extends SelectionRenderer {
  int renders = 0;
  List<Tattoo> rendered = [];
  @override
  Future<List<Uint8List>> render(
    List<Tattoo> products, {
    ValueChanged<double>? onProgress,
    String? orderCode,
    bool showPrices = false,
    Map<String, int> quantities = const {},
  }) async {
    renders++;
    rendered = products;
    expect(showPrices, isTrue);
    expect(orderCode, isNull);
    expect(quantities, isEmpty);
    return SelectionRenderer.pages(products)
        .map((_) => Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]))
        .toList();
  }
}

void main() {
  test(
    'all filtered pages export and later sessions reuse unchanged images',
    () async {
      final catalog = MemoryCatalog();
      final storage = TestStorage();
      final renderer = TestRenderer();
      final exporter = CatalogImageExporter(
        storage: storage,
        renderer: renderer,
      );
      final first = await exporter.generate(
        catalog,
        const CatalogQuery(categoryId: 'bracelets'),
      );
      expect(first.pages.length, 5);
      expect(renderer.rendered.length, 30);
      expect(first.saved, isTrue);
      expect(first.reused, isFalse);
      final later = await CatalogImageExporter(
        storage: storage,
        renderer: renderer,
      ).generate(catalog, const CatalogQuery(categoryId: 'bracelets'));
      expect(later.reused, isTrue);
      expect(renderer.renders, 1);
      expect(catalog.queries.map((q) => q.offset), [0, 24, 0, 24]);
    },
  );

  test(
    'price, artwork, membership and filters invalidate saved images',
    () async {
      final catalog = MemoryCatalog(products: [fixture(1), fixture(2)]);
      final renderer = TestRenderer();
      final exporter = CatalogImageExporter(
        storage: TestStorage(),
        renderer: renderer,
      );
      Future<void> generate() async {
        expect(
          (await exporter.generate(catalog, const CatalogQuery())).reused,
          isFalse,
        );
      }

      await generate();
      catalog.data[0] = fixture(1, price: 7000);
      await generate();
      catalog.data[0] = Tattoo.fromJson({
        ...catalog.data[0].toJson(),
        'image_url': 'new.png',
      });
      await generate();
      catalog.data.removeLast();
      await generate();
      final filtered = await exporter.generate(
        catalog,
        const CatalogQuery(search: '001'),
      );
      expect(filtered.reused, isFalse);
      expect(renderer.renders, 5);
    },
  );

  test('failed refresh never serves stale images and failed storage still allows export', () async {
    final catalog = MemoryCatalog(products: [fixture(1)]);
    final storage = TestStorage();
    final renderer = TestRenderer();
    final exporter = CatalogImageExporter(storage: storage, renderer: renderer);
    await exporter.generate(catalog, const CatalogQuery());
    catalog.offline = true;
    await expectLater(
      exporter.generate(catalog, const CatalogQuery()),
      throwsStateError,
    );
    expect(renderer.renders, 1);
    catalog.offline = false;
    storage.fail = true;
    catalog.data[0] = fixture(1, price: null);
    final result = await exporter.generate(catalog, const CatalogQuery());
    expect(result.pages, isNotEmpty);
    expect(result.saved, isFalse);
    expect(renderer.rendered.single.price, isNull);
  });
}
