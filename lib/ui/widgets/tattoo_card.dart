import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/catalog.dart';
import '../theme.dart';
import 'common.dart';

class TattooCard extends StatelessWidget {
  const TattooCard(this.product, {super.key});
  final Tattoo product;
  @override
  Widget build(BuildContext context) {
    final selection = AppScope.of(context).selection;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final selected = selection.contains(product.id);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? forest : const Color(0xFFE4E6DF),
              width: selected ? 1.7 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'عرض ${product.displayName}',
                  child: InkWell(
                    onTap: () => context.push('/tattoo/${product.id}'),
                    child: CatalogImage(
                      product.thumbnail,
                      label: product.displayName,
                      padding: 18,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (product.isNew)
                      const Text(
                        'جديد',
                        style: TextStyle(color: forest, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  [
                    product.dimensions,
                    product.formattedPrice,
                  ].where((s) => s.isNotEmpty).join('  •  '),
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    height: 1.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 6),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: selected ? const Color(0xFFEAF0E7) : null,
                  ),
                  onPressed: () => selection.toggle(product),
                  icon: Icon(
                    selected ? Icons.check : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text(
                    selected ? 'تم الاختيار' : 'اختيار',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
