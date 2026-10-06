import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paints [painter] at [size] and returns the colour of the pixel at [at].
Future<Color> paintAndReadPixel(
  WidgetTester tester,
  CustomPainter painter,
  Size size,
  Offset at,
) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final image = recorder
      .endRecording()
      .toImageSync(size.width.toInt(), size.height.toInt());
  final data = (await tester.runAsync(() => image.toByteData()))!;
  final i = (at.dy.toInt() * image.width + at.dx.toInt()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}
