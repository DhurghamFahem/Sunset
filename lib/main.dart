import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_scope.dart';
import 'config.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/test_catalog_repository.dart';
import 'services/admin_service.dart';
import 'services/test_admin_service.dart';
import 'services/analytics.dart';
import 'state/selection_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  SupabaseClient? client;
  if (!AppConfig.useTestData && AppConfig.configured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    client = Supabase.instance.client;
  }
  final analytics = NoopAnalytics();
  final preferences = await SharedPreferences.getInstance();
  final testCatalog = AppConfig.useTestData ? TestCatalogRepository() : null;
  runApp(
    G2GApp(
      services: AppServices(
        catalog:
            testCatalog ??
            (client == null
                ? UnconfiguredCatalogRepository()
                : SupabaseCatalogRepository(client)),
        admin: testCatalog != null
            ? TestAdminService(testCatalog)
            : client == null
            ? null
            : AdminService(client),
        analytics: analytics,
        selection: SelectionStore(
          preferences,
          analytics,
          storageKey: AppConfig.useTestData
              ? 'g2g.test-selections.v1'
              : 'g2g.selections.v1',
        ),
      ),
    ),
  );
}
