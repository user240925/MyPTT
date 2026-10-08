import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/terminal_surface.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late List<String> opened;
  late List<String> copied;
  late int backgroundTaps;
  String? clipboard;

  // The surface is exactly 800x480: 80x24 cells of 10x20 pixels.
  Future<void> pumpSurface(WidgetTester tester, {bool inputEnabled = true}) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    clipboard = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    opened = [];
    copied = [];
    backgroundTaps = 0;
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalSurface(
          session: session,
          inputEnabled: inputEnabled,
          onTapBackground: () => backgroundTaps++,
          onOpenUrl: opened.add,
          onCopied: copied.add,
        ),
      ),
    ));
  }

  Future<void> disposeSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(session.dispose);
  }

  /// Moves two fingers between the given x positions in small steps, the
  /// way a real pinch arrives, and leaves both fingers down.
  Future<(TestGesture, TestGesture)> pinch(
    WidgetTester tester, {
    required (double, double) from,
    required (double, double) to,
  }) async {
    const y = 240.0, steps = 10;
    final a = await tester.startGesture(Offset(from.$1, y));
    final b = await tester.startGesture(Offset(from.$2, y));
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      await a.moveTo(Offset(from.$1 + (to.$1 - from.$1) * t, y));
      await b.moveTo(Offset(from.$2 + (to.$2 - from.$2) * t, y));
    }
    await tester.pump();
    return (a, b);
  }

  double zoom(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const Key('terminal-zoom')))
      .transform
      .getMaxScaleOnAxis();

  testWidgets('one-finger swipes send navigation keys', (tester) async {
    await pumpSurface(tester);
    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    expect(conn.sent, '\x1b[D'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 240), const Offset(-200, 0));
    expect(conn.sent, '\x1b[C'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 300), const Offset(0, -200));
    expect(conn.sent, '\x1b[6~'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 100), const Offset(0, 200));
    expect(conn.sent, '\x1b[5~'.codeUnits);
    await disposeSurface(tester);
  });

  testWidgets('short and diagonal drags send nothing', (tester) async {
    await pumpSurface(tester);
    await tester.dragFrom(const Offset(400, 240), const Offset(30, 0));
    await tester.dragFrom(const Offset(400, 240), const Offset(150, 150));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('swipes send nothing when input is disabled', (tester) async {
    await pumpSurface(tester, inputEnabled: false);
    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  // Review Focus 5
  testWidgets('pinch and panning while zoomed send nothing', (tester) async {
    await pumpSurface(tester);
    expect(zoom(tester), closeTo(1, 0.001));

    final (a, b) = await pinch(tester, from: (300, 500), to: (150, 650));
    await a.up();
    // The remaining finger keeps moving after the other lifts.
    await b.moveTo(const Offset(650, 440));
    await b.up();
    await tester.pump();
    expect(zoom(tester), greaterThan(1.5));
    expect(conn.sent, isEmpty);

    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    await tester.dragFrom(const Offset(400, 240), const Offset(0, -200));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(zoom(tester), greaterThan(1.5));
    await disposeSurface(tester);
  });

  testWidgets('zoom is limited to between 1x and 4x', (tester) async {
    await pumpSurface(tester);
    var (a, b) = await pinch(tester, from: (390, 410), to: (10, 790));
    await a.up();
    await b.up();
    await tester.pump();
    expect(zoom(tester), closeTo(4, 0.001));

    (a, b) = await pinch(tester, from: (10, 790), to: (399, 401));
    await a.up();
    await b.up();
    await tester.pump();
    expect(zoom(tester), closeTo(1, 0.001));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('tapping a URL opens it; tapping elsewhere reports a background tap',
      (tester) async {
    await pumpSurface(tester);
    conn.emit('see https://example.com/a now'.codeUnits);
    await tester.pump();

    await tester.tapAt(const Offset(105, 10));
    expect(opened, ['https://example.com/a']);
    expect(backgroundTaps, 0);

    await tester.tapAt(const Offset(5, 10));
    await tester.tapAt(const Offset(400, 300));
    expect(opened.length, 1);
    expect(backgroundTaps, 2);
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('the mouse pointer becomes a hand over a URL', (tester) async {
    await pumpSurface(tester);
    conn.emit('see https://example.com/a now'.codeUnits);
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 10));
    addTearDown(mouse.removePointer);
    MouseCursor cursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    await tester.pump();
    expect(cursor(), SystemMouseCursors.basic);
    await mouse.moveTo(const Offset(105, 10));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.click);
    await mouse.moveTo(const Offset(105, 300));
    await tester.pump();
    expect(cursor(), SystemMouseCursors.basic);
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('long-press drag selects and copies text', (tester) async {
    await pumpSurface(tester);
    conn.emit(codec.encode('Hello 中文 World').bytes);
    await tester.pump();

    final g = await tester.startGesture(const Offset(5, 10));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(const Offset(95, 10));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(clipboard, 'Hello 中文');
    expect(copied, ['Hello 中文']);
    expect(conn.sent, isEmpty);

    // The next tap only clears the selection.
    await tester.tapAt(const Offset(400, 300));
    expect(backgroundTaps, 0);
    await tester.tapAt(const Offset(400, 300));
    expect(backgroundTaps, 1);
    await disposeSurface(tester);
  });

  testWidgets('taps outside the terminal area are background taps', (tester) async {
    await pumpSurface(tester);
    // Portrait-like: the terminal fills the top 480 px, black space below.
    tester.view.physicalSize = const Size(800, 900);
    await tester.pump();
    conn.emit('\x1b[24;1Hhttps://example.com/bottom'.codeUnits);
    await tester.pump();

    await tester.tapAt(const Offset(105, 470));
    expect(opened, ['https://example.com/bottom']);
    await tester.tapAt(const Offset(105, 800));
    expect(opened.length, 1);
    expect(backgroundTaps, 1);
    await disposeSurface(tester);
  });

  testWidgets('survives very small and very large sizes', (tester) async {
    await pumpSurface(tester);
    conn.emit(codec.encode('中文 ABC █').bytes);
    for (final size in const [Size(1, 1), Size(40, 20), Size(4000, 3000), Size(400, 900)]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tapAt(Offset(size.width / 2, size.height / 2));
      expect(tester.takeException(), isNull);
    }
    await disposeSurface(tester);
  });
}
