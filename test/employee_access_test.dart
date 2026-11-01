import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/services/test_admin_service.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/admin/admin_screen.dart';
import 'package:sunset/ui/admin/order_management.dart';
import 'package:sunset/ui/customer/catalog_screen.dart';

class EmployeeSession extends TestAdminService {
  EmployeeSession(super.catalog);

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<StaffAccess> staffAccess() async =>
      signedIn ? StaffAccess.employee : StaffAccess.none;
}

class TrackedCatalog extends TestCatalogRepository {
  int privateReads = 0;

  @override
  Future<List<Category>> categories({bool admin = false}) {
    if (admin) privateReads++;
    return super.categories(admin: admin);
  }

  @override
  Future<List<Tattoo>> products(CatalogQuery query) {
    if (query.admin) privateReads++;
    return super.products(query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Tajawal',
    )..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))).load();
    await (FontLoader(
      'ElMessiri',
    )..addFont(rootBundle.load('assets/fonts/ElMessiri-700.ttf'))).load();
  });
  testWidgets(
    'employee sees only orders and customer images, including deep links',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final catalog = TrackedCatalog();
      final admin = EmployeeSession(catalog);
      final analytics = NoopAnalytics();
      final selection = SelectionStore(
        await SharedPreferences.getInstance(),
        analytics,
      );
      await admin.signIn('test@gmail.com', '1234');
      final services = AppServices(
        catalog: catalog,
        selection: selection,
        analytics: analytics,
        admin: admin,
      );
      await tester.pumpWidget(G2GApp(services: services));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(CatalogScreen)));
      for (final path in [
        '/admin',
        '/admin/products',
        '/admin/categories',
        '/admin/offers',
        '/admin/team',
        '/admin/settings',
        '/admin/orders',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(find.byType(OrderManagement), findsOneWidget, reason: path);
        expect(
          tester.widget<OrderManagement>(find.byType(OrderManagement)).section,
          'orders',
          reason: path,
        );
        expect(find.byType(ChoiceChip), findsNWidgets(2), reason: path);
        expect(find.widgetWithText(ChoiceChip, 'الطلبات'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'صور للزبون'), findsOneWidget);
        expect(find.text('مساحة التصاميم'), findsNothing);
        expect(catalog.privateReads, 0, reason: path);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'صور للزبون'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CatalogScreen>(find.byType(CatalogScreen)).forCustomer,
        isTrue,
      );
      expect(find.widgetWithText(ChoiceChip, 'الطلبات'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'صور للزبون'), findsOneWidget);
      for (final label in [
        'المنتجات',
        'العروض',
        'التصنيفات',
        'الموظفون',
        'التوصيل',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsNothing);
      }
      expect(catalog.privateReads, 0);
      await tester.tap(find.byTooltip('تسجيل الخروج'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminScreen), findsOneWidget);
      expect(find.text('تسجيل دخول الإدارة'), findsOneWidget);
      expect(find.byType(CatalogScreen), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
      await admin.dispose();
    },
  );
}
