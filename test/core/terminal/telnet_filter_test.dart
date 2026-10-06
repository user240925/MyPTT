import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/telnet_filter.dart';

const iac = 255, dont = 254, doo = 253, wont = 252, will = 251, sb = 250, se = 240;
const echo = 1, sga = 3, ttype = 24, naws = 31;

void main() {
  late List<int> data;
  late List<int> replies;
  late TelnetFilter filter;

  setUp(() {
    data = [];
    replies = [];
    filter = TelnetFilter(onData: data.addAll, onReply: replies.addAll);
  });

  test('plain data passes through', () {
    filter.feed([0x41, 0xA4, 0xA4, 0x1B]);
    expect(data, [0x41, 0xA4, 0xA4, 0x1B]);
    expect(replies, isEmpty);
  });

  test('WILL ECHO and WILL SGA are accepted', () {
    filter.feed([iac, will, echo, iac, will, sga]);
    expect(replies, [iac, doo, echo, iac, doo, sga]);
    expect(data, isEmpty);
  });

  test('other WILL options are refused', () {
    filter.feed([iac, will, 5]);
    expect(replies, [iac, dont, 5]);
  });

  test('DO TERMINAL-TYPE is accepted', () {
    filter.feed([iac, doo, ttype]);
    expect(replies, [iac, will, ttype]);
  });

  test('DO NAWS is accepted and followed by the window size', () {
    filter.feed([iac, doo, naws]);
    expect(replies, [iac, will, naws, iac, sb, naws, 0, 80, 0, 24, iac, se]);
  });

  test('other DO options are refused', () {
    filter.feed([iac, doo, 5]);
    expect(replies, [iac, wont, 5]);
  });

  test('WONT and DONT need no reply', () {
    filter.feed([iac, wont, echo, iac, dont, echo, 0x41]);
    expect(replies, isEmpty);
    expect(data, [0x41]);
  });

  test('terminal type request is answered with VT100', () {
    filter.feed([iac, sb, ttype, 1, iac, se]);
    expect(replies, [iac, sb, ttype, 0, ...'VT100'.codeUnits, iac, se]);
  });

  test('escaped IAC becomes a data byte', () {
    filter.feed([0x41, iac, iac, 0x42]);
    expect(data, [0x41, 0xFF, 0x42]);
  });

  test('commands split across feeds are still recognised', () {
    filter.feed([0x41, iac]);
    filter.feed([will]);
    filter.feed([echo, 0x42]);
    expect(data, [0x41, 0x42]);
    expect(replies, [iac, doo, echo]);
  });

  test('unknown commands and unterminated subnegotiation do not throw', () {
    filter.feed([iac, 241, 0x41]);
    expect(data, [0x41]);
    filter.feed([iac, sb, 99, ...List.filled(5000, 7)]);
    filter.feed([iac, se, 0x42]);
    expect(data, [0x41, 0x42]);
  });
}
