import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final selection = AppScope.of(context).selection;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final index = path.startsWith('/selection')
        ? 2
        : path.startsWith('/categor')
        ? 1
        : 0;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          titleSpacing: 22,
          title: Row(
            children: [
              InkWell(onTap: () => context.go('/'), child: const Brand()),
              const SizedBox(width: 16),
              if (wide)
                const Text(
                  'وشومات عشبية • لمسة تشبهك',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
            ],
          ),
          actions: wide
              ? [
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('الرئيسية'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/categories'),
                    child: const Text('التصنيفات'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/selections'),
                      icon: const Icon(Icons.favorite_border, size: 19),
                      label: Text('اختياراتي • ${selection.count}'),
                    ),
                  ),
                ]
              : [
                  TextButton.icon(
                    onPressed: () => context.go('/selections'),
                    icon: const Icon(Icons.favorite_border, size: 21),
                    label: Text('${selection.count}'),
                  ),
                  const SizedBox(width: 8),
                ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Color(0xFFE2E5DC)),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (selection.persistenceWarning)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFEDCB),
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    'المتصفح ما قدر يحفظ اختياراتك. خلي الصفحة مفتوحة لحد ما تحفظ الصور.',
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selection.count > 0 && index != 2)
              SafeArea(
                top: false,
                bottom: wide,
                child: Container(
                  color: ivory,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.go('/selections'),
                        icon: const Icon(Icons.favorite_outline),
                        label: Text('اختياراتي • ${selection.count}'),
                      ),
                    ),
                  ),
                ),
              ),
            if (!wide)
              NavigationBar(
                height: 70,
                selectedIndex: index,
                onDestinationSelected: (i) =>
                    context.go(['/', '/categories', '/selections'][i]),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'الرئيسية',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'التصنيفات',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: selection.count > 0,
                      label: Text('${selection.count}'),
                      child: const Icon(Icons.favorite_border),
                    ),
                    label: 'اختياراتي',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
