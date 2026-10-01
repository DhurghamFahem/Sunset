import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/catalog.dart';
import '../models/catalog_search.dart';

abstract class CatalogRepository {
  Future<List<TattooSize>> availableSizes();
  Future<List<Category>> categories({bool admin = false});
  Future<List<Tattoo>> products(CatalogQuery query);
  Future<Tattoo?> product(String id);
  Future<List<Tattoo>> selected(List<String> ids);
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<TattooSize>> availableSizes() async {
    final rows = await client.rpc('catalog_available_sizes');
    return (rows as List)
        .map(
          (row) => TattooSize(
            (row['width_cm'] as num).toDouble(),
            (row['height_cm'] as num).toDouble(),
          ),
        )
        .toList();
  }

  @override
  Future<List<Category>> categories({bool admin = false}) async {
    var q = client.from('categories').select();
    if (!admin) q = q.eq('active', true);
    return (await q.order('sort_order').order('id'))
        .map(Category.fromJson)
        .toList();
  }

  @override
  Future<List<Tattoo>> products(CatalogQuery query) async {
    // The view aggregates memberships before pagination, so a tattoo appears
    // once even when several categories match. Explicit visibility also applies
    // when an administrator is browsing the customer catalog.
    var q = client.from('catalog_products').select();
    if (!query.admin) q = q.eq('public_visible', true);
    if (query.categoryId != null) {
      q = q.contains(query.admin ? 'category_ids' : 'public_category_ids', [
        query.categoryId!,
      ]);
    }
    if (query.audience != null) {
      q = q.contains('audiences', [query.audience!.name]);
    }
    if (query.bodyPlacements.isNotEmpty) {
      q = q.overlaps(
        'body_placements',
        query.bodyPlacements.map((value) => value.name).toList(),
      );
    }
    if (query.sizes.isNotEmpty) {
      q = q.or(
        query.sizes
            .map(
              (size) =>
                  'and(width_cm.eq.${size.width},height_cm.eq.${size.height})',
            )
            .join(','),
      );
    }
    for (final term in catalogSearchTerms(query.search)) {
      q = q.ilike(query.admin ? 'admin_search_text' : 'search_text', '%$term%');
    }
    if (query.sort == CatalogSort.featured) q = q.eq('featured', true);
    final String order;
    switch (query.sort) {
      case CatalogSort.newest:
        order = 'created_at';
      case CatalogSort.price:
        order = 'price';
      case CatalogSort.size:
        order = 'area_cm2';
      default:
        order = 'sort_order';
    }
    return (await q
            .order(
              order,
              ascending: query.sort != CatalogSort.newest,
              nullsFirst: false,
            )
            .order('id')
            .range(query.offset, query.offset + AppConfig.pageSize - 1))
        .map(Tattoo.fromJson)
        .toList();
  }

  @override
  Future<Tattoo?> product(String id) async {
    final j = await client
        .from('catalog_products')
        .select()
        .eq('id', id)
        .eq('public_visible', true)
        .maybeSingle();
    return j == null ? null : Tattoo.fromJson(j);
  }

  @override
  Future<List<Tattoo>> selected(List<String> ids) async {
    final result = <Tattoo>[];
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.skip(i).take(50).toList();
      result.addAll(
        (await client
                .from('catalog_products')
                .select()
                .inFilter('id', chunk)
                .eq('public_visible', true))
            .map(Tattoo.fromJson),
      );
    }
    return result;
  }
}

class UnconfiguredCatalogRepository implements CatalogRepository {
  Never _missing() => throw StateError('Catalog is not configured');
  @override
  Future<List<TattooSize>> availableSizes() async => _missing();
  @override
  Future<List<Category>> categories({bool admin = false}) async => _missing();
  @override
  Future<List<Tattoo>> products(CatalogQuery query) async => _missing();
  @override
  Future<Tattoo?> product(String id) async => _missing();
  @override
  Future<List<Tattoo>> selected(List<String> ids) async => _missing();
}
