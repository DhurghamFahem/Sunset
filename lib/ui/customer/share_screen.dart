import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/order.dart';
import '../../services/share/share_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({
    super.key,
    required this.pages,
    this.catalogExport = false,
    this.initialSource = OrderSource.instagram,
    this.onSourceChanged,
    this.exportNotice,
  });
  final List<Uint8List> pages;
  final bool catalogExport;
  final OrderSource initialSource;
  final Future<void> Function(OrderSource)? onSourceChanged;
  final String? exportNotice;
  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final service = ShareService();
  final preview = PageController();
  final downloaded = <int>{};
  int current = 0;
  late OrderSource source = widget.initialSource;
  bool savingSource = false;
  bool canShare = false;
  bool get allDownloaded => downloaded.length == widget.pages.length;

  @override
  void initState() {
    super.initState();
    canShare = service.prepare(widget.pages);
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

  Future<void> changeSource(OrderSource value) async {
    if (savingSource || value == source) return;
    setState(() => savingSource = true);
    try {
      await widget.onSourceChanged?.call(value);
      if (mounted) setState(() => source = value);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          e is OrderException
              ? e.message
              : 'تعذر حفظ منصة الإرسال. حاول مرة ثانية.',
        );
      }
    } finally {
      if (mounted) setState(() => savingSource = false);
    }
  }

  Future<void> shareWithCustomer() async {
    final result = await service.share();
    if (mounted && result != 'shared' && result != 'cancelled') {
      showNotice(context, 'احفظ الصور وأرفقها بمحادثة الزبون.');
    }
  }

  Future<void> openChat() async {
    final whatsapp = source == OrderSource.whatsapp;
    AppScope.of(context).analytics.event('${source.name}_clicked');
    final opened = await launchUrl(
      Uri.parse(whatsapp ? AppConfig.whatsappUrl : AppConfig.instagramUrl),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened && mounted) {
      showNotice(
        context,
        whatsapp
            ? 'افتح WhatsApp ودز الصور إلى 07778700244'
            : 'افتح Instagram ودز الصور إلى @${AppConfig.instagramUsername}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.catalogExport ? 'صور للزبون بالأسعار' : 'إرسال اختياراتك',
        ),
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
                      if (!widget.catalogExport) const JourneySteps(current: 2),
                      const SizedBox(height: 24),
                      Text(
                        widget.catalogExport
                            ? 'صور الوشومات جاهزة.'
                            : 'ذوقك صار بصورة.',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.catalogExport
                            ? 'احفظ الصور وأرسلها للزبون. الأسعار للقطعة، ولم يتم إنشاء طلب.'
                            : widget.pages.length == 1
                            ? 'جمعنالك اختياراتك بصورة وحدة. احفظها ودزها إلنا بالمحادثة.'
                            : 'جمعنالك اختياراتك بـ ${widget.pages.length} صور. احفظها ودزها إلنا بالمحادثة.',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 16),
                      if (widget.exportNotice != null) ...[
                        Text(
                          widget.exportNotice!,
                          style: const TextStyle(color: forest, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                      ],
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
                        widget.catalogExport
                            ? 'أرفق الصور المحفوظة بمحادثة الزبون.'
                            : allDownloaded
                            ? 'تأكد إن الصور انحفظت، وبعدين أرفقها بالمحادثة ودزها إلنا.'
                            : 'احفظ صور اختياراتك، وبعدين افتح محادثتنا.',
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 10),
                      if (!widget.catalogExport) ...[
                        SegmentedButton<OrderSource>(
                          segments: const [
                            ButtonSegment(
                              value: OrderSource.instagram,
                              label: Text('Instagram'),
                            ),
                            ButtonSegment(
                              value: OrderSource.whatsapp,
                              label: Text('WhatsApp'),
                            ),
                          ],
                          selected: {source},
                          onSelectionChanged: savingSource
                              ? null
                              : (values) => changeSource(values.single),
                        ),
                        if (savingSource) const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                      ],
                      FilledButton.icon(
                        key: const ValueKey('share-next'),
                        onPressed: savingSource
                            ? null
                            : widget.catalogExport
                            ? download
                            : allDownloaded
                            ? openChat
                            : download,
                        icon: Icon(
                          allDownloaded && !widget.catalogExport
                              ? Icons.open_in_new
                              : Icons.download_outlined,
                        ),
                        label: Text(
                          allDownloaded && !widget.catalogExport
                              ? 'افتح محادثتنا على ${source.label}'
                              : widget.pages.length == 1
                              ? 'حفظ الصورة'
                              : 'حفظ الصورة ${current + 1} / ${widget.pages.length}',
                        ),
                      ),
                      if (widget.catalogExport && canShare)
                        TextButton.icon(
                          onPressed: shareWithCustomer,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('مشاركة مع الزبون'),
                        ),
                      if (allDownloaded && !widget.catalogExport)
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
