import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/catalog.dart';
import '../models/offer.dart';
import '../services/admin_service.dart';
import 'catalog_repository.dart';
import 'test_catalog_repository.dart';

abstract interface class OfferRepository {
  Future<List<TattooOffer>> list({bool admin = false, int offset = 0});
  Future<void> save({
    required String id,
    required String name,
    required int price,
    required List<String> productIds,
    required bool active,
  });
  Future<void> delete(String id);
}

void validateOffer(String name, int price, List<String> productIds) {
  if (name.trim().isEmpty || name.trim().length > 120) {
    throw CatalogInputException('أدخل اسم العرض (حتى 120 حرف).');
  }
  if (price < 0 || price > 2147483647) {
    throw CatalogInputException('أدخل سعر عرض صحيح بالدينار العراقي.');
  }
  if (productIds.isEmpty ||
      productIds.length > 100 ||
      productIds.toSet().length != productIds.length) {
    throw CatalogInputException('اختار من 1 إلى 100 وشم مختلف للعرض.');
  }
}

class SupabaseOfferRepository implements OfferRepository {
  SupabaseOfferRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<TattooOffer>> list({bool admin = false, int offset = 0}) async {
    var query = client.from('catalog_offers').select();
    if (!admin) query = query.eq('public_visible', true);
    return (await query
            .order('created_at', ascending: false)
            .order('id')
            .range(offset, offset + AppConfig.pageSize - 1))
        .map(TattooOffer.fromJson)
        .toList();
  }

  @override
  Future<void> save({
    required String id,
    required String name,
    required int price,
    required List<String> productIds,
    required bool active,
  }) async {
    validateOffer(name, price, productIds);
    try {
      await client.rpc(
        'save_catalog_offer',
        params: {
          'p_id': id,
          'p_name': name.trim(),
          'p_price': price,
          'p_product_ids': productIds,
          'p_active': active,
        },
      );
    } on PostgrestException {
      throw CatalogInputException(
        'تعذر حفظ العرض. تأكد أن الوشومات موجودة وحاول مرة ثانية.',
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    await client.rpc('delete_catalog_offer', params: {'p_id': id});
  }
}

class MemoryOfferRepository implements OfferRepository {
  MemoryOfferRepository(this.catalog, this.admin);
  final CatalogRepository catalog;
  final CatalogAdmin? admin;
  final _offers = <String, TattooOffer>{};

  Future<void> _requireAdmin() async {
    if (await admin?.isAdmin() != true) {
      throw CatalogInputException('سجّل دخول الإدارة أولاً.');
    }
  }

  Future<Map<String, Tattoo>> _products() async {
    final result = <String, Tattoo>{};
    for (var offset = 0; ; offset += AppConfig.pageSize) {
      final page = await catalog.products(
        CatalogQuery(admin: true, offset: offset),
      );
      result.addEntries(page.map((p) => MapEntry(p.id, p)));
      if (page.length < AppConfig.pageSize) return result;
    }
  }

  @override
  Future<List<TattooOffer>> list({bool admin = false, int offset = 0}) async {
    if (admin) await _requireAdmin();
    if (_offers.isEmpty) return [];
    final products = await _products();
    final visible = (await catalog.selected(products.keys.toList()))
        .map((p) => p.id)
        .toSet();
    final result = _offers.values
        .toList()
        .reversed
        .map((offer) {
          final ids = offer.products.map((p) => p.id).toList();
          return TattooOffer(
            id: offer.id,
            name: offer.name,
            price: offer.price,
            active: offer.active,
            publicVisible: offer.active && ids.every(visible.contains),
            products: List.unmodifiable(
              ids.map((id) => products[id]).whereType<Tattoo>(),
            ),
          );
        })
        .where((offer) => admin || offer.publicVisible);
    return result.skip(offset).take(AppConfig.pageSize).toList();
  }

  void _protectProducts() {
    if (catalog case final TestCatalogRepository demo) {
      demo.offerProductIds
        ..clear()
        ..addAll(_offers.values.expand((o) => o.products.map((p) => p.id)));
    }
  }

  @override
  Future<void> save({
    required String id,
    required String name,
    required int price,
    required List<String> productIds,
    required bool active,
  }) async {
    await _requireAdmin();
    validateOffer(name, price, productIds);
    final products = await _products();
    if (productIds.any((id) => !products.containsKey(id))) {
      throw CatalogInputException('أحد الوشومات لم يعد موجوداً. حدّث القائمة.');
    }
    await _requireAdmin();
    _offers[id] = TattooOffer(
      id: id,
      name: name.trim(),
      price: price,
      products: List.unmodifiable(productIds.map((id) => products[id]!)),
      active: active,
    );
    _protectProducts();
  }

  @override
  Future<void> delete(String id) async {
    await _requireAdmin();
    _offers.remove(id);
    _protectProducts();
  }
}
