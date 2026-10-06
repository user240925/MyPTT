import 'dart:typed_data';

class EncodeResult {
  const EncodeResult(this.bytes, this.unmappable);

  final Uint8List bytes;

  /// Number of characters that had no Big5 mapping and were sent as '?'.
  final int unmappable;
}

/// Converts between Big5 (UAO 2.50) and Unicode. The only place in the app
/// that knows about the wire encoding.
class Big5Codec {
  Big5Codec(Uint8List b2u, Uint8List u2b)
      : _b2u = ByteData.sublistView(b2u),
        _u2b = ByteData.sublistView(u2b);

  static const int replacement = 0xFFFD;
  static const int _trailSpan = 0xFE - 0x40 + 1;

  final ByteData _b2u;
  final ByteData _u2b;

  static bool isLead(int b) => b >= 0x81 && b <= 0xFE;
  static bool isTrail(int b) => b >= 0x40 && b <= 0xFE;

  int decodePair(int lead, int trail) {
    if (!isLead(lead) || !isTrail(trail)) return replacement;
    final index = (lead - 0x81) * _trailSpan + (trail - 0x40);
    final v = _b2u.getUint16(index * 2, Endian.little);
    return v == 0 ? replacement : v;
  }

  EncodeResult encode(String text) {
    final out = BytesBuilder();
    var unmappable = 0;
    for (final rune in text.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      final big5 = rune <= 0xFFFF ? _u2b.getUint16(rune * 2, Endian.little) : 0;
      if (big5 == 0) {
        out.addByte(0x3F);
        unmappable++;
      } else {
        out.addByte(big5 >> 8);
        out.addByte(big5 & 0xFF);
      }
    }
    return EncodeResult(out.toBytes(), unmappable);
  }
}
