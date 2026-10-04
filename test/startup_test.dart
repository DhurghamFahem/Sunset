import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/config.dart';
import 'package:sunset/main.dart' as entry;
import 'package:sunset/repositories/catalog_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/test_admin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Tajawal',
    )..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))).load();
  });
  testWidgets('startup chooses the configured catalog mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Invoke with invalid Supabase credentials in test mode to prove startup
    // never attempts to initialize the backend, even when it is configured.
    await entry.main();
    await tester.pumpAndSettle();
    final app = tester.widget<G2GApp>(find.byType(G2GApp));
    if (AppConfig.useTestData) {
      expect(app.services.catalog, isA<TestCatalogRepository>());
      expect(app.services.admin, isA<TestAdminService>());
      expect(find.text('رجالي'), findsOneWidget);
      expect(find.text('نسائي'), findsOneWidget);
    } else if (!AppConfig.configured) {
      expect(app.services.catalog, isA<UnconfiguredCatalogRepository>());
      expect(app.services.admin, isNull);
    } else {
      expect(app.services.catalog, isA<SupabaseCatalogRepository>());
      expect(app.services.admin, isNotNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.services.selection.dispose();
  });
}
