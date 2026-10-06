import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the iOS app is named MyPTT on the home screen', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    expect(match?.group(1), 'MyPTT');
  });

  test('template text has been replaced', () {
    expect(File('README.md').readAsStringSync(), isNot(contains('A new Flutter project')));
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('A new Flutter project')));
  });

  test('the iOS build guide covers every item that needs a real iPhone', () {
    final guide = File('docs/ios-build.md').readAsStringSync();
    for (final topic in const ['鍵盤', '鑰匙圈', '回到前景', '手勢', '字體']) {
      expect(guide, contains(topic), reason: topic);
    }
    for (final file in const [
      'lib/ui/input_strip.dart',
      'lib/platform/secure_credential_store.dart',
      'lib/ui/session_controller.dart',
      'lib/ui/terminal_surface.dart',
      'lib/ui/terminal_painter.dart',
    ]) {
      expect(guide, contains(file), reason: file);
      expect(File(file).existsSync(), isTrue, reason: file);
    }
  });
}
