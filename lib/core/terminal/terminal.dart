import 'screen_buffer.dart';

enum _State { ground, escape, csi }

/// Interprets the byte stream from the BBS and applies it to a [ScreenBuffer].
/// Non-control bytes are stored as-is; Big5 decoding happens when a row is read.
class Terminal {
  Terminal(this.screen, {this.onReply});

  final ScreenBuffer screen;

  /// Called with bytes the terminal must send back, such as a cursor report.
  final void Function(List<int> bytes)? onReply;

  int attr = Attr.normal;

  static const int _maxParamBytes = 64;
  static const int _maxParamValue = 9999;

  _State _state = _State.ground;
  final List<int> _params = [];
  int _savedRow = 0;
  int _savedCol = 0;
  int _savedAttr = Attr.normal;

  void feed(List<int> data) {
    for (final b in data) {
      switch (_state) {
        case _State.ground:
          if (b == 0x1B) {
            _state = _State.escape;
          } else if (b < 0x20 || b == 0x7F) {
            _control(b);
          } else {
            screen.put(b, attr);
          }
        case _State.escape:
          _escape(b);
        case _State.csi:
          _csi(b);
      }
    }
  }

  void _control(int b) {
    switch (b) {
      case 0x0D:
        screen.cursorCol = 0;
      case 0x0A:
        screen.lineFeed();
      case 0x08:
        final col =
            screen.cursorCol >= screen.cols ? screen.cols - 1 : screen.cursorCol;
        screen.cursorCol = col > 0 ? col - 1 : 0;
      case 0x09:
        final next = (screen.cursorCol ~/ 8 + 1) * 8;
        screen.cursorCol = next >= screen.cols ? screen.cols - 1 : next;
    }
  }

  void _save() {
    _savedRow = screen.cursorRow;
    _savedCol = screen.cursorCol;
    _savedAttr = attr;
  }

  void _restore() {
    screen.moveTo(_savedRow, _savedCol);
    attr = _savedAttr;
  }

  void _escape(int b) {
    _state = _State.ground;
    switch (b) {
      case 0x5B: // [
        _params.clear();
        _state = _State.csi;
      case 0x1B:
        _state = _State.escape;
      case 0x44: // D
        screen.lineFeed();
      case 0x4D: // M
        screen.reverseLineFeed();
      case 0x45: // E
        screen.cursorCol = 0;
        screen.lineFeed();
      case 0x37: // 7
        _save();
      case 0x38: // 8
        _restore();
    }
  }

  void _csi(int b) {
    if (b == 0x1B) {
      _state = _State.escape;
    } else if (b < 0x20) {
      _control(b);
    } else if (b >= 0x30 && b <= 0x3F) {
      if (_params.length < _maxParamBytes) _params.add(b);
    } else if (b <= 0x2F) {
      // Intermediate byte: not used by any sequence we handle.
    } else {
      _state = _State.ground;
      if (b <= 0x7E) _dispatch(b);
    }
  }

  void _dispatch(int finalByte) {
    final text = String.fromCharCodes(_params);
    // Private-mode sequences such as ESC[?25l are not used by the BBS.
    if (text.startsWith('?') || text.startsWith('>')) return;
    final p = text.isEmpty
        ? const <int>[]
        : text.split(';').map((s) {
            final v = int.tryParse(s) ?? 0;
            return v > _maxParamValue ? _maxParamValue : v;
          }).toList();
    int arg(int i, int fallback) => i < p.length && p[i] != 0 ? p[i] : fallback;
    final row = screen.cursorRow, col = screen.cursorCol;

    switch (String.fromCharCode(finalByte)) {
      case 'm':
        _sgr(p);
      case 'H' || 'f':
        screen.moveTo(arg(0, 1) - 1, arg(1, 1) - 1);
      case 'A':
        screen.moveTo(row - arg(0, 1), col);
      case 'B':
        screen.moveTo(row + arg(0, 1), col);
      case 'C':
        screen.moveTo(row, col + arg(0, 1));
      case 'D':
        screen.moveTo(row, col - arg(0, 1));
      case 'G':
        screen.moveTo(row, arg(0, 1) - 1);
      case 'd':
        screen.moveTo(arg(0, 1) - 1, col);
      case 'J':
        screen.eraseInDisplay(arg(0, 0));
      case 'K':
        screen.eraseInLine(arg(0, 0));
      case 'L':
        screen.insertLines(arg(0, 1));
      case 'M':
        screen.deleteLines(arg(0, 1));
      case '@':
        screen.insertChars(arg(0, 1));
      case 'P':
        screen.deleteChars(arg(0, 1));
      case 'r':
        screen.setScrollRegion(arg(0, 1) - 1, arg(1, screen.rows) - 1);
        screen.moveTo(0, 0);
      case 's':
        _save();
      case 'u':
        _restore();
      case 'n':
        if (arg(0, 0) == 6) {
          final c = col >= screen.cols ? screen.cols - 1 : col;
          onReply?.call('\x1b[${row + 1};${c + 1}R'.codeUnits);
        } else if (arg(0, 0) == 5) {
          onReply?.call('\x1b[0n'.codeUnits);
        }
    }
  }

  void _sgr(List<int> p) {
    if (p.isEmpty) {
      attr = Attr.normal;
      return;
    }
    for (final v in p) {
      if (v == 0) {
        attr = Attr.normal;
      } else if (v == 1) {
        attr |= Attr.bright;
      } else if (v == 4) {
        attr |= Attr.underline;
      } else if (v == 5) {
        attr |= Attr.blink;
      } else if (v == 7) {
        attr |= Attr.inverse;
      } else if (v >= 30 && v <= 37) {
        attr = (attr & ~Attr.fgMask) | (v - 30);
      } else if (v == 39) {
        attr = (attr & ~Attr.fgMask) | Attr.fg(Attr.normal);
      } else if (v >= 40 && v <= 47) {
        attr = (attr & ~Attr.bgMask) | ((v - 40) << Attr.bgShift);
      } else if (v == 49) {
        attr = attr & ~Attr.bgMask;
      }
    }
  }
}
