import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rapid selection updates survive a refresh and removing one leaves four',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final selection = SelectionStore(prefs, NoopAnalytics());
      for (var i = 1; i <= 5; i++) {
        selection.toggle(fixture(i));
      }
      selection.toggle(fixture(3));
      await selection.flush();
      final restored = SelectionStore(prefs, NoopAnalytics());
      expect(restored.count, 4);
      expect(restored.items.map((p) => p.id), ['1', '2', '4', '5']);
      restored.clear();
      await restored.flush();
      expect(SelectionStore(prefs, NoopAnalytics()).count, 0);
    },
  );
  test('reconciliation updates prices and drops unavailable designs, offline preserves data', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SelectionStore(
      await SharedPreferences.getInstance(),
      NoopAnalytics(),
    );
    store.toggle(fixture(1));
    store.toggle(fixture(2));
    final repo = MemoryCatalog(products: [fixture(1, price: 7000)]);
    expect(await store.reconcile(repo), 1);
    expect(store.items.single.price, 7000);
    repo.offline = true;
    await expectLater(store.reconcile(repo), throwsStateError);
    expect(store.count, 1);
    await store.flush();
  });
  test(
    'null price and dimensions are omitted, Iraqi price formatted correctly',
    () {
      expect(fixture(1, price: null).formattedPrice, '');
      expect(fixture(1).formattedPrice, '5,000 د.ع');
      expect(fixture(1).dimensions, '28 × 7 سم');
    },
  );
}
