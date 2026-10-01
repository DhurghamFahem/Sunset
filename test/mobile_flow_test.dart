import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/widgets/tattoo_card.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
  });
  for (final width in [360.0, 390.0, 430.0, 1200.0]) {
    testWidgets('browse and select without layout errors at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final analytics = NoopAnalytics();
      final selection = SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      );
      await tester.pumpWidget(
        G2GApp(
          services: AppServices(
            catalog: MemoryCatalog(),
            selection: selection,
            analytics: analytics,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('اختار وشمك 🌿'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();
      final button = find.text('اختيار').first;
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(selection.count, 1);
      expect(find.text('تم الاختيار'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await selection.flush();
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'customer combines audience, body placement, and category filters',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final analytics = NoopAnalytics();
      final selection = SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      );
      await tester.pumpWidget(
        G2GApp(
          services: AppServices(
            catalog: TestCatalogRepository(),
            selection: selection,
            analytics: analytics,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'رجالي'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'المعصم'));
      await tester.pumpAndSettle();
      final size = find.widgetWithText(FilterChip, '3 × 5 سم');
      await Scrollable.ensureVisible(tester.element(size), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(size);
      await tester.pumpAndSettle();
      final tag = find.byKey(const ValueKey('tag-filter-floral'));
      await Scrollable.ensureVisible(tester.element(tag), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(tag).selected, isTrue);
      final search = find.byType(TextField);
      await Scrollable.ensureVisible(tester.element(search), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'زَهْرَة');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final category = find.text('أغصان وأوراق');
      await Scrollable.ensureVisible(tester.element(category), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<TattooCard>(find.byType(TattooCard))
          .toList();
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.product.audiences, contains(TattooAudience.men));
        expect(card.product.bodyPlacements, contains(BodyPlacement.wrist));
        expect(card.product.categoryIds, contains('test-branches'));
        expect(card.product.size, const TattooSize(3, 5));
        expect(card.product.tags, contains('floral'));
        expect(find.text(card.product.displayName), findsWidgets);
        expect(find.text(card.product.code), findsNothing);
      }
      expect(tester.takeException(), isNull);
      final allTags = find.widgetWithText(ChoiceChip, 'كل الوسوم');
      await Scrollable.ensureVisible(tester.element(allTags), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(allTags);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(tag).selected, isFalse);
      expect(tester.widget<FilterChip>(size).selected, isTrue);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
    },
  );
}
