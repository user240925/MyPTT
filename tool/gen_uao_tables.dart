// Generates assets/uao/b2u.bin and u2b.bin from the UAO 2.50 tables at moztw.org.
import 'dart:io';
import 'dart:typed_data';

const _leadMin = 0x81, _leadMax = 0xFE, _trailMin = 0x40, _trailMax = 0xFE;
const _trailSpan = _trailMax - _trailMin + 1;

Future<List<String>> _fetch(String url) async {
  final client = HttpClient();
  final res = await (await client.getUrl(Uri.parse(url))).close();
  if (res.statusCode != 200) {
    throw StateError('HTTP ${res.statusCode} for $url');
  }
  final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  client.close();
  return String.fromCharCodes(bytes).split('\n');
}

// Both source files list "<big5> <unicode>" per line, in hex with a 0x prefix.
Iterable<(int, int)> _rows(List<String> lines) sync* {
  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    yield (int.parse(parts[0]), int.parse(parts[1]));
  }
}

Future<void> main() async {
  const base = 'https://moztw.org/docs/big5/table';

  final b2u = Uint8List((_leadMax - _leadMin + 1) * _trailSpan * 2);
  final b2uView = ByteData.sublistView(b2u);
  for (final (big5, ucs) in _rows(await _fetch('$base/uao250-b2u.txt'))) {
    final lead = big5 >> 8, trail = big5 & 0xFF;
    if (lead < _leadMin || lead > _leadMax) continue;
    if (trail < _trailMin || trail > _trailMax) continue;
    if (ucs > 0xFFFF) continue;
    final index = (lead - _leadMin) * _trailSpan + (trail - _trailMin);
    b2uView.setUint16(index * 2, ucs, Endian.little);
  }

  final u2b = Uint8List(0x10000 * 2);
  final u2bView = ByteData.sublistView(u2b);
  for (final (big5, ucs) in _rows(await _fetch('$base/uao250-u2b.txt'))) {
    if (big5 < 0x8140 || big5 > 0xFEFE) continue;
    if (ucs < 0x80 || ucs > 0xFFFF) continue;
    u2bView.setUint16(ucs * 2, big5, Endian.little);
  }

  Directory('assets/uao').createSync(recursive: true);
  File('assets/uao/b2u.bin').writeAsBytesSync(b2u);
  File('assets/uao/u2b.bin').writeAsBytesSync(u2b);
  stdout.writeln('b2u.bin ${b2u.length} bytes, u2b.bin ${u2b.length} bytes');
}
