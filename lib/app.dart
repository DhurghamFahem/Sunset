import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'ui/theme.dart';
import 'ui/customer/shell.dart';
import 'ui/customer/catalog_screen.dart';
import 'ui/customer/categories_screen.dart';
import 'ui/customer/detail_screen.dart';
import 'ui/customer/selection_screen.dart';
import 'ui/customer/orders_screen.dart';
import 'ui/admin/admin_screen.dart';
import 'ui/widgets/common.dart';

class G2GApp extends StatefulWidget {
  const G2GApp({super.key, required this.services});
  final AppServices services;
  @override
  State<G2GApp> createState() => _G2GAppState();
}

class _G2GAppState extends State<G2GApp> {
  @override
  void initState() {
    super.initState();
    GoRouter.optionURLReflectsImperativeAPIs = true;
  }

  late final router = GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            CustomerShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CatalogScreen()),
          GoRoute(
            path: '/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/category/:id',
            builder: (_, state) => CatalogScreen(
              key: ValueKey(state.pathParameters['id']),
              categoryId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/tattoo/:id',
            builder: (_, state) =>
                DetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/selections',
            builder: (_, _) => const SelectionScreen(),
          ),
        ],
      ),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
      GoRoute(path: '/orders', builder: (_, _) => const CustomerOrdersScreen()),
      GoRoute(
        path: '/admin/orders',
        builder: (_, _) => const AdminScreen(section: 'orders'),
      ),
      GoRoute(
        path: '/admin/team',
        builder: (_, _) => const AdminScreen(section: 'team'),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => const AdminScreen(section: 'settings'),
      ),
      GoRoute(
        path: '/admin/categories',
        builder: (_, _) => const AdminScreen(section: 'categories'),
      ),
      GoRoute(
        path: '/admin/products',
        builder: (_, _) => const AdminScreen(section: 'products'),
      ),
    ],
    errorBuilder: (context, _) => Scaffold(
      body: MessagePanel(
        title: 'الصفحة مو موجودة',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('تصفح الوشومات'),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'G2G | وشومات عشبية',
      theme: catalogTheme(),
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    ),
  );
}
