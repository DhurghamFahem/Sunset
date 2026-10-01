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
            fontFamily: 'serif',
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
    color: const Color(0xFFF3F2EC),
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
        color: const Color(0xFFEAECE5),
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
          Icon(icon, size: 40, color: forest),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
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
