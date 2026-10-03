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
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(20),
          ),
          // Painted above the content so the image can't cover the border.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? forest : line,
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CatalogImage(
                          product.thumbnail,
                          label: product.displayName,
                          padding: 22,
                        ),
                        if (product.isNew || product.featured)
                          PositionedDirectional(
                            top: 10,
                            start: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: paper.withValues(alpha: .94),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                product.isNew ? 'جديد' : 'مميز',
                                style: const TextStyle(
                                  color: forest,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        PositionedDirectional(
                          bottom: 10,
                          end: 10,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: paper.withValues(alpha: .9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.north_west,
                              size: 14,
                              color: forest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Text(
                  product.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
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
                    fontSize: 11,
                    color: muted,
                    height: 1.8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: selected ? forest : sage,
                    foregroundColor: selected ? paper : forest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => selection.toggle(product),
                  icon: Icon(selected ? Icons.check : Icons.add, size: 17),
                  label: Text(
                    selected ? 'تم الاختيار' : 'اختيار',
                    style: const TextStyle(fontSize: 12),
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
