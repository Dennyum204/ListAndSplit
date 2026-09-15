import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewKey = ValueKey('uiPreviewBoundary');

Widget uiPreviewBoundary(Widget child) =>
    RepaintBoundary(key: _previewKey, child: child);

/// Uses locally installed SDK fonts only for opt-in review renders.
/// Normal test runs remain independent of fonts and workstation paths.
Future<void> prepareUiPreviewFonts() async {
  const directory = String.fromEnvironment('UI_PREVIEW_FONT_DIRECTORY');
  const output = String.fromEnvironment('UI_PREVIEW_DIRECTORY');
  if (output.isEmpty || directory.isEmpty) return;
  for (final entry in {
    'Ahem': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
    'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
    'MaterialIcons': ['MaterialIcons-Regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      final bytes =
          await File('$directory${Platform.pathSeparator}$name').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// Optional local render evidence, never a golden baseline or CI dependency.
Future<void> captureUiPreview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('UI_PREVIEW_DIRECTORY');
  if (directory.isEmpty) return;
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'Use a simple preview name');
  }
  final target = Directory(directory).absolute;
  final repository = Directory.current.absolute.path;
  if (target.path == repository ||
      target.path.startsWith('$repository${Platform.pathSeparator}')) {
    throw ArgumentError('UI preview output must stay outside the repository');
  }
  await tester.pumpAndSettle();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_previewKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await target.create(recursive: true);
      await File('${target.path}${Platform.pathSeparator}$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
