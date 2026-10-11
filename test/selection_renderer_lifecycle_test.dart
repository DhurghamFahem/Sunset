import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sunset/services/selection_renderer.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List artwork;
  setUpAll(() {
    final source = img.Image(width: 1600, height: 800, numChannels: 4);
    img.fillRect(
      source,
      x1: 400,
      y1: 200,
      x2: 1199,
      y2: 599,
      color: img.ColorRgba8(220, 30, 40, 255),
    );
    artwork = Uint8List.fromList(img.encodePng(source));
  });

  test(
    'each page retains artwork through rasterization then releases it',
    () async {
      final created = <ui.Image>[];
      final previous = ui.Image.onCreate;
      ui.Image.onCreate = created.add;
      addTearDown(() => ui.Image.onCreate = previous);
      var loads = 0;
      final pages =
          await SelectionRenderer(
            imageLoader: (_) async {
              loads++;
              if (loads == 7) {
                // No resources from the previous page may survive into the next one.
                expect(created, isNotEmpty);
                expect(created.every((image) => image.debugDisposed), isTrue);
              }
              return artwork;
            },
          ).render(
            List.generate(7, fixture),
            onProgress: (_) {
              final live = created
                  .where((image) => !image.debugDisposed)
                  .toList();
              // Progress is reported after recording artwork, before rasterization.
              expect(live.length, loads <= 6 ? loads : 1);
              for (final image in live) {
                expect(image.width, lessThanOrEqualTo(loads <= 6 ? 472 : 1032));
                expect(image.width / image.height, closeTo(2, .01));
              }
            },
          );
      expect(created.every((image) => image.debugDisposed), isTrue);
      expect(pages.length, 2);
      // Check actual encoded pixels, including every grid cell and the expanded
      // final page. Transparent regions must show the white card, not black.
      for (var page = 0; page < pages.length; page++) {
        final output = img.decodePng(pages[page])!;
        final count = page == 0 ? 6 : 1;
        final cellHeight = page == 0 ? 1220 / 3 : 1220.0;
        for (var i = 0; i < count; i++) {
          final x = page == 0 ? (i.isEven ? 880 : 320) : 600;
          final y = (310 + (i ~/ 2) * cellHeight + (cellHeight - 138) / 2)
              .round();
          final center = output.getPixel(x, y);
          expect(center.r, greaterThan(200));
          expect(center.g, lessThan(60));
          final transparent = output.getPixel(page == 0 ? x - 220 : 100, y);
          expect(
            [transparent.r, transparent.g, transparent.b, transparent.a],
            [255, 255, 255, 255],
          );
        }
      }
    },
  );

  test(
    'a later image failure releases previously decoded artwork and recording',
    () async {
      final images = <ui.Image>[];
      final pictures = <ui.Picture>[];
      final previousImage = ui.Image.onCreate;
      final previousPicture = ui.Picture.onCreate;
      ui.Image.onCreate = images.add;
      ui.Picture.onCreate = pictures.add;
      addTearDown(() {
        ui.Image.onCreate = previousImage;
        ui.Picture.onCreate = previousPicture;
      });
      var loads = 0;
      await expectLater(
        SelectionRenderer(
          imageLoader: (_) async {
            if (++loads == 2) throw StateError('Download failed');
            return artwork;
          },
        ).render([fixture(1), fixture(2)]),
        throwsStateError,
      );
      expect(images, isNotEmpty);
      expect(images.every((image) => image.debugDisposed), isTrue);
      expect(pictures, isNotEmpty);
      expect(pictures.every((picture) => picture.debugDisposed), isTrue);
    },
  );
}
