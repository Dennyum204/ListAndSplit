// Run: flutter test tools/branding/generate_branding_test.dart
// Generates reviewed source assets, not arbitrary user-selected paths.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/branding/list_split_mark.dart';

void main() {
  testWidgets('generate launcher resources from original mark geometry',
      (tester) async {
    final paths = ListSplitMarkPainter.paths
        .map((commands) => commands
            .map((c) => '${[
                  'M',
                  'L',
                  'Q'
                ][c[0].toInt()]}${c.skip(1).map((n) => n.toInt()).join(' ')}')
            .join(' '))
        .toList();
    void write(String path, String data) {
      final file = File(path)..parent.createSync(recursive: true);
      file.writeAsStringSync('$data\n');
    }

    const root = 'android/app/src/main/res';
    String vector(String color) =>
        '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n${paths.map((p) => '  <path android:pathData="$p" android:fillColor="#00000000" android:strokeColor="$color" android:strokeWidth="5" android:strokeLineCap="round" android:strokeLineJoin="round"/>').join('\n')}\n</vector>';
    write('$root/drawable/ic_launcher_foreground.xml', vector('#F4AE45'));
    write('$root/drawable/ic_launcher_monochrome.xml', vector('#FFFFFF'));
    write(
        '$root/drawable/ic_stat_list_split.xml',
        vector('#FFFFFF')
            .replaceAll(
                'android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108"',
                'android:width="24dp" android:height="24dp" android:viewportWidth="64" android:viewportHeight="64"')
            .replaceFirst('>\n  <path',
                '>\n  <group android:translateX="-22" android:translateY="-20">\n  <path')
            .replaceFirst('</vector>', '  </group>\n</vector>'));
    write('$root/values/brand_colors.xml',
        '<resources><color name="brand_charcoal">#202020</color></resources>');
    for (final version in [26, 33]) {
      write('$root/mipmap-anydpi-v$version/ic_launcher.xml',
          '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n  <background android:drawable="@color/brand_charcoal"/>\n  <foreground android:drawable="@drawable/ic_launcher_foreground"/>${version == 33 ? '\n  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' : ''}\n</adaptive-icon>');
    }
    write('assets/branding/list-and-split.svg',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">\n<rect width="108" height="108" fill="#202020"/>\n<g fill="none" stroke="#F4AE45" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">\n${paths.map((p) => '<path d="$p"/>').join('\n')}\n</g>\n</svg>');
    await tester.runAsync(() async {
      for (final entry in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
        'preview': 512
      }.entries) {
        final size = entry.value;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(ListSplitMarkPainter.background, BlendMode.src);
        const ListSplitMarkPainter()
            .paint(canvas, Size.square(size.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File(entry.key == 'preview'
            ? 'assets/branding/launcher-preview.png'
            : '$root/mipmap-${entry.key}/ic_launcher.png');
        target.parent.createSync(recursive: true);
        await target.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
    });
  });
}
