// Manual check against the real server: connects, waits for the welcome
// screen, writes it to build/ptt_probe.txt. Does not log in.
import 'dart:io';

import 'package:myptt/core/connection/ws_connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';

Future<void> main() async {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );
  final session = TerminalSession(WsConnection(), codec);
  await session.connect();
  await Future<void>.delayed(const Duration(seconds: 3));

  final lines = [
    for (var r = 0; r < session.screen.rows; r++)
      rowString(session.screen, r, codec),
  ];
  File('build/ptt_probe.txt')
    ..createSync(recursive: true)
    ..writeAsStringSync(lines.join('\n'));

  final ok = lines.any((l) => l.contains('批踢踢'));
  stdout.writeln(ok ? 'OK: welcome screen decoded' : 'FAIL: 批踢踢 not found');
  await session.dispose();
  exit(ok ? 0 : 1);
}
