import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  final preview = PageController();
  final downloaded = <int>{};
  int current = 0;
  bool get allDownloaded => downloaded.length == widget.pages.length;

  @override
  void initState() {
    super.initState();
    service.prepare(widget.pages);
  }

  @override
  void dispose() {
    preview.dispose();
    service.dispose();
    super.dispose();
  }

  void download() {
    service.download(current);
    setState(() => downloaded.add(current));
    final next = List.generate(
      widget.pages.length,
      (i) => i,
    ).where((i) => !downloaded.contains(i)).firstOrNull;
    if (next != null) preview.jumpToPage(next);
  }

  Future<void> openInstagram() async {
    AppScope.of(context).analytics.event('instagram_clicked');
    final opened = await launchUrl(
      Uri.parse(AppConfig.instagramUrl),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && mounted) {
      showNotice(
        context,
        'افتح Instagram ودز الصور إلى @${AppConfig.instagramUsername}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إرسال اختياراتك'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تعديل'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const JourneySteps(current: 2),
                      const SizedBox(height: 24),
                      Text(
                        'ذوقك صار بصورة.',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.pages.length == 1
                            ? 'جمعنالك اختياراتك بصورة وحدة. احفظها ودزها إلنا بالمحادثة.'
                            : 'جمعنالك اختياراتك بـ ${widget.pages.length} صور. احفظها ودزها إلنا بالمحادثة.',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).height * .38).clamp(
                          150.0,
                          380.0,
                        ),
                        child: PageView.builder(
                          controller: preview,
                          onPageChanged: (index) =>
                              setState(() => current = index),
                          itemCount: widget.pages.length,
                          itemBuilder: (_, i) => StudioPanel(
                            padding: const EdgeInsets.all(12),
                            child: Image.memory(
                              widget.pages[i],
                              fit: BoxFit.contain,
                              semanticLabel:
                                  'اختياراتي ${i + 1} من ${widget.pages.length}',
                            ),
                          ),
                        ),
                      ),
                      if (widget.pages.length > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'الصورة السابقة',
                              onPressed: current == 0
                                  ? null
                                  : () => preview.jumpToPage(current - 1),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Text(
                              '${current + 1} / ${widget.pages.length}',
                              textDirection: TextDirection.ltr,
                            ),
                            IconButton(
                              tooltip: 'الصورة التالية',
                              onPressed: current == widget.pages.length - 1
                                  ? null
                                  : () => preview.jumpToPage(current + 1),
                              icon: const Icon(Icons.arrow_forward),
                            ),
                          ],
                        ),
                      const Text(
                        'إذا انفتحت الصورة بدل الحفظ، اضغط عليها مطولاً واحفظها.',
                        style: TextStyle(color: muted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.fromBorderSide(BorderSide(color: line)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        allDownloaded
                            ? 'تأكد إن الصور انحفظت، وبعدين أرفقها بالمحادثة ودزها إلنا.'
                            : 'احفظ صور اختياراتك، وبعدين افتح محادثتنا على Instagram.',
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const ValueKey('share-next'),
                        onPressed: allDownloaded ? openInstagram : download,
                        icon: Icon(
                          allDownloaded
                              ? Icons.open_in_new
                              : Icons.download_outlined,
                        ),
                        label: Text(
                          allDownloaded
                              ? 'افتح محادثتنا على Instagram'
                              : widget.pages.length == 1
                              ? 'حفظ الصورة'
                              : 'حفظ الصورة ${current + 1} / ${widget.pages.length}',
                        ),
                      ),
                      if (allDownloaded)
                        TextButton(
                          onPressed: download,
                          child: const Text('حفظ الصورة مرة ثانية'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
