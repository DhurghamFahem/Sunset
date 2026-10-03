import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/catalog.dart';

typedef ImageLoader = Future<Uint8List> Function(String url);

class SelectionRenderer {
  SelectionRenderer({ImageLoader? imageLoader})
    : _load = imageLoader ?? _download;
  final ImageLoader _load;
  static Future<Uint8List> _download(String url) async {
    if (url.startsWith('data:image/')) {
      return Uri.parse(url).data!.contentAsBytes();
    }
    if (url.startsWith('asset:')) {
      final data = await rootBundle.load(url.substring('asset:'.length));
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    // Fetch bytes through CORS before decoding. No cross-origin HTML canvas is
    // used; a failed fetch aborts export rather than silently omitting artwork.
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > AppConfig.maxUploadBytes) {
      throw StateError('Image unavailable');
    }
    return response.bodyBytes;
  }

  static List<List<Tattoo>> pages(List<Tattoo> products) => [
    for (var i = 0; i < products.length; i += AppConfig.designsPerImage)
      products.skip(i).take(AppConfig.designsPerImage).toList(),
  ];
  Future<List<Uint8List>> render(
    List<Tattoo> products, {
    ValueChanged<double>? onProgress,
    String? orderCode,
    Map<String, int> quantities = const {},
  }) async {
    final batches = pages(products);
    final output = <Uint8List>[];
    var done = 0;
    for (var page = 0; page < batches.length; page++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const width = 1200.0, height = 1680.0;
      canvas.drawColor(const Color(0xFFF9F7F1), BlendMode.src);
      if (AppConfig.logoAsset.isEmpty) {
        _text(
          canvas,
          AppConfig.brand,
          const Rect.fromLTWH(60, 45, 1080, 80),
          size: 62,
          bold: true,
          latin: true,
        );
      } else {
        final data = await rootBundle.load(AppConfig.logoAsset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final logo = (await codec.getNextFrame()).image;
        _image(canvas, logo, const Rect.fromLTWH(470, 30, 260, 105));
        logo.dispose();
        codec.dispose();
      }
      _text(
        canvas,
        'اختياراتي من G2G',
        const Rect.fromLTWH(60, 140, 1080, 80),
        size: 38,
        bold: true,
      );
      _text(
        canvas,
        '${orderCode == null ? '' : 'ORDER $orderCode    •    '}${page + 1} / ${batches.length}',
        const Rect.fromLTWH(60, 213, 1080, 55),
        size: 24,
        latin: true,
      );
      final batch = batches[page];
      final single = batch.length == 1;
      final rows = single ? 1 : (batch.length / 2).ceil();
      final cellWidth = single ? 1080.0 : 520.0;
      final cellHeight = 1220.0 / rows;
      for (var i = 0; i < batch.length; i++) {
        final product = batch[i];
        final x = single ? 60.0 : (i.isEven ? 620.0 : 60.0);
        final y = 290 + (single ? 0 : i ~/ 2) * cellHeight;
        final card = Rect.fromLTWH(x, y, cellWidth, cellHeight - 20);
        canvas.drawRRect(
          RRect.fromRectAndRadius(card, const Radius.circular(18)),
          Paint()..color = Colors.white,
        );
        final bytes = await _load(product.imageUrl);
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        _image(
          canvas,
          image,
          Rect.fromLTWH(x + 24, y + 20, cellWidth - 48, cellHeight - 138),
        );
        image.dispose();
        codec.dispose();
        _text(
          canvas,
          product.displayName,
          Rect.fromLTWH(x + 12, y + cellHeight - 112, cellWidth - 24, 46),
          size: 29,
          bold: true,
        );
        if (product.dimensions.isNotEmpty ||
            quantities.containsKey(product.id)) {
          _text(
            canvas,
            [
              if (quantities.containsKey(product.id))
                'الكمية: ${quantities[product.id]}',
              if (product.dimensions.isNotEmpty) product.dimensions,
            ].join(' • '),
            Rect.fromLTWH(x + 12, y + cellHeight - 67, cellWidth - 24, 40),
            size: 25,
            latin: !quantities.containsKey(product.id),
          );
        }
        onProgress?.call(++done / products.length);
      }
      _text(
        canvas,
        '@${AppConfig.instagramUsername}',
        const Rect.fromLTWH(60, 1540, 1080, 65),
        size: 30,
        latin: true,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (png == null) throw StateError('Export failed');
      output.add(png.buffer.asUint8List());
    }
    return output;
  }

  void _image(Canvas canvas, ui.Image image, Rect destination) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      destination.size,
    );
    final rect = Alignment.center.inscribe(fitted.destination, destination);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Rect rect, {
    double size = 28,
    bool bold = false,
    bool latin = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'NotoArabic',
          color: const Color(0xFF253B30),
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: latin ? TextDirection.ltr : TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    );
    painter.layout(minWidth: rect.width, maxWidth: rect.width);
    painter.paint(canvas, Offset(rect.left, rect.top));
    painter.dispose();
  }
}
