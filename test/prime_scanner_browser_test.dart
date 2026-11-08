// Run separately: flutter test --platform chrome test/prime_scanner_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// Exercise the real web plugin, not the native platform mock in widget tests.
// ignore: implementation_imports
import 'package:mobile_scanner/src/web/mobile_scanner_web.dart';
import 'package:sunset/ui/admin/preparation_screen.dart';

@JS('eval')
external JSAny? evaluate(JSString script);

void main() {
  testWidgets('web camera starts with Safari inline playback requirements', (
    tester,
  ) async {
    MobileScannerPlatform.instance = MobileScannerWeb();
    evaluate(
      r'''
      window.scannerTest = {
        getUserMedia: navigator.mediaDevices.getUserMedia,
        play: HTMLVideoElement.prototype.play,
        inlinePlay: false,
        tracks: [],
      };
      const fixture = document.createElement('canvas');
      fixture.width = 640;
      fixture.height = 480;
      const paint = () => {
        fixture.getContext('2d').fillStyle = '#83a57d';
        fixture.getContext('2d').fillRect(0, 0, 640, 480);
      };
      paint();
      scannerTest.timer = setInterval(paint, 100);
      navigator.mediaDevices.getUserMedia = async () => {
        const stream = fixture.captureStream(10);
        scannerTest.tracks.push(...stream.getTracks());
        return stream;
      };
      HTMLVideoElement.prototype.play = function() {
        if (!this.hasAttribute('playsinline') || !this.hasAttribute('muted')) {
          return Promise.reject(new DOMException('Inline preview required', 'NotAllowedError'));
        }
        scannerTest.inlinePlay = true;
        scannerTest.video = this;
        // This synthetic stream has no real camera-permission click. Allow
        // headless Chrome playback after checking Safari's inline attributes.
        this.muted = true;
        return scannerTest.play.call(this);
      };
    '''
          .toJS,
    );
    addTearDown(() {
      evaluate(
        r'''
        clearInterval(scannerTest.timer);
        scannerTest.tracks.forEach(track => track.stop());
        navigator.mediaDevices.getUserMedia = scannerTest.getUserMedia;
        HTMLVideoElement.prototype.play = scannerTest.play;
        delete window.scannerTest;
      '''
            .toJS,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: PrimeQrScanner()));
    // Real JS library loading and media playback run outside Flutter's fake clock.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(HtmlElementView).evaluate().isNotEmpty) break;
    }
    expect(
      MobileScannerPlatform.instance.activeWebReader,
      WebBarcodeReader.zxingJs,
    );
    expect(find.byType(HtmlElementView), findsOneWidget);
    expect(
      (evaluate(
        'scannerTest.inlinePlay && scannerTest.video.videoWidth > 0 && !scannerTest.video.paused'
            .toJS,
      ) as JSBoolean).toDart,
      isTrue,
    );
    expect(find.text('جاري تشغيل الكاميرا…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(
      (evaluate(
        'scannerTest.tracks.every(track => track.readyState === "ended")'.toJS,
      ) as JSBoolean).toDart,
      isTrue,
    );
  });
}
