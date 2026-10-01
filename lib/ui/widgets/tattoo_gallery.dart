import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import '../theme.dart';
import 'common.dart';

class TattooGallery extends StatefulWidget {
  const TattooGallery({super.key, required this.images, required this.label});
  final List<TattooImage> images;
  final String label;

  @override
  State<TattooGallery> createState() => _TattooGalleryState();
}

class _TattooGalleryState extends State<TattooGallery> {
  final pages = PageController();
  final thumbnails = ScrollController();
  int current = 0;
  bool zoomed = false;

  @override
  void dispose() {
    pages.dispose();
    thumbnails.dispose();
    super.dispose();
  }

  void showImage(int index) {
    if (index < 0 || index >= widget.images.length) return;
    pages.jumpToPage(index);
  }

  void pageChanged(int index) {
    setState(() {
      current = index;
      zoomed = false;
    });
    if (thumbnails.hasClients) {
      thumbnails.animateTo(
        (index * 82.0).clamp(0.0, thumbnails.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .48,
          child: PageView.builder(
            controller: pages,
            physics: zoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: pageChanged,
            itemCount: widget.images.length,
            itemBuilder: (_, index) => _GalleryPhoto(
              // Reset zoom when switching images, including via thumbnails.
              key: ValueKey('$current-$index'),
              image: widget.images[index],
              label: '${widget.label} — صورة ${index + 1}',
              onZoomChanged: (value) {
                if (index == current && zoomed != value) {
                  setState(() => zoomed = value);
                }
              },
            ),
          ),
        ),
      ),
      if (widget.images.length > 1) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'الصورة السابقة',
              onPressed: current == 0 ? null : () => showImage(current - 1),
              icon: const Icon(Icons.arrow_back),
            ),
            Semantics(
              liveRegion: true,
              label: 'صورة ${current + 1} من ${widget.images.length}',
              child: Text(
                '${current + 1} / ${widget.images.length}',
                textDirection: TextDirection.ltr,
              ),
            ),
            IconButton(
              tooltip: 'الصورة التالية',
              onPressed: current == widget.images.length - 1
                  ? null
                  : () => showImage(current + 1),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            controller: thumbnails,
            scrollDirection: Axis.horizontal,
            itemCount: widget.images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) => Semantics(
              selected: current == index,
              button: true,
              label: 'عرض الصورة ${index + 1}',
              child: InkWell(
                key: ValueKey('gallery-thumbnail-$index'),
                onTap: () => showImage(index),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 74,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current == index ? forest : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: CatalogImage(
                    widget.images[index].thumbnail,
                    label: 'صورة ${index + 1}',
                    padding: 4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        widget.images.length > 1
            ? 'اسحب بين الصور أو اختار صورة مصغرة • كبّر حتى تشوف التفاصيل'
            : 'كبّر الصورة حتى تشوف التفاصيل',
        style: const TextStyle(color: muted, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _GalleryPhoto extends StatefulWidget {
  const _GalleryPhoto({
    super.key,
    required this.image,
    required this.label,
    required this.onZoomChanged,
  });
  final TattooImage image;
  final String label;
  final ValueChanged<bool> onZoomChanged;
  @override
  State<_GalleryPhoto> createState() => _GalleryPhotoState();
}

class _GalleryPhotoState extends State<_GalleryPhoto> {
  final transformation = TransformationController();
  bool zoomed = false;
  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: transformation,
    minScale: 1,
    maxScale: 5,
    panEnabled: zoomed,
    onInteractionUpdate: (_) {
      final value = transformation.value.getMaxScaleOnAxis() > 1.01;
      if (value != zoomed) {
        setState(() => zoomed = value);
        widget.onZoomChanged(value);
      }
    },
    child: SizedBox.expand(
      child: CatalogImage(widget.image.url, label: widget.label, padding: 24),
    ),
  );
}
