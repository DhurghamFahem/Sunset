import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../widgets/common.dart';

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final selection = AppScope.of(context).selection;
    final reviewing = path.startsWith('/selection');
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 58,
          titleSpacing: 16,
          leading: path == '/'
              ? null
              : IconButton(
                  tooltip: 'رجوع للتصفح',
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                ),
          title: InkWell(
            onTap: () => context.go('/'),
            child: const Brand(size: 28),
          ),
          actions: [
            if (!reviewing)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: TextButton.icon(
                  onPressed: () => context.push('/selections'),
                  icon: Badge(
                    isLabelVisible: selection.count > 0,
                    label: Text('${selection.count}'),
                    child: const Icon(Icons.favorite_border, size: 21),
                  ),
                  label: const Text('اختياراتي'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (selection.persistenceWarning)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFEDCB),
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    'خلي الصفحة مفتوحة لحد ما تحفظ صور اختياراتك.',
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: selection.count == 0 || reviewing
            ? null
            : Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E5DC))),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('review-selections'),
                            onPressed: () => context.push('/selections'),
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            label: Text('شوف اختياراتي (${selection.count})'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
