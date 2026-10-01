import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/catalog.dart';
import '../widgets/common.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Future<List<Category>>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= AppScope.of(context).catalog.categories();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MessagePanel(
              title: 'تعذر تحميل التصنيفات.',
              action: OutlinedButton(
                onPressed: () => setState(() {
                  future = AppScope.of(context).catalog.categories();
                }),
                child: const Text('إعادة المحاولة'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(20),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: List.generate(6, (_) => const SkeletonBox()),
            );
          }
          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return const MessagePanel(title: 'قريباً نضيف موديلات جديدة 🌿');
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'التصنيفات',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.sizeOf(context).width < 600
                        ? 2
                        : 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: .9,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final c = categories[i];
                    return InkWell(
                      onTap: () => context.push('/category/${c.id}'),
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: double.infinity,
                                child: CatalogImage(c.imageUrl, label: c.name),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(c.name, textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    );
                  }, childCount: categories.length),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
