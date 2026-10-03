import 'package:flutter/widgets.dart';

import 'repositories/catalog_repository.dart';
import 'services/admin_service.dart';
import 'services/analytics.dart';
import 'state/selection_store.dart';

class AppServices {
  AppServices({
    required this.catalog,
    required this.selection,
    required this.analytics,
    this.admin,
  });
  final CatalogRepository catalog;
  final SelectionStore selection;
  final Analytics analytics;
  final CatalogAdmin? admin;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;
  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;
  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
