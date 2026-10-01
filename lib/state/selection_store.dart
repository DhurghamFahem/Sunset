import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../repositories/catalog_repository.dart';
import '../services/analytics.dart';

class SelectionStore extends ChangeNotifier {
  SelectionStore(
    this.preferences,
    this.analytics, {
    String storageKey = 'g2g.selections.v1',
  }) : _key = storageKey {
    try {
      final rows = jsonDecode(preferences.getString(_key) ?? '[]') as List;
      for (final j in rows) {
        final p = Tattoo.fromJson(Map<String, dynamic>.from(j as Map));
        _items[p.id] = p;
      }
    } catch (_) {
      persistenceWarning = true;
    }
  }
  final String _key;
  final SharedPreferences preferences;
  final Analytics analytics;
  final Map<String, Tattoo> _items = {};
  Future<void> _writes = Future.value();
  bool persistenceWarning = false;
  List<Tattoo> get items => List.unmodifiable(_items.values);
  int get count => _items.length;
  bool contains(String id) => _items.containsKey(id);
  void toggle(Tattoo p) {
    final removed = _items.remove(p.id) != null;
    if (!removed) _items[p.id] = p;
    analytics.event(
      removed ? 'tattoo_removed' : 'tattoo_selected',
      catalogId: p.id,
    );
    _persist();
  }

  void clear() {
    _items.clear();
    _persist();
  }

  void _persist() {
    final data = jsonEncode(items.map((p) => p.toJson()).toList());
    notifyListeners();
    // Serialize writes so rapid taps cannot persist an older selection last.
    _writes = _writes.then((_) async {
      try {
        persistenceWarning = !await preferences.setString(_key, data);
      } catch (_) {
        persistenceWarning = true;
      }
      notifyListeners();
    });
  }

  Future<void> flush() => _writes;

  /// A successful server check drops unavailable designs, but a network failure
  /// leaves the local selection intact. Revalidate before generating images.
  Future<int> reconcile(CatalogRepository repository) async {
    final before = count;
    final fresh = await repository.selected(_items.keys.toList());
    final byId = {for (final p in fresh) p.id: p};
    for (final id in _items.keys.toList()) {
      if (byId.containsKey(id)) {
        _items[id] = byId[id]!;
      } else {
        _items.remove(id);
      }
    }
    _persist();
    return before - count;
  }
}
