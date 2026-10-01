import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/catalog.dart';

abstract class CatalogRepository {
  Future<List<Category>> categories({bool admin = false});
  Future<List<Tattoo>> products(CatalogQuery query);
  Future<Tattoo?> product(String id);
  Future<List<Tattoo>> selected(List<String> ids);
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this.client);
  final SupabaseClient client;
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
    final search = query.search
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
        .trim();
    if (search.isNotEmpty) {
      q = q.or('code.ilike.%$search%,name_ar.ilike.%$search%');
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
  Future<List<Category>> categories({bool admin = false}) async => _missing();
  @override
  Future<List<Tattoo>> products(CatalogQuery query) async => _missing();
  @override
  Future<Tattoo?> product(String id) async => _missing();
  @override
  Future<List<Tattoo>> selected(List<String> ids) async => _missing();
}
