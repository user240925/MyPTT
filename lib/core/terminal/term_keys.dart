enum TermKey {
  up, down, right, left,
  enter, backspace, tab, escape,
  home, end, pageUp, pageDown, insert, delete,
}

List<int> bytesForKey(TermKey key) => switch (key) {
      TermKey.up => const [0x1B, 0x5B, 0x41],
      TermKey.down => const [0x1B, 0x5B, 0x42],
      TermKey.right => const [0x1B, 0x5B, 0x43],
      TermKey.left => const [0x1B, 0x5B, 0x44],
      TermKey.enter => const [0x0D],
      TermKey.backspace => const [0x08],
      TermKey.tab => const [0x09],
      TermKey.escape => const [0x1B],
      TermKey.home => const [0x1B, 0x5B, 0x31, 0x7E],
      TermKey.insert => const [0x1B, 0x5B, 0x32, 0x7E],
      TermKey.delete => const [0x1B, 0x5B, 0x33, 0x7E],
      TermKey.end => const [0x1B, 0x5B, 0x34, 0x7E],
      TermKey.pageUp => const [0x1B, 0x5B, 0x35, 0x7E],
      TermKey.pageDown => const [0x1B, 0x5B, 0x36, 0x7E],
    };

/// Bytes for Ctrl plus a letter, or null if [letter] is not a single A–Z letter.
List<int>? bytesForCtrl(String letter) {
  if (letter.length != 1) return null;
  final c = letter.toLowerCase().codeUnitAt(0);
  if (c < 0x61 || c > 0x7A) return null;
  return [c & 0x1F];
}
