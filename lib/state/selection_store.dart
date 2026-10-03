import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/order_repository.dart';
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
        _quantities[p.id] = ((j['quantity'] as int?) ?? 1).clamp(1, 99);
      }
    } catch (_) {
      persistenceWarning = true;
    }
  }
  final String _key;
  final SharedPreferences preferences;
  final Analytics analytics;
  final Map<String, Tattoo> _items = {};
  final Map<String, int> _quantities = {};
  int quantity(String id) => _quantities[id] ?? 1;
  Map<String, int> get quantities => {
    for (final id in _items.keys) id: quantity(id),
  };
  int get pieces => quantities.values.fold(0, (a, b) => a + b);
  void setQuantity(String id, int value) {
    if (!_items.containsKey(id) || value < 1 || value > 99) return;
    _quantities[id] = value;
    _persist();
  }

  /// Persist the request before networking so failures/reloads reuse one order.
  Future<String> exportToken() async {
    final fingerprint = jsonEncode(quantities);
    final saved = jsonDecode(
      preferences.getString('$_key.export-request') ?? '{}',
    ) as Map;
    if (saved['items'] == fingerprint && saved['token'] is String) {
      return saved['token'] as String;
    }
    final next = newOrderToken();
    if (!await preferences.setString(
      '$_key.export-request',
      jsonEncode({'items': fingerprint, 'token': next}),
    )) {
      throw StateError('Cannot save order request');
    }
    return next;
  }

  Future<void> rememberOrder(String id, String token) async {
    final history = preferences.getStringList('$_key.orders') ?? [];
    final entry = '$id|$token';
    if (!history.contains(entry)) history.insert(0, entry);
    if (!await preferences.setStringList('$_key.orders', history)) {
      throw StateError('Cannot save order access');
    }
  }

  List<({String id, String token})> get savedOrders =>
      (preferences.getStringList('$_key.orders') ?? [])
          .where((v) => v.split('|').length == 2)
          .map((v) => (id: v.split('|')[0], token: v.split('|')[1]))
          .toList();
  Future<void> finishExport() async {
    await preferences.remove('$_key.export-request');
  }

  Future<void> _writes = Future.value();
  bool persistenceWarning = false;
  List<Tattoo> get items => List.unmodifiable(_items.values);
  int get count => _items.length;
  bool contains(String id) => _items.containsKey(id);
  void toggle(Tattoo p) {
    final removed = _items.remove(p.id) != null;
    if (!removed) _items[p.id] = p;
    if (removed) _quantities.remove(p.id);
    analytics.event(
      removed ? 'tattoo_removed' : 'tattoo_selected',
      catalogId: p.id,
    );
    _persist();
  }

  void clear() {
    _items.clear();
    _quantities.clear();
    _persist();
  }

  void _persist() {
    final data = jsonEncode(
      items.map((p) => {...p.toJson(), 'quantity': quantity(p.id)}).toList(),
    );
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
