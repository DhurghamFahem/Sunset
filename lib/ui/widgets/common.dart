import 'package:flutter/material.dart';

import '../../config.dart';
import '../theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => AppConfig.logoAsset.isEmpty
      ? Text(
          AppConfig.brand,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: displayFont,
            fontWeight: FontWeight.w800,
            fontSize: size,
            letterSpacing: -1.8,
            color: forest,
          ),
        )
      : Image.asset(
          AppConfig.logoAsset,
          height: size + 8,
          semanticLabel: AppConfig.brand,
        );
}

class CatalogImage extends StatelessWidget {
  const CatalogImage(
    this.url, {
    super.key,
    this.label = 'تصميم وشم',
    this.padding = 12,
  });
  final String? url;
  final String label;
  final double padding;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFEFE7D6),
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: url == null || url!.isEmpty
          ? const Center(
              child: Icon(Icons.image_outlined, color: muted, size: 28),
            )
          : url!.startsWith('asset:')
          ? Image.asset(
              url!.substring('asset:'.length),
              fit: BoxFit.contain,
              semanticLabel: label,
            )
          : url!.startsWith('data:image/')
          ? Image.memory(
              Uri.parse(url!).data!.contentAsBytes(),
              fit: BoxFit.contain,
              semanticLabel: label,
            )
          : Image.network(
              url!,
              fit: BoxFit.contain,
              semanticLabel: label,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const SkeletonBox(),
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.broken_image_outlined, color: muted),
              ),
            ),
    ),
  );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'جاري التحميل',
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAE1CE),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.title,
    this.detail,
    this.action,
    this.icon = Icons.spa_outlined,
  });
  final String title;
  final String? detail;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 22),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: sage,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: forest),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (detail != null) ...[
            const SizedBox(height: 10),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

void showNotice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ) ??
    false;

/// Shared headings keep the customer journey and management views related.
class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
  final String eyebrow, title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: clay,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(description, style: const TextStyle(color: muted, fontSize: 13)),
      ],
    ),
  );
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class JourneySteps extends StatelessWidget {
  const JourneySteps({super.key, required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0)
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Divider(),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: i <= current ? forest : sage,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: i < current
                  ? const Icon(Icons.check, color: paper, size: 16)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i == current ? paper : muted,
                        fontSize: 12,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              ['اختار', 'راجع', 'شارك'][i],
              style: TextStyle(
                color: i == current ? forest : muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

/// A quiet botanical line drawing; decorative and excluded from semantics.
class BotanicalMark extends StatelessWidget {
  const BotanicalMark({super.key});
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _BotanicalPainter()));
}

class _BotanicalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    final stroke = Paint()
      ..color = const Color(0xFF4F7A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(
      const Rect.fromLTWH(18, 8, 156, 180),
      Paint()..color = const Color(0xFF222222),
    );
    canvas.drawPath(
      Path()
        ..moveTo(70, 205)
        ..cubicTo(95, 156, 125, 92, 107, 12),
      stroke,
    );
    for (var i = 0; i < 6; i++) {
      final y = 45.0 + i * 24;
      final x = 112.0 - i * 2;
      final left = i.isEven;
      final dx = left ? -55.0 : 55.0;
      canvas.drawPath(
        Path()
          ..moveTo(x, y + 17)
          ..quadraticBezierTo(x + dx, y + 12, x + dx, y - 22)
          ..quadraticBezierTo(x + 8, y - 17, x, y + 17),
        stroke,
      );
      canvas.drawLine(Offset(x, y + 17), Offset(x + dx, y - 22), stroke);
    }
    canvas.drawCircle(
      const Offset(161, 31),
      3,
      Paint()..color = const Color(0xFFD96B30),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BotanicalPainter oldDelegate) => false;
}
