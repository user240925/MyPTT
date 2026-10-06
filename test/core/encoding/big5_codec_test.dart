import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';

Big5Codec loadCodec() => Big5Codec(
      File('assets/uao/b2u.bin').readAsBytesSync(),
      File('assets/uao/u2b.bin').readAsBytesSync(),
    );

String decodeAll(Big5Codec codec, List<int> bytes) {
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] < 0x80) {
      out.writeCharCode(bytes[i]);
    } else {
      out.writeCharCode(codec.decodePair(bytes[i], bytes[i + 1]));
      i++;
    }
  }
  return out.toString();
}

void main() {
  final codec = loadCodec();

  test('decodes common Big5 pairs', () {
    expect(codec.decodePair(0xA4, 0x40), 0x4E00); // 一
    expect(codec.decodePair(0xA4, 0xA4), 0x4E2D); // 中
    expect(codec.decodePair(0xA4, 0xE5), 0x6587); // 文
    expect(codec.decodePair(0xA1, 0x40), 0x3000); // ideographic space
  });

  test('invalid pairs decode to the replacement character', () {
    expect(codec.decodePair(0x41, 0x41), Big5Codec.replacement);
    expect(codec.decodePair(0xA4, 0x20), Big5Codec.replacement);
  });

  test('encodes ASCII and Chinese', () {
    final r = codec.encode('a中');
    expect(r.bytes, [0x61, 0xA4, 0xA4]);
    expect(r.unmappable, 0);
  });

  test('round-trips Chinese, kana, and block characters', () {
    const text = 'PTT 批踢踢實業坊 テストあいう █◢◣─│';
    final r = codec.encode(text);
    expect(r.unmappable, 0);
    expect(decodeAll(codec, r.bytes), text);
  });

  test('unmappable characters become ? and are counted', () {
    final r = codec.encode('a😀b');
    expect(r.bytes, [0x61, 0x3F, 0x62]);
    expect(r.unmappable, 1);
  });
}
