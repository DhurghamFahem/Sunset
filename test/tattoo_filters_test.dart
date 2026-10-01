import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/catalog_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/state/catalog_controller.dart';

void main() {
  test('old selection snapshots load and new properties round trip', () {
    final legacy = Tattoo.fromJson({
      'id': 'old',
      'code': 'G2G-001',
      'image_url': 'image',
      'category_id': 'flowers',
    });
    expect(legacy.categoryIds, ['flowers']);
    expect(legacy.audiences, TattooAudience.values);
    expect(legacy.bodyPlacements, isEmpty);
    const current = Tattoo(
      id: 'new',
      code: 'G2G-002',
      imageUrl: 'image',
      categoryIds: ['flowers', 'minimal'],
      audiences: [TattooAudience.women],
      bodyPlacements: [BodyPlacement.arm, BodyPlacement.back],
    );
    final restored = Tattoo.fromJson(jsonDecode(jsonEncode(current.toJson())));
    expect(restored.categoryIds, current.categoryIds);
    expect(restored.audiences, current.audiences);
    expect(restored.bodyPlacements, current.bodyPlacements);
  });

  test(
    'both audiences include shared tattoos and exclude the other-only audience',
    () async {
      final repo = TestCatalogRepository();
      final men = await repo.products(
        const CatalogQuery(audience: TattooAudience.men),
      );
      final women = await repo.products(
        const CatalogQuery(audience: TattooAudience.women),
      );
      expect(men.map((p) => p.code), containsAll(['TEST-001', 'TEST-003']));
      expect(men.map((p) => p.code), isNot(contains('TEST-002')));
      expect(women.map((p) => p.code), containsAll(['TEST-002', 'TEST-003']));
      expect(women.map((p) => p.code), isNot(contains('TEST-001')));
    },
  );

  test(
    'secondary category and any placement combine with audience and search',
    () async {
      final repo = TestCatalogRepository();
      final matches = await repo.products(
        const CatalogQuery(
          categoryId: 'test-branches',
          audience: TattooAudience.men,
          bodyPlacements: [BodyPlacement.foot, BodyPlacement.wrist],
          search: 'TEST-001',
          admin: true,
        ),
      );
      expect(matches.single.code, 'TEST-001');
      expect(
        await repo.products(
          const CatalogQuery(
            categoryId: 'test-stars',
            audience: TattooAudience.men,
            search: 'TEST-001',
            admin: true,
          ),
        ),
        isEmpty,
      );
      expect(
        await repo.products(
          const CatalogQuery(
            bodyPlacements: [BodyPlacement.back],
            search: 'TEST-001',
            admin: true,
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'changing filters resets pagination and retains other dimensions',
    () async {
      final state = CatalogController(TestCatalogRepository());
      await state.initialize();
      await state.loadMore();
      expect(state.products, hasLength(36));
      state.setAudience(TattooAudience.men);
      await Future<void>.delayed(Duration.zero);
      expect(state.products, hasLength(24));
      state.toggleBodyPlacement(BodyPlacement.wrist);
      state.setCategory('test-branches');
      await Future<void>.delayed(Duration.zero);
      expect(state.products, isNotEmpty);
      expect(
        state.products.every(
          (p) =>
              p.audiences.contains(TattooAudience.men) &&
              p.bodyPlacements.contains(BodyPlacement.wrist) &&
              p.categoryIds.contains('test-branches'),
        ),
        isTrue,
      );
      state.clearFilters();
      await Future<void>.delayed(Duration.zero);
      expect(state.audience, isNull);
      expect(state.bodyPlacements, isEmpty);
      expect(state.categoryId, 'test-branches');
      state.dispose();
    },
  );

  test(
    'Supabase queries use array filters and explicit public visibility',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = SupabaseCatalogRepository(client);
      await repo.products(
        const CatalogQuery(
          categoryId: 'category',
          audience: TattooAudience.women,
          bodyPlacements: [BodyPlacement.arm, BodyPlacement.back],
          offset: 24,
        ),
      );
      final uri = requests.last.url;
      expect(uri.path, '/rest/v1/catalog_products');
      expect(uri.queryParameters['public_visible'], 'eq.true');
      expect(uri.queryParameters['public_category_ids'], 'cs.{"category"}');
      expect(uri.queryParameters['audiences'], 'cs.{"women"}');
      expect(uri.queryParameters['body_placements'], 'ov.{"arm","back"}');
      expect(uri.queryParameters['offset'], '24');
      await repo.products(
        const CatalogQuery(admin: true, categoryId: 'category'),
      );
      expect(
        requests.last.url.queryParameters['category_ids'],
        'cs.{"category"}',
      );
      expect(
        requests.last.url.queryParameters,
        isNot(contains('public_visible')),
      );
      await repo.selected(['id']);
      expect(requests.last.url.queryParameters['public_visible'], 'eq.true');
      await client.dispose();
    },
  );

  test('admin sends all product properties in one atomic RPC', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '"saved-id"',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final data = {
      'category_ids': ['one', 'two'],
      'audiences': ['men', 'women'],
      'body_placements': ['arm', 'back'],
    };
    await AdminService(client).save('products', data, id: 'existing-id');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/save_catalog_product');
    expect(jsonDecode(requests.single.body), {
      'p_id': 'existing-id',
      'p_data': data,
    });
    await client.dispose();
  });
}
