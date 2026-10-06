import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/catalog.dart';
import '../repositories/catalog_repository.dart';
import 'catalog_image_storage.dart';
import 'catalog_image_storage_stub.dart'
    if (dart.library.js_interop) 'catalog_image_storage_web.dart';
import 'selection_renderer.dart';

class CatalogImageExport {
  const CatalogImageExport(
    this.pages, {
    required this.reused,
    required this.saved,
  });
  final List<Uint8List> pages;
  final bool reused, saved;
}

class CatalogImageExporter {
  CatalogImageExporter({
    CatalogImageStorage? storage,
    SelectionRenderer? renderer,
  }) : storage = storage ?? DeviceCatalogImageStorage(),
       renderer = renderer ?? SelectionRenderer();
  final CatalogImageStorage storage;
  final SelectionRenderer renderer;

  Future<CatalogImageExport> generate(
    CatalogRepository catalog,
    CatalogQuery query, {
    ValueChanged<double>? onProgress,
  }) async {
    // Always refresh ALL matching records, including pages not yet browsed.
    // No order repository or customer selection state is involved.
    final products = <Tattoo>[];
    final ids = <String>{};
    for (var offset = 0; ; offset += AppConfig.pageSize) {
      final page = await catalog.products(
        CatalogQuery(
          categoryId: query.categoryId,
          audience: query.audience,
          bodyPlacements: query.bodyPlacements,
          sizes: query.sizes,
          tags: query.tags,
          search: query.search,
          sort: query.sort,
          offset: offset,
        ),
      );
      products.addAll(page.where((p) => ids.add(p.id)));
      if (page.length < AppConfig.pageSize) break;
    }
    if (products.isEmpty) throw StateError('No matching tattoos');
    // Fingerprint every rendered field and its order, plus filters and branding.
    // Bump the layout version whenever rendering changes.
    final key = jsonEncode({
      'layout': 1,
      'test': AppConfig.useTestData,
      'backend': AppConfig.supabaseUrl,
      'brand': AppConfig.brand,
      'logo': AppConfig.logoAsset,
      'instagram': AppConfig.instagramUsername,
      'pageSize': AppConfig.designsPerImage,
      'category': query.categoryId,
      'audience': query.audience?.name,
      'placements': query.bodyPlacements.map((p) => p.name).toList()..sort(),
      'sizes': query.sizes.map((s) => s.label).toList()..sort(),
      'tags': query.tags.toList()..sort(),
      'search': query.search.trim(),
      'sort': query.sort.name,
      'products': products
          .map(
            (p) => [
              p.id,
              p.code,
              p.displayName,
              p.imageUrl,
              p.width,
              p.height,
              p.price,
            ],
          )
          .toList(),
    });
    try {
      final cached = await storage.read(key);
      if (cached != null &&
          cached.length == SelectionRenderer.pages(products).length &&
          cached.every(
            (page) =>
                page.length > 8 &&
                listEquals(page.take(8).toList(), [
                  137,
                  80,
                  78,
                  71,
                  13,
                  10,
                  26,
                  10,
                ]),
          )) {
        onProgress?.call(1);
        return CatalogImageExport(cached, reused: true, saved: true);
      }
    } catch (_) {
      /* Unavailable/evicted storage is a cache miss. */
    }
    final pages = await renderer.render(
      products,
      showPrices: true,
      onProgress: onProgress,
    );
    var saved = false;
    try {
      saved = await storage.write(key, pages);
    } catch (_) {
      /* Still allow downloading. */
    }
    return CatalogImageExport(pages, reused: false, saved: saved);
  }
}
