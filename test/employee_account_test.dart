import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunset/app_scope.dart';
import 'package:sunset/models/order.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/order_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/services/analytics.dart';
import 'package:sunset/services/test_admin_service.dart';
import 'package:sunset/state/selection_store.dart';
import 'package:sunset/ui/admin/order_management.dart';
import 'package:sunset/ui/order_screen.dart';

void main() {
  testWidgets('create employee login, sign in and preserve order creator', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final catalog = TestCatalogRepository();
    final admin = TestAdminService(catalog);
    await admin.signIn('test@gmail.com', '1234');
    final analytics = NoopAnalytics();
    final selection = SelectionStore(
      await SharedPreferences.getInstance(),
      analytics,
    );
    final app = AppServices(
      catalog: catalog,
      selection: selection,
      analytics: analytics,
      admin: admin,
    );
    Widget wrap(Widget child) => AppScope(
      services: app,
      child: MaterialApp(home: child),
    );
    await tester.pumpWidget(
      wrap(const Scaffold(body: OrderManagement(section: 'team'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة موظف'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(await app.orders.employees(), isEmpty);
    await fill('الاسم', 'موظف تجريبي');
    await fill('رقم الهاتف', '07701234567');
    await fill('البريد الإلكتروني للدخول', 'worker@example.com');
    await fill('كلمة المرور', 'Employee123!');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(TextFormField, 'كلمة المرور'),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    final employee = (await app.orders.employees()).single;
    expect(employee.email, 'worker@example.com');
    await admin.signOut();
    await expectLater(
      admin.signIn(employee.email, 'wrong'),
      throwsA(isA<CatalogInputException>()),
    );
    await admin.signIn(employee.email, 'Employee123!');
    expect(await admin.staffAccess(), StaffAccess.employee);
    expect(await admin.isAdmin(), isFalse);
    await expectLater(
      app.orders.saveEmployee(
        name: 'Forbidden',
        phone: '07701234567',
        email: 'forbidden@example.com',
        password: 'Employee123!',
      ),
      throwsA(isA<CatalogInputException>()),
    );
    final products = await catalog.products(const CatalogQuery());
    final token = newOrderToken();
    var order = await app.orders.createManual(token, {products.first.id: 1});
    expect(order.createdBy, employee.userId);
    expect(order.createdByName, employee.name);
    await admin.signOut();
    await admin.signIn('test@gmail.com', '1234');
    expect(
      (await app.orders.createManual(token, {products.first.id: 1})).createdBy,
      employee.userId,
    );
    order = await app.orders.save(order, {'customer_name': 'Customer'});
    expect(order.createdBy, employee.userId);
    for (final changes in [
      {'employee_id': null},
      {'created_by': 'other'},
      {'created_by_name': 'other'},
    ]) {
      await expectLater(
        app.orders.save(order, changes),
        throwsA(isA<OrderException>()),
      );
    }
    final stats = (await app.orders.performance()).singleWhere(
      (row) => row['name'] == employee.name,
    );
    expect(stats['orders'], 1);
    await tester.pumpWidget(wrap(OrderScreen(order: order)));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('أُنشئ بواسطة: ${employee.name}'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    selection.dispose();
    await admin.dispose();
  });
}
