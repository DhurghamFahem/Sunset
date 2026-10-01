import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/catalog_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/state/catalog_controller.dart';

void main() {
  test(
    'available tags are unique and multiple selections match any chosen tag',
    () async {
      final repo = TestCatalogRepository();
      final tags = await repo.availableTags();
      expect(tags, containsAll(['floral', 'love', 'ناعم']));
      expect(tags.length, tags.toSet().length);
      final products = await repo.products(
        const CatalogQuery(tags: ['floral', 'love']),
      );
      expect(products, hasLength(18));
      expect(
        products.every(
          (product) => product.tags.any(['floral', 'love'].contains),
        ),
        isTrue,
      );
      expect(
        await repo.products(const CatalogQuery(tags: ['missing'])),
        isEmpty,
      );
      // Selection is a tag match, not an incidental name/text match.
      expect(await repo.products(const CatalogQuery(tags: ['ورود'])), isEmpty);
    },
  );

  test('tag choices combine with every other filter', () async {
    final products = await TestCatalogRepository().products(
      const CatalogQuery(
        tags: ['floral'],
        categoryId: 'test-branches',
        audience: TattooAudience.men,
        bodyPlacements: [BodyPlacement.wrist],
        sizes: [TattooSize(3, 5)],
        search: 'ناعم',
      ),
    );
    expect(products.single.code, 'TEST-001');
  });

  test(
    'tag toggles reset pagination and clearing tags preserves other choices',
    () async {
      final state = CatalogController(TestCatalogRepository());
      await state.initialize();
      await state.loadMore();
      expect(state.products, hasLength(36));
      expect(state.availableTags, contains('floral'));
      state.toggleTag('floral');
      await Future<void>.delayed(Duration.zero);
      expect(state.products, hasLength(9));
      state.toggleTag('love');
      await Future<void>.delayed(Duration.zero);
      expect(state.products, hasLength(18));
      state.toggleTag('love');
      state.setAudience(TattooAudience.men);
      state.toggleSize(const TattooSize(3, 5));
      await Future<void>.delayed(Duration.zero);
      state.clearTags();
      await Future<void>.delayed(Duration.zero);
      expect(state.tags, isEmpty);
      expect(state.audience, TattooAudience.men);
      expect(state.sizes, [const TattooSize(3, 5)]);
      state.toggleTag('floral');
      state.clearFilters();
      await Future<void>.delayed(Duration.zero);
      expect(state.tags, isEmpty);
      expect(state.products, hasLength(24));
      state.dispose();
    },
  );

  test(
    'Supabase fetches options and filters the tag array alongside search',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path.endsWith('catalog_available_tags')
                ? '["floral","love"]'
                : '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = SupabaseCatalogRepository(client);
      expect(await repo.availableTags(), ['floral', 'love']);
      await repo.products(
        const CatalogQuery(tags: ['floral', 'love'], search: 'ناعم'),
      );
      expect(requests.last.url.queryParameters['tags'], 'ov.{"floral","love"}');
      expect(requests.last.url.queryParameters['search_text'], 'ilike.%ناعم%');
      expect(requests.last.url.queryParameters['public_visible'], 'eq.true');
      await client.dispose();
    },
  );
}
