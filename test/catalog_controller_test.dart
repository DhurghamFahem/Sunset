import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/state/catalog_controller.dart';

import 'support/fixtures.dart';

class DelayedCatalog extends MemoryCatalog {
  final requests = <Completer<List<Tattoo>>>[];
  @override
  Future<List<Tattoo>> products(CatalogQuery query) {
    final request = Completer<List<Tattoo>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  test('pagination uses bounded ranges and preserves already loaded data on failure', () async {
    final repo = MemoryCatalog();
    final state = CatalogController(repo);
    await state.initialize();
    expect(state.products.length, 24);
    repo.offline = true;
    await state.loadMore();
    expect(state.failed, true);
    expect(state.products.length, 24);
    repo.offline = false;
    await state.loadMore();
    expect(state.products.length, 30);
    expect(state.hasMore, false);
    expect(repo.queries.map((q) => q.offset), [0, 24, 24]);
    state.dispose();
  });
  test('stale responses never overwrite a newer filter', () async {
    final repo = DelayedCatalog();
    final state = CatalogController(repo);
    final first = state.reload();
    final second = state.reload();
    repo.requests[1].complete([fixture(2)]);
    await second;
    repo.requests[0].complete([fixture(1)]);
    await first;
    expect(state.products.single.id, '2');
    state.dispose();
  });
}
