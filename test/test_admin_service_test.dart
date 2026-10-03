import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app.dart';
import 'package:sunset/main.dart' as entry;
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/services/test_admin_service.dart';
import 'package:sunset/ui/customer/catalog_screen.dart';

void main() {
  test('credentials, logout, and writes require a demo session', () async {
    final catalog = TestCatalogRepository();
    final admin = TestAdminService(catalog);
    addTearDown(admin.dispose);
    expect(await admin.isAdmin(), isFalse);
    await expectLater(
      admin.signIn('test@gmail.com', 'wrong'),
      throwsA(isA<CatalogInputException>()),
    );
    await expectLater(
      admin.signIn('other@gmail.com', '1234'),
      throwsA(isA<CatalogInputException>()),
    );
    await expectLater(
      admin.save('categories', {'name_ar': 'Demo'}),
      throwsA(isA<CatalogInputException>()),
    );
    await admin.signIn(' test@gmail.com ', '1234');
    expect(await admin.isAdmin(), isTrue);
    await admin.signOut();
    expect(await admin.isAdmin(), isFalse);
    await expectLater(
      admin.deleteCategory('test-flowers'),
      throwsA(isA<CatalogInputException>()),
    );
  });

  test(
    'demo edits affect the shared catalog and reset with a new catalog',
    () async {
      final catalog = TestCatalogRepository();
      final admin = TestAdminService(catalog);
      addTearDown(admin.dispose);
      await admin.signIn('test@gmail.com', '1234');
      final original = (await catalog.product('test-tattoo-001'))!;
      await admin.save('products', {
        ...original.toJson(),
        'name_ar': 'Changed',
        'active': false,
      }, id: original.id);
      expect(await catalog.product(original.id), isNull);
      final hidden = await catalog.products(
        const CatalogQuery(admin: true, search: 'Changed'),
      );
      expect(hidden.single.id, original.id);
      expect(
        (await TestCatalogRepository().product(original.id))!.name,
        original.name,
      );
      await expectLater(
        admin.deleteCategory('test-flowers'),
        throwsA(isA<CatalogInputException>()),
      );
      await expectLater(
        admin.save('products', original.toJson()),
        throwsA(isA<CatalogInputException>()),
      );
      await admin.save('categories', {'name_ar': 'Demo'});
      final created = (await catalog.categories()).singleWhere(
        (c) => c.name == 'Demo',
      );
      await admin.deleteCategory(created.id);
      expect(
        (await catalog.categories()).any((c) => c.id == created.id),
        isFalse,
      );
    },
  );

  testWidgets('test startup supports admin login, editing, and logout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await entry.main();
    await tester.pumpAndSettle();
    final app = tester.widget<G2GApp>(find.byType(G2GApp));
    final router = GoRouter.of(tester.element(find.byType(CatalogScreen)));
    router.go('/admin');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'test@gmail.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'دخول'));
    await tester.pumpAndSettle();
    expect(
      find.text('تعذر تسجيل الدخول. تأكد من الحساب وكلمة المرور.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'دخول'));
    await tester.pumpAndSettle();
    expect(find.text('مساحة التصاميم'), findsOneWidget);
    router.go('/admin/categories');
    await tester.pumpAndSettle();
    expect(find.text('مجموعاتك'), findsOneWidget);
    await tester.tap(find.text('ورود'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Test flowers');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('Test flowers'), findsOneWidget);
    await tester.tap(find.byTooltip('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل دخول الإدارة'), findsOneWidget);
    expect(find.text('مجموعاتك'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.services.selection.dispose();
    await (app.services.admin as TestAdminService).dispose();
  });
}
