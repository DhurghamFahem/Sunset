import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../services/share/share_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.pages});
  final List<Uint8List> pages;
  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final service = ShareService();
  bool canShare = false, sharing = false;
  @override
  void initState() {
    super.initState();
    canShare = service.prepare(widget.pages);
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Future<void> share() async {
    // Must be called before any asynchronous work to retain user activation.
    final result = service.share();
    setState(() {
      sharing = true;
    });
    final status = await result;
    if (!mounted) return;
    setState(() {
      sharing = false;
    });
    if (status == 'failed' || status == 'unsupported') {
      setState(() {
        canShare = false;
      });
      showNotice(
        context,
        'المشاركة مو متاحة بهالمتصفح. احفظ الصور وافتح Instagram.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Brand()),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              'اختياراتك جاهزة 🌿',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'دز الصور إلنا على Instagram ونكمل طلبك هناك.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < widget.pages.length; i++) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  widget.pages[i],
                  semanticLabel: 'اختياراتي ${i + 1} من ${widget.pages.length}',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => service.download(i),
                icon: const Icon(Icons.download_outlined),
                label: Text(
                  widget.pages.length == 1
                      ? 'حفظ الصور'
                      : 'حفظ الصورة ${i + 1} / ${widget.pages.length}',
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (canShare) ...[
              FilledButton.icon(
                onPressed: sharing ? null : share,
                icon: const Icon(Icons.ios_share),
                label: const Text('مشاركة الصور'),
              ),
              const SizedBox(height: 12),
            ],
            if (!canShare)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  '1. احفظ صور اختياراتك\n2. افتح Instagram\n3. دز الصور إلنا بالخاص',
                ),
              ),
            const Text(
              'إذا المتصفح فتح الصورة بدل الحفظ، اضغط عليها مطولاً واحفظها. تگدر هم تفتح الموقع بمتصفح الهاتف.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                AppScope.of(context).analytics.event('instagram_clicked');
                final opened = await launchUrl(
                  Uri.parse(AppConfig.instagramUrl),
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
                if (!opened && context.mounted) {
                  showNotice(
                    context,
                    'افتح Instagram ودز الصور إلى @${AppConfig.instagramUsername}',
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح Instagram'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                final app = AppScope.of(context);
                if (await confirm(
                  context,
                  'بدء اختيار جديد؟',
                  'تأكد إنك حفظت الصور قبل مسح اختياراتك.',
                )) {
                  app.selection.clear();
                  if (context.mounted) {
                    Navigator.pop(context);
                    context.go('/');
                  }
                }
              },
              child: const Text('بدء اختيار جديد'),
            ),
          ],
        ),
      ),
    ),
  );
}
