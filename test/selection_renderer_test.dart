import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sunset/services/selection_renderer.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
  });
  test(
    'twenty-one designs produce four pages without omissions or duplicates',
    () {
      final items = List.generate(21, (i) => fixture(i));
      final pages = SelectionRenderer.pages(items);
      expect(pages.map((p) => p.length), [6, 6, 6, 3]);
      expect(pages.expand((p) => p).map((p) => p.id), items.map((p) => p.id));
      expect(SelectionRenderer.pages([]), isEmpty);
    },
  );
  test('real PNG export preserves artwork aspect ratio and includes all selected images', () async {
    final source = img.Image(width: 400, height: 100);
    img.fill(source, color: img.ColorRgb8(215, 34, 40));
    final bytes = Uint8List.fromList(img.encodePng(source));
    final requests = <String>[];
    final renderer = SelectionRenderer(
      imageLoader: (url) async {
        requests.add(url);
        return bytes;
      },
    );
    final pages = await renderer.render(List.generate(7, (i) => fixture(i)));
    expect(requests.length, 7);
    expect(pages.length, 2);
    final output = img.decodePng(pages.last)!;
    expect(output.width, 1200);
    expect(output.height, 1680);
    var left = 1200, right = 0, top = 1680, bottom = 0;
    for (var y = 0; y < output.height; y++) {
      for (var x = 0; x < output.width; x++) {
        final pixel = output.getPixel(x, y);
        if (pixel.r > 180 && pixel.g < 70 && pixel.b < 80) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    expect((right - left + 1) / (bottom - top + 1), closeTo(4, .03));
    final dir = Directory('test-results')..createSync(recursive: true);
    File('${dir.path}/fixture-wide.png').writeAsBytesSync(bytes);
    File('${dir.path}/selection-six.png').writeAsBytesSync(pages.first);
    File('${dir.path}/selection-single.png').writeAsBytesSync(pages.last);
  });
  test(
    'image failure fails export instead of silently sharing incomplete artwork',
    () async {
      await expectLater(
        SelectionRenderer(
          imageLoader: (_) async => throw StateError('CORS failure'),
        ).render([fixture(1)]),
        throwsStateError,
      );
    },
  );
}
