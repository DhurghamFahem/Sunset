import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/widgets/common.dart';
import 'package:sunset/ui/widgets/tattoo_card.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Tajawal',
    )..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))).load();
  });
  testWidgets('cards load previews; opening details loads the original', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const original = 'asset:assets/test_catalog/flower.png';
    const thumbnail = 'asset:assets/test_catalog/flower-alternate.png';
    const tattoo = Tattoo(
      id: '1',
      code: '001',
      imageUrl: original,
      thumbnailUrl: thumbnail,
    );
    SharedPreferences.setMockInitialValues({});
    final analytics = NoopAnalytics();
    final selection = SelectionStore(
      await SharedPreferences.getInstance(),
      analytics,
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      G2GApp(
        services: AppServices(
          catalog: MemoryCatalog(products: [tattoo]),
          selection: selection,
          analytics: analytics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cardImage = find.descendant(
      of: find.byType(TattooCard),
      matching: find.byType(CatalogImage),
    );
    expect(tester.widget<CatalogImage>(cardImage).url, thumbnail);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CatalogImage && widget.url == original,
      ),
      findsNothing,
    );

    await tester.tap(cardImage);
    await tester.pumpAndSettle();
    final detailImage = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.byType(CatalogImage),
    );
    expect(tester.widget<CatalogImage>(detailImage).url, original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
