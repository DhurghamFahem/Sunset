import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../config.dart';
import '../models/catalog.dart';
import '../repositories/catalog_repository.dart';

class CatalogController extends ChangeNotifier {
  CatalogController(this.repository, {this.categoryId});
  final CatalogRepository repository;
  String? categoryId;
  TattooAudience? audience;
  List<BodyPlacement> bodyPlacements = [];
  List<TattooSize> sizes = [], availableSizes = [];
  List<String> tags = [], availableTags = [];
  List<Tattoo> products = [];
  List<Category> categories = [];
  String search = '';
  CatalogSort sort = CatalogSort.curated;
  bool loading = false, hasMore = true, failed = false;
  int _generation = 0;
  int _offset = 0;
  bool _disposed = false;
  Timer? _debounce;
  Future<void> initialize() async {
    final tagOptions = repository
        .availableTags()
        .then((value) {
          if (!_disposed) {
            availableTags = value;
            notifyListeners();
          }
        })
        .catchError((Object _) {});
    final sizeOptions = repository
        .availableSizes()
        .then((value) {
          if (!_disposed) {
            availableSizes = value;
            notifyListeners();
          }
        })
        .catchError((Object _) {});
    final cat = repository
        .categories()
        .then((value) {
          if (!_disposed) {
            categories = value;
            notifyListeners();
          }
        })
        .catchError((Object _) {});
    await reload();
    await cat;
    await sizeOptions;
    await tagOptions;
  }

  void setSearch(String value) {
    _debounce?.cancel();
    // Invalidate any in-flight request immediately, including during debounce.
    _generation++;
    search = value;
    _debounce = Timer(const Duration(milliseconds: 300), reload);
  }

  void setSort(CatalogSort value) {
    sort = value;
    reload();
  }

  void setCategory(String? value) {
    categoryId = value;
    reload();
  }

  void setAudience(TattooAudience? value) {
    audience = value;
    reload();
  }

  void toggleBodyPlacement(BodyPlacement value) {
    bodyPlacements = bodyPlacements.contains(value)
        ? bodyPlacements.where((item) => item != value).toList()
        : [...bodyPlacements, value];
    reload();
  }

  void clearFilters() {
    audience = null;
    bodyPlacements = [];
    sizes = [];
    tags = [];
    reload();
  }

  void toggleSize(TattooSize value) {
    sizes = sizes.contains(value)
        ? sizes.where((item) => item != value).toList()
        : [...sizes, value];
    reload();
  }

  void toggleTag(String value) {
    tags = tags.contains(value)
        ? tags.where((tag) => tag != value).toList()
        : [...tags, value];
    reload();
  }

  void clearTags() {
    tags = [];
    reload();
  }

  Future<void> reload() async {
    _debounce?.cancel();
    _generation++;
    _offset = 0;
    products = [];
    loading = false;
    hasMore = true;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || _disposed) return;
    final generation = _generation;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final page = await repository.products(
        CatalogQuery(
          categoryId: categoryId,
          audience: audience,
          bodyPlacements: List.unmodifiable(bodyPlacements),
          sizes: List.unmodifiable(sizes),
          tags: List.unmodifiable(tags),
          search: search,
          sort: sort,
          offset: _offset,
        ),
      );
      if (_disposed || generation != _generation) return;
      final ids = products.map((p) => p.id).toSet();
      products.addAll(page.where((p) => ids.add(p.id)));
      _offset += page.length;
      hasMore = page.length == AppConfig.pageSize;
    } catch (_) {
      if (generation == _generation) failed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
