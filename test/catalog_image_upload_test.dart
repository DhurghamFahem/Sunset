import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sunset/services/admin_service.dart';

void main() {
  test(
    'photo previews are small JPEGs and originals stay byte-for-byte intact',
    () {
      final photo = img.Image(width: 1200, height: 800);
      final random = Random(42);
      for (final pixel in photo) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final original = Uint8List.fromList(img.encodeJpg(photo, quality: 95));
      final before = Uint8List.fromList(original);
      final prepared = prepareCatalogImage(original, extension: 'JPG');
      final preview = img.decodeJpg(prepared.thumbnail)!;
      expect(prepared.bytes, orderedEquals(before));
      expect(prepared.mime, 'image/jpeg');
      expect(prepared.thumbnailMime, 'image/jpeg');
      expect(prepared.thumbnailExtension, 'jpg');
      expect((preview.width, preview.height), (480, 320));
      expect(prepared.thumbnail.length, lessThan(120 * 1024));
      expect(prepared.thumbnail.length, lessThan(original.length ~/ 4));
    },
  );

  test('transparent tattoo previews retain alpha and proportions', () {
    final tattoo = img.Image(width: 800, height: 1200, numChannels: 4);
    img.fillRect(
      tattoo,
      x1: 200,
      y1: 300,
      x2: 600,
      y2: 900,
      color: img.ColorRgba8(20, 40, 60, 128),
    );
    final original = Uint8List.fromList(img.encodePng(tattoo));
    final prepared = prepareCatalogImage(original, extension: 'png');
    final preview = img.decodePng(prepared.thumbnail)!;
    expect(prepared.bytes, orderedEquals(original));
    expect(prepared.thumbnailMime, 'image/png');
    expect(prepared.thumbnailExtension, 'png');
    expect((preview.width, preview.height), (320, 480));
    expect(preview.getPixel(0, 0).a, 0);
    expect(preview.getPixel(160, 240).a, 128);
  });

  test('opaque RGBA PNGs use JPEG previews without enlarging small images', () {
    final tattoo = img.Image(width: 80, height: 120, numChannels: 4);
    img.fill(tattoo, color: img.ColorRgba8(20, 40, 60, 255));
    final original = Uint8List.fromList(img.encodePng(tattoo));
    final prepared = prepareCatalogImage(original, extension: 'png');
    final preview = img.decodeJpg(prepared.thumbnail)!;
    expect(prepared.mime, 'image/png');
    expect(prepared.bytes, orderedEquals(original));
    expect(prepared.thumbnailMime, 'image/jpeg');
    expect((preview.width, preview.height), (80, 120));
  });

  test('camera orientation is applied before sizing the preview', () {
    final photo = img.Image(width: 1200, height: 800);
    photo.exif.imageIfd.orientation = 6;
    final original = Uint8List.fromList(img.encodeJpg(photo));
    final prepared = prepareCatalogImage(original, extension: 'jpeg');
    final preview = img.decodeJpg(prepared.thumbnail)!;
    expect((preview.width, preview.height), (320, 480));
    expect(prepared.bytes, orderedEquals(original));
  });

  test('invalid uploads are still rejected before creating a preview', () {
    expect(
      () => prepareCatalogImage(Uint8List(0), extension: 'png'),
      throwsA(isA<CatalogInputException>()),
    );
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 8, height: 8)),
    );
    expect(
      () => prepareCatalogImage(png, extension: 'jpg'),
      throwsA(isA<CatalogInputException>()),
    );
  });
}
