import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/models/catalog_search.dart';
import 'package:sunset/repositories/catalog_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';

void main() {
  test('Arabic and English search normalization and tag deduplication', () {
    expect(
      normalizeCatalogSearch('  وَرْدَة أَلِفٌ FLOWER  '),
      'ورده الف flower',
    );
    expect(
      normalizeCatalogSearch('أوراق إبرة آية ٱسم هدى'),
      'اوراق ابره ايه اسم هدي',
    );
    expect(parseCatalogTags('وردة، وَرْدَة, #floral; FLORAL\nناعم'), [
      'وردة',
      'floral',
      'ناعم',
    ]);
    expect(catalogSearchTerms('  ",()% _'), isEmpty);
  });

  test('old records use a customer name fallback and new tags persist', () {
    final old = Tattoo.fromJson({
      'id': 'old',
      'code': 'INTERNAL',
      'image_url': 'image',
    });
    expect(old.displayName, 'وشم عشبي');
    expect(old.tags, isEmpty);
    const current = Tattoo(
      id: 'new',
      code: 'INTERNAL',
      imageUrl: 'image',
      name: 'وردة ناعمة',
      tags: ['طبيعة', 'floral'],
      width: 5.5,
      height: 8,
    );
    final restored = Tattoo.fromJson(jsonDecode(jsonEncode(current.toJson())));
    expect(restored.displayName, 'وردة ناعمة');
    expect(restored.tags, current.tags);
    expect(restored.size, const TattooSize(5.5, 8));
    expect(restored.dimensions, '5.5 × 8 سم');
  });

  test('search matches all words across name and tags, while code search is admin-only', () async {
    final repository = TestCatalogRepository();
    final matches = await repository.products(
      const CatalogQuery(search: 'وُرُود FLORAL نَاعِم'),
    );
    expect(matches, hasLength(9));
    expect(
      await repository.products(const CatalogQuery(search: 'ورود unknown')),
      isEmpty,
    );
    expect(
      await repository.products(const CatalogQuery(search: 'TEST-001')),
      isEmpty,
    );
    expect(
      (await repository.products(
        const CatalogQuery(search: 'test 001', admin: true),
      )).single.code,
      'TEST-001',
    );
  });

  test(
    'sizes come from inventory and filter exact pairs rather than area',
    () async {
      final repository = TestCatalogRepository();
      final sizes = await repository.availableSizes();
      expect(sizes, hasLength(6));
      expect(sizes.toSet(), hasLength(6));
      final matches = await repository.products(
        const CatalogQuery(sizes: [TattooSize(3, 5), TattooSize(5, 8)]),
      );
      expect(matches, hasLength(12));
      expect(
        matches.every(
          (p) =>
              [const TattooSize(3, 5), const TattooSize(5, 8)].contains(p.size),
        ),
        isTrue,
      );
      expect(
        await repository.products(
          const CatalogQuery(sizes: [TattooSize(5, 3)]),
        ),
        isEmpty,
      );
      final combined = await repository.products(
        const CatalogQuery(
          sizes: [TattooSize(3, 5)],
          audience: TattooAudience.men,
          bodyPlacements: [BodyPlacement.wrist],
          search: 'ورود',
        ),
      );
      expect(combined.single.code, 'TEST-001');
    },
  );

  test('Supabase combines every search word and exact size pairs', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.url.path.endsWith('catalog_available_sizes')
              ? '[{"width_cm":5.5,"height_cm":8}]'
              : '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final repository = SupabaseCatalogRepository(client);
    await repository.products(
      const CatalogQuery(
        search: 'وَرْدَة نَاعِم',
        sizes: [TattooSize(5.5, 8), TattooSize(10, 15)],
      ),
    );
    expect(requests.last.url.queryParametersAll['search_text'], [
      'ilike.%ورده%',
      'ilike.%ناعم%',
    ]);
    expect(
      requests.last.url.queryParameters['or'],
      '(and(width_cm.eq.5.5,height_cm.eq.8.0),and(width_cm.eq.10.0,height_cm.eq.15.0))',
    );
    expect(await repository.availableSizes(), [const TattooSize(5.5, 8)]);
    await client.dispose();
  });
}
