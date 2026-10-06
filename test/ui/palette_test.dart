import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/ui/palette.dart';

void main() {
  test('palette has sixteen colours', () {
    expect(ansiPalette.length, 16);
  });

  test('default attribute is light grey on black', () {
    expect(foregroundOf(Attr.normal), ansiPalette[7]);
    expect(backgroundOf(Attr.normal), ansiPalette[0]);
  });

  test('bright selects the upper half of the palette for foreground only', () {
    const a = 0x01 | Attr.bright | (4 << Attr.bgShift);
    expect(foregroundOf(a), ansiPalette[9]);
    expect(backgroundOf(a), ansiPalette[4]);
  });

  test('inverse swaps foreground and background', () {
    const a = 0x03 | (4 << Attr.bgShift) | Attr.inverse;
    expect(foregroundOf(a), ansiPalette[4]);
    expect(backgroundOf(a), ansiPalette[3]);
  });
}
