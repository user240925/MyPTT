enum _State { data, iac, option, sub, subIac }

/// Strips Telnet commands from the incoming stream and answers negotiation.
class TelnetFilter {
  TelnetFilter({
    required this.onData,
    required this.onReply,
    this.cols = 80,
    this.rows = 24,
  });

  final void Function(List<int> bytes) onData;
  final void Function(List<int> bytes) onReply;
  final int cols;
  final int rows;

  static const int _iac = 255, _dont = 254, _do = 253, _wont = 252, _will = 251;
  static const int _sb = 250, _se = 240;
  static const int _echo = 1, _sga = 3, _ttype = 24, _naws = 31;
  static const int _send = 1, _is = 0;
  static const int _maxSubBytes = 64;

  _State _state = _State.data;
  int _command = 0;
  final List<int> _sub = [];

  /// Forgets any half-received command, for a new connection.
  void reset() {
    _state = _State.data;
    _sub.clear();
  }

  void feed(List<int> input) {
    final out = <int>[];
    for (final b in input) {
      switch (_state) {
        case _State.data:
          if (b == _iac) {
            _state = _State.iac;
          } else {
            out.add(b);
          }
        case _State.iac:
          if (b == _iac) {
            out.add(0xFF);
            _state = _State.data;
          } else if (b == _will || b == _wont || b == _do || b == _dont) {
            _command = b;
            _state = _State.option;
          } else if (b == _sb) {
            _sub.clear();
            _state = _State.sub;
          } else {
            _state = _State.data;
          }
        case _State.option:
          _negotiate(_command, b);
          _state = _State.data;
        case _State.sub:
          if (b == _iac) {
            _state = _State.subIac;
          } else if (_sub.length < _maxSubBytes) {
            _sub.add(b);
          }
        case _State.subIac:
          if (b == _se) {
            _subnegotiation();
            _state = _State.data;
          } else {
            _state = _State.sub;
          }
      }
    }
    if (out.isNotEmpty) onData(out);
  }

  void _negotiate(int command, int option) {
    if (command == _will) {
      final accept = option == _echo || option == _sga;
      onReply([_iac, accept ? _do : _dont, option]);
    } else if (command == _do) {
      if (option == _ttype) {
        onReply([_iac, _will, option]);
      } else if (option == _naws) {
        onReply([_iac, _will, option]);
        onReply([
          _iac, _sb, _naws,
          cols >> 8, cols & 0xFF, rows >> 8, rows & 0xFF,
          _iac, _se,
        ]);
      } else {
        onReply([_iac, _wont, option]);
      }
    }
  }

  void _subnegotiation() {
    if (_sub.length >= 2 && _sub[0] == _ttype && _sub[1] == _send) {
      onReply([_iac, _sb, _ttype, _is, ...'VT100'.codeUnits, _iac, _se]);
    }
  }
}
