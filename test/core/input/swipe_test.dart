import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/input/swipe.dart';
import 'package:myptt/core/terminal/term_keys.dart';

void main() {
  test('classifies the four directions', () {
    expect(classifySwipe(100, 0), Swipe.right);
    expect(classifySwipe(-100, 5), Swipe.left);
    expect(classifySwipe(3, -100), Swipe.up);
    expect(classifySwipe(0, 100), Swipe.down);
  });

  test('short drags are not swipes', () {
    expect(classifySwipe(47, 0), isNull);
    expect(classifySwipe(0, -47), isNull);
    expect(classifySwipe(0, 0), isNull);
  });

  test('diagonal drags are not swipes', () {
    expect(classifySwipe(100, 100), isNull);
    expect(classifySwipe(100, 80), isNull);
    expect(classifySwipe(-60, 50), isNull);
  });

  test('non-finite input is not a swipe', () {
    expect(classifySwipe(double.nan, 100), isNull);
    expect(classifySwipe(100, double.nan), isNull);
    expect(classifySwipe(double.infinity, double.infinity), isNull);
  });

  test('swipes map to BBS navigation keys', () {
    expect(keyForSwipe(Swipe.right), TermKey.left);
    expect(keyForSwipe(Swipe.left), TermKey.right);
    expect(keyForSwipe(Swipe.up), TermKey.pageDown);
    expect(keyForSwipe(Swipe.down), TermKey.pageUp);
  });
}
