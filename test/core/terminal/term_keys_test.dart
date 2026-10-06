import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/term_keys.dart';

void main() {
  test('arrow keys', () {
    expect(bytesForKey(TermKey.up), '\x1b[A'.codeUnits);
    expect(bytesForKey(TermKey.down), '\x1b[B'.codeUnits);
    expect(bytesForKey(TermKey.right), '\x1b[C'.codeUnits);
    expect(bytesForKey(TermKey.left), '\x1b[D'.codeUnits);
  });

  test('editing and navigation keys', () {
    expect(bytesForKey(TermKey.enter), [0x0D]);
    expect(bytesForKey(TermKey.backspace), [0x08]);
    expect(bytesForKey(TermKey.tab), [0x09]);
    expect(bytesForKey(TermKey.escape), [0x1B]);
    expect(bytesForKey(TermKey.home), '\x1b[1~'.codeUnits);
    expect(bytesForKey(TermKey.insert), '\x1b[2~'.codeUnits);
    expect(bytesForKey(TermKey.delete), '\x1b[3~'.codeUnits);
    expect(bytesForKey(TermKey.end), '\x1b[4~'.codeUnits);
    expect(bytesForKey(TermKey.pageUp), '\x1b[5~'.codeUnits);
    expect(bytesForKey(TermKey.pageDown), '\x1b[6~'.codeUnits);
  });

  test('every key has a mapping', () {
    for (final k in TermKey.values) {
      expect(bytesForKey(k), isNotEmpty);
    }
  });

  test('control combinations', () {
    expect(bytesForCtrl('p'), [0x10]);
    expect(bytesForCtrl('X'), [0x18]);
    expect(bytesForCtrl('1'), isNull);
    expect(bytesForCtrl(''), isNull);
    expect(bytesForCtrl('ab'), isNull);
  });
}
