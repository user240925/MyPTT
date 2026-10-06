# MyPTT 手機版終端機 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把計畫一的 Windows 終端機變成可在手機上使用的完整 app：觸控手勢、縮放、按鍵列、中文輸入、登入與自動登入、斷線處理、防閒置，並附上在 Mac 上建置的說明。

**Architecture:** 純邏輯（手勢判定、選取與網址偵測、自動登入、防閒置）放在 `lib/core/`，以單元測試驗證。介面拆成四個元件：終端機畫面（手勢與縮放）、輸入列（輸入法與實體鍵盤）、按鍵列、以及把它們組起來並處理斷線與前後景切換的終端機頁。只在 iOS 上才能驗證的行為各自集中在單一檔案。

**Tech Stack:** Flutter stable（Dart 3）、`flutter_secure_storage`（鑰匙圈）、`url_launcher`（開啟連結）。

**Spec:** `docs/superpowers/specs/2026-10-06-myptt-ios-design.md`（第 5、6、8 節，以及第 9 節的步驟 5 到 7）

## Global Constraints

- `lib/core/` 底下為純 Dart，不得 import `package:flutter` 或 `dart:ui`。
- 只新增兩個套件：`flutter_secure_storage` 與 `url_launcher`。
- 密碼只存在鑰匙圈，不寫進一般設定檔，不寫進記錄，不出現在錯誤訊息中。
- 密碼只在游標所在列同時含有「請輸入」與「密碼」時送出，且每次連線最多送一次。
- 自動登入每次連線只嘗試一次；失敗後不重試，交還使用者操作。
- 輸入法組字期間不送出任何資料。
- 手勢對應：向右滑送 ←、向左滑送 →、向上滑送 PageDown、向下滑送 PageUp。
- 縮放以整體畫面縮放的方式進行，不重新排版字形。
- 無法轉成 Big5 的文字，送出前顯示「有 N 個字 PTT 不支援，將以 ? 取代」並等待確認。
- 防閒置的間隔為 3 分鐘，送出的位元組為 `ESC O A ESC O B`（與 PCMan 的預設相同）。
- 所有指令在 repo 根目錄執行，Flutter 位於 `C:\dev\flutter\bin\flutter.bat`（不在 PATH）。
- 每個 Task 結束前執行 `flutter analyze` 與完整的 `flutter test`，皆須通過。
- 介面文字使用繁體中文。
- Commit 訊息結尾加上 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 畫面上其他位置出現「密碼」字樣（例如歡迎畫面的「忘記密碼可參考…」）時，密碼不得送出。（Task 4 測試 `password is not sent to a row that merely mentions it`）
2. 密碼錯誤後 PTT 會再次顯示帳號提示，此時不得再次自動登入。（Task 4 測試 `does not retry after a failed login`）
3. 輸入法組字中，Enter、Backspace 與方向鍵屬於輸入法，不得送到 PTT。（Task 3 測試 `keys pressed while composing are left to the IME`）
4. app 連續多次回到前景，或在連線進行中回到前景，只能有一次連線嘗試；使用者已選擇離線瀏覽時不自動重連。（Task 5 測試 `resuming repeatedly connects once` 與 `resuming in offline mode does not reconnect`）
5. 雙指縮放，以及縮放後的單指拖曳，都不得被當成滑動而送出按鍵。（Task 2 測試 `pinch and panning while zoomed send nothing`）

## File Structure

| 檔案 | 職責 |
|---|---|
| `lib/core/terminal/selection.dart` | 儲存格位置、選取範圍、取出範圍文字、偵測網址 |
| `lib/core/input/swipe.dart` | 判定滑動方向並對應到按鍵 |
| `lib/core/login/credentials.dart` | 帳密資料與儲存介面 |
| `lib/core/login/auto_login.dart` | 自動登入的狀態機 |
| `lib/core/anti_idle.dart` | 防閒置計時 |
| `lib/core/session.dart`（修改） | 區分使用者輸入與自動回覆，提供游標列文字 |
| `lib/ui/terminal_painter.dart`（修改） | 加上游標、選取範圍、過寬字形的壓縮 |
| `lib/ui/terminal_surface.dart` | 終端機畫面：繪製、滑動、縮放、選取複製、點擊網址 |
| `lib/ui/input_strip.dart` | 輸入列：輸入法、實體鍵盤。**iOS 鍵盤行為集中於此** |
| `lib/ui/key_bar.dart` | 常用按鍵列 |
| `lib/ui/session_controller.dart` | 連線、自動登入、防閒置、離線模式、回到前景重連。**重連時機集中於此** |
| `lib/ui/terminal_page.dart` | 終端機頁：組合上述元件與斷線畫面 |
| `lib/ui/login_page.dart` | 登入頁 |
| `lib/platform/secure_credential_store.dart` | 鑰匙圈儲存。**鑰匙圈行為集中於此** |
| `lib/platform/link_opener.dart` | 以系統瀏覽器開啟網址 |
| `lib/ui/terminal_view.dart`（刪除） | 由 `terminal_surface.dart` 與 `input_strip.dart` 取代 |
| `docs/ios-build.md` | Mac 上的建置與檢查步驟 |

---

### Task 1: 選取、網址偵測，以及游標與選取範圍的繪製

**Files:**
- Create: `lib/core/terminal/selection.dart`
- Modify: `lib/ui/terminal_painter.dart`（整個取代）
- Create: `test/support/paint_pixels.dart`
- Test: `test/core/terminal/selection_test.dart`、`test/ui/terminal_painter_test.dart`

**Interfaces:**
- Consumes: `ScreenBuffer`、`Attr`、`glyphsOfRow`、`Big5Codec`、`drawShape`、`foregroundOf`、`backgroundOf`（計畫一）
- Produces:
  - `class CellPos { const CellPos(int row, int col); final int row; final int col; }`（有 `==` 與 `hashCode`）
  - `class Selection { const Selection(CellPos anchor, CellPos focus); CellPos get start; CellPos get end; (int, int)? columnsOnRow(int row, int cols); }`（`start` 不晚於 `end`；`columnsOnRow` 回傳該列被選取的起訖欄，含頭含尾，未選取則為 null）
  - `String textInRange(ScreenBuffer s, Big5Codec codec, Selection sel)`
  - `String? urlAt(ScreenBuffer s, Big5Codec codec, CellPos pos)`
  - `TerminalPainter({required ScreenBuffer screen, required Big5Codec codec, required bool blinkOn, bool showCursor = false, Selection? selection})`
  - 測試輔助 `Future<Color> paintAndReadPixel(WidgetTester tester, CustomPainter painter, Size size, Offset at)`

- [ ] **Step 1: 寫失敗的測試**

`test/core/terminal/selection_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/selection.dart';
import 'package:myptt/core/terminal/terminal.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late ScreenBuffer screen;
  late Terminal term;

  setUp(() {
    screen = ScreenBuffer();
    term = Terminal(screen);
  });

  void feed(String s) => term.feed(codec.encode(s).bytes);

  test('selection orders its ends regardless of drag direction', () {
    const sel = Selection(CellPos(3, 5), CellPos(1, 9));
    expect(sel.start, const CellPos(1, 9));
    expect(sel.end, const CellPos(3, 5));
  });

  test('columnsOnRow covers partial first and last rows', () {
    const sel = Selection(CellPos(1, 9), CellPos(3, 5));
    expect(sel.columnsOnRow(0, 80), isNull);
    expect(sel.columnsOnRow(1, 80), (9, 79));
    expect(sel.columnsOnRow(2, 80), (0, 79));
    expect(sel.columnsOnRow(3, 80), (0, 5));
    expect(sel.columnsOnRow(4, 80), isNull);
  });

  test('text of a single-row range', () {
    feed('Hello World');
    const sel = Selection(CellPos(0, 0), CellPos(0, 4));
    expect(textInRange(screen, codec, sel), 'Hello');
  });

  test('a wide character is included when either half is selected', () {
    feed('A中文B');
    expect(textInRange(screen, codec, const Selection(CellPos(0, 2), CellPos(0, 3))), '中文');
    expect(textInRange(screen, codec, const Selection(CellPos(0, 1), CellPos(0, 1))), '中');
  });

  test('multi-row ranges are joined with newlines and right-trimmed', () {
    feed('first line\r\nsecond\r\nthird line');
    const sel = Selection(CellPos(0, 6), CellPos(2, 4));
    expect(textInRange(screen, codec, sel), 'line\nsecond\nthird');
  });

  test('out-of-range positions are clamped', () {
    feed('abc');
    const sel = Selection(CellPos(-5, -5), CellPos(99, 999));
    expect(textInRange(screen, codec, sel).split('\n').first, 'abc');
  });

  test('urlAt finds the URL under a cell', () {
    feed('see https://www.ptt.cc/bbs/Stock/index.html now');
    expect(urlAt(screen, codec, const CellPos(0, 4)), 'https://www.ptt.cc/bbs/Stock/index.html');
    expect(urlAt(screen, codec, const CellPos(0, 42)), 'https://www.ptt.cc/bbs/Stock/index.html');
    expect(urlAt(screen, codec, const CellPos(0, 0)), isNull);
    expect(urlAt(screen, codec, const CellPos(0, 44)), isNull);
    expect(urlAt(screen, codec, const CellPos(5, 0)), isNull);
  });

  test('urlAt accounts for wide characters before the URL', () {
    feed('網址 http://example.com/a 結束');
    expect(urlAt(screen, codec, const CellPos(0, 5)), 'http://example.com/a');
    expect(urlAt(screen, codec, const CellPos(0, 3)), isNull);
  });

  test('urlAt drops trailing punctuation and stops at non-ASCII', () {
    feed('(https://example.com/x).');
    expect(urlAt(screen, codec, const CellPos(0, 5)), 'https://example.com/x');
    screen.moveTo(1, 0);
    feed('https://example.com/y，後面');
    expect(urlAt(screen, codec, const CellPos(1, 3)), 'https://example.com/y');
  });
}
```

`test/support/paint_pixels.dart`：

```dart
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paints [painter] at [size] and returns the colour of the pixel at [at].
Future<Color> paintAndReadPixel(
  WidgetTester tester,
  CustomPainter painter,
  Size size,
  Offset at,
) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final image = recorder
      .endRecording()
      .toImageSync(size.width.toInt(), size.height.toInt());
  final data = (await tester.runAsync(() => image.toByteData()))!;
  final i = (at.dy.toInt() * image.width + at.dx.toInt()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}
```

`test/ui/terminal_painter_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/selection.dart';
import 'package:myptt/core/terminal/terminal.dart';
import 'package:myptt/ui/terminal_painter.dart';

import '../support/paint_pixels.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  // 80x24 cells of 10x20 pixels.
  const size = Size(800, 480);
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);

  TerminalPainter painter(
    ScreenBuffer screen, {
    bool blinkOn = true,
    bool showCursor = false,
    Selection? selection,
  }) =>
      TerminalPainter(
        screen: screen,
        codec: codec,
        blinkOn: blinkOn,
        showCursor: showCursor,
        selection: selection,
      );

  testWidgets('background colour fills the cell', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed('\x1b[44m \x1b[m'.codeUnits);
    final inCell = await paintAndReadPixel(tester, painter(screen), size, const Offset(5, 10));
    final outside = await paintAndReadPixel(tester, painter(screen), size, const Offset(25, 10));
    expect(inCell, const Color(0xFF000080));
    expect(outside, black);
  });

  testWidgets('the cursor is drawn at the cursor cell when enabled', (tester) async {
    final screen = ScreenBuffer()..moveTo(2, 5);
    const inCursor = Offset(55, 2 * 20 + 19);
    expect(await paintAndReadPixel(tester, painter(screen, showCursor: true), size, inCursor), white);
    expect(await paintAndReadPixel(tester, painter(screen), size, inCursor), black);
    expect(
      await paintAndReadPixel(tester, painter(screen, showCursor: true, blinkOn: false), size, inCursor),
      black,
    );
  });

  testWidgets('a cursor past the last column is drawn in the last column', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed(List.filled(80, 0x20));
    expect(screen.cursorCol, 80);
    final c = await paintAndReadPixel(tester, painter(screen, showCursor: true), size, const Offset(795, 19));
    expect(c, white);
  });

  testWidgets('selected cells are tinted', (tester) async {
    final screen = ScreenBuffer();
    const sel = Selection(CellPos(1, 2), CellPos(1, 4));
    final p = painter(screen, selection: sel);
    expect(await paintAndReadPixel(tester, p, size, const Offset(35, 30)), isNot(black));
    expect(await paintAndReadPixel(tester, p, size, const Offset(55, 30)), black);
    expect(await paintAndReadPixel(tester, p, size, const Offset(35, 10)), black);
  });

  testWidgets('a full block fills its whole cell with no gap', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed([...'\x1b[1;37m'.codeUnits, ...codec.encode('██').bytes]);
    final p = painter(screen);
    for (final x in const [0.0, 19.0, 20.0, 39.0]) {
      expect(await paintAndReadPixel(tester, p, size, Offset(x, 0)), white, reason: 'x=$x top');
      expect(await paintAndReadPixel(tester, p, size, Offset(x, 19)), white, reason: 'x=$x bottom');
    }
  });

  testWidgets('glyphs never paint outside their own cell', (tester) async {
    final screen = ScreenBuffer();
    // A wide Latin letter in column 1; columns 0 and 2 must stay black.
    Terminal(screen).feed(' W '.codeUnits);
    final p = painter(screen);
    for (var y = 0.0; y < 20; y += 3) {
      expect(await paintAndReadPixel(tester, p, size, Offset(8, y)), black, reason: 'left y=$y');
      expect(await paintAndReadPixel(tester, p, size, Offset(21, y)), black, reason: 'right y=$y');
    }
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/selection_test.dart test/ui/terminal_painter_test.dart
```

Expected: FAIL。`selection_test.dart` 找不到 `selection.dart`；`terminal_painter_test.dart` 因 `showCursor` 與 `selection` 參數不存在而無法編譯。

- [ ] **Step 3: 實作選取與網址偵測**

`lib/core/terminal/selection.dart`：

```dart
import '../encoding/big5_codec.dart';
import 'row_glyphs.dart';
import 'screen_buffer.dart';

class CellPos {
  const CellPos(this.row, this.col);

  final int row;
  final int col;

  bool isBefore(CellPos other) =>
      row < other.row || (row == other.row && col < other.col);

  @override
  bool operator ==(Object other) =>
      other is CellPos && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'CellPos($row, $col)';
}

/// A run of cells in reading order between two positions, both inclusive.
class Selection {
  const Selection(this.anchor, this.focus);

  /// Where the selection gesture began.
  final CellPos anchor;

  /// Where the finger currently is.
  final CellPos focus;

  CellPos get start => focus.isBefore(anchor) ? focus : anchor;
  CellPos get end => focus.isBefore(anchor) ? anchor : focus;

  /// First and last selected column on [row], or null if the row is outside.
  (int, int)? columnsOnRow(int row, int cols) {
    final s = start, e = end;
    if (row < s.row || row > e.row) return null;
    return (row == s.row ? s.col : 0, row == e.row ? e.col : cols - 1);
  }
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

CellPos _clampPos(ScreenBuffer s, CellPos p) =>
    CellPos(_clamp(p.row, 0, s.rows - 1), _clamp(p.col, 0, s.cols - 1));

String textInRange(ScreenBuffer s, Big5Codec codec, Selection sel) {
  final clamped = Selection(_clampPos(s, sel.start), _clampPos(s, sel.end));
  final lines = <String>[];
  for (var r = clamped.start.row; r <= clamped.end.row; r++) {
    final (from, to) = clamped.columnsOnRow(r, s.cols)!;
    final line = StringBuffer();
    for (final g in glyphsOfRow(s, r, codec)) {
      if (g.col + g.width - 1 >= from && g.col <= to) {
        line.writeCharCode(g.codePoint);
      }
    }
    lines.add(line.toString().trimRight());
  }
  return lines.join('\n');
}

final RegExp _url = RegExp(r'https?://[\x21-\x7E]+');
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]>]+$');

/// The http(s) URL covering [pos], or null. URLs that wrap onto the next row
/// are not joined.
String? urlAt(ScreenBuffer s, Big5Codec codec, CellPos pos) {
  if (pos.row < 0 || pos.row >= s.rows) return null;
  final text = StringBuffer();
  // First and last column of each character in [text].
  final firstCol = <int>[];
  final lastCol = <int>[];
  for (final g in glyphsOfRow(s, pos.row, codec)) {
    // Keep one UTF-16 unit per glyph so string indices match the lists.
    text.writeCharCode(g.codePoint > 0xFFFF ? Big5Codec.replacement : g.codePoint);
    firstCol.add(g.col);
    lastCol.add(g.col + g.width - 1);
  }
  for (final m in _url.allMatches(text.toString())) {
    final url = m.group(0)!.replaceFirst(_trailingPunctuation, '');
    if (url.isEmpty) continue;
    final endIndex = m.start + url.length - 1;
    if (pos.col >= firstCol[m.start] && pos.col <= lastCol[endIndex]) return url;
  }
  return null;
}
```

- [ ] **Step 4: 實作游標、選取範圍與過寬字形的壓縮**

`lib/ui/terminal_painter.dart`（整個取代）：

```dart
import 'package:flutter/widgets.dart';

import '../core/encoding/big5_codec.dart';
import '../core/terminal/row_glyphs.dart';
import '../core/terminal/screen_buffer.dart';
import '../core/terminal/selection.dart';
import 'glyph_shapes.dart';
import 'palette.dart';

/// Paints a [ScreenBuffer]. Every glyph is drawn inside its own cell, so
/// column alignment does not depend on the font's advance widths.
class TerminalPainter extends CustomPainter {
  TerminalPainter({
    required this.screen,
    required this.codec,
    required this.blinkOn,
    this.showCursor = false,
    this.selection,
  });

  final ScreenBuffer screen;
  final Big5Codec codec;

  /// Whether blinking text and the cursor are in their visible phase.
  final bool blinkOn;
  final bool showCursor;
  final Selection? selection;

  static const Color _cursorColor = Color(0xFFFFFFFF);
  static const Color _selectionColor = Color(0x804488FF);

  /// Fraction of the cell height taken by the underline cursor.
  static const double _cursorHeight = 0.15;
  static const int _maxCachedGlyphs = 4000;
  static const List<String> _fonts = [
    'MingLiU', 'Microsoft JhengHei', 'PingFang TC', 'Heiti TC', 'monospace',
  ];
  static final Map<(int, Color, double), TextPainter> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / screen.cols, ch = size.height / screen.rows;
    if (cw <= 0 || ch <= 0) return;
    final fill = Paint()..isAntiAlias = false;

    for (var r = 0; r < screen.rows; r++) {
      final top = r * ch;

      var start = 0;
      while (start < screen.cols) {
        final bg = backgroundOf(screen.attrAt(r, start));
        var end = start + 1;
        while (end < screen.cols && backgroundOf(screen.attrAt(r, end)) == bg) {
          end++;
        }
        // Overdraw by half a pixel so rounding never leaves a seam.
        canvas.drawRect(
          Rect.fromLTRB(start * cw, top, end * cw + 0.5, top + ch + 0.5),
          fill..color = bg,
        );
        start = end;
      }

      for (final g in glyphsOfRow(screen, r, codec)) {
        if (g.codePoint == 0x20 || g.codePoint == 0x3000) continue;
        final box = Rect.fromLTWH(g.col * cw, top, g.width * cw, ch);
        final left = _visibleFg(g.leftAttr), right = _visibleFg(g.rightAttr);
        if (g.width == 1 || left == right) {
          _drawClipped(canvas, box, g.codePoint, left, box);
        } else {
          final mid = box.left + cw;
          _drawClipped(canvas, box, g.codePoint, left,
              Rect.fromLTRB(box.left, box.top, mid, box.bottom));
          _drawClipped(canvas, box, g.codePoint, right,
              Rect.fromLTRB(mid, box.top, box.right, box.bottom));
        }
      }

      final selected = selection?.columnsOnRow(r, screen.cols);
      if (selected != null) {
        final (from, to) = selected;
        canvas.drawRect(
          Rect.fromLTRB(from * cw, top, (to + 1) * cw, top + ch),
          fill..color = _selectionColor,
        );
      }
    }

    if (showCursor && blinkOn) {
      final col =
          screen.cursorCol >= screen.cols ? screen.cols - 1 : screen.cursorCol;
      final h = ch * _cursorHeight;
      canvas.drawRect(
        Rect.fromLTWH(col * cw, (screen.cursorRow + 1) * ch - h, cw, h),
        fill..color = _cursorColor,
      );
    }
  }

  Color? _visibleFg(int attr) =>
      (attr & Attr.blink) != 0 && !blinkOn ? null : foregroundOf(attr);

  /// Draws the glyph laid out in [box] but only inside [clip], so a glyph
  /// can never spill into a neighbouring cell.
  void _drawClipped(Canvas canvas, Rect box, int cp, Color? color, Rect clip) {
    if (color == null) return;
    canvas.save();
    canvas.clipRect(clip);
    if (!drawShape(canvas, box, cp, color)) _drawText(canvas, box, cp, color);
    canvas.restore();
  }

  void _drawText(Canvas canvas, Rect box, int cp, Color color) {
    final fontSize = box.height * 0.82;
    if (fontSize < 1) return;
    final tp = _painterFor(cp, color, fontSize);
    final dy = box.top + (box.height - tp.height) / 2;
    if (tp.width <= box.width) {
      tp.paint(canvas, Offset(box.left + (box.width - tp.width) / 2, dy));
      return;
    }
    // Squeeze glyphs from proportional fallback fonts that are wider than
    // the cell.
    canvas.save();
    canvas.translate(box.left, dy);
    canvas.scale(box.width / tp.width, 1);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  TextPainter _painterFor(int cp, Color color, double fontSize) {
    final key = (cp, color, fontSize);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _maxCachedGlyphs) {
      for (final p in _cache.values) {
        p.dispose();
      }
      _cache.clear();
    }
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(cp),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1,
          fontFamilyFallback: _fonts,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cache[key] = tp;
  }

  @override
  bool shouldRepaint(TerminalPainter oldDelegate) => true;
}
```

- [ ] **Step 5: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/selection_test.dart test/ui/terminal_painter_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/core/terminal/selection.dart lib/ui/terminal_painter.dart test/core/terminal/selection_test.dart test/ui/terminal_painter_test.dart test/support/paint_pixels.dart
git commit -m "feat: add selection, URL detection, cursor and selection painting"
```

---

### Task 2: 終端機畫面的手勢、縮放、選取複製、點擊網址

**Files:**
- Create: `lib/core/input/swipe.dart`
- Create: `lib/ui/terminal_surface.dart`
- Test: `test/core/input/swipe_test.dart`、`test/ui/terminal_surface_test.dart`

**Interfaces:**
- Consumes: `TerminalSession`、`TermKey`、`bytesForKey`、`FakeConnection`（計畫一）；`CellPos`、`Selection`、`textInRange`、`urlAt`、`TerminalPainter`（Task 1）
- Produces:
  - `enum Swipe { left, right, up, down }`
  - `Swipe? classifySwipe(double dx, double dy, {double minDistance = 48})`
  - `TermKey keyForSwipe(Swipe swipe)`
  - `class TerminalSurface extends StatefulWidget { const TerminalSurface({super.key, required TerminalSession session, bool inputEnabled = true, VoidCallback? onTapBackground, ValueChanged<String>? onOpenUrl, ValueChanged<String>? onCopied}); }`
  - 縮放用的元件帶有 `Key('terminal-zoom')`，測試可由此讀取目前倍率。

行為：

| 手勢 | 結果 |
|---|---|
| 單指滑動（未放大時） | 依方向送出按鍵；`inputEnabled` 為 false 時不送 |
| 雙指 | 縮放，1 到 4 倍，不送出任何按鍵 |
| 單指拖曳（已放大時） | 平移畫面，不送出任何按鍵 |
| 點一下網址 | 呼叫 `onOpenUrl` |
| 點一下其他位置 | 有選取範圍時清除選取；否則呼叫 `onTapBackground` |
| 長按並拖曳 | 選取文字，放開時複製到剪貼簿並呼叫 `onCopied` |

- [ ] **Step 1: 寫失敗的測試**

`test/core/input/swipe_test.dart`：

```dart
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
```

`test/ui/terminal_surface_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/terminal_surface.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late List<String> opened;
  late List<String> copied;
  late int backgroundTaps;
  String? clipboard;

  // The surface is exactly 800x480: 80x24 cells of 10x20 pixels.
  Future<void> pumpSurface(WidgetTester tester, {bool inputEnabled = true}) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    clipboard = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    opened = [];
    copied = [];
    backgroundTaps = 0;
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalSurface(
          session: session,
          inputEnabled: inputEnabled,
          onTapBackground: () => backgroundTaps++,
          onOpenUrl: opened.add,
          onCopied: copied.add,
        ),
      ),
    ));
  }

  Future<void> disposeSurface(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(session.dispose);
  }

  /// Moves two fingers between the given x positions in small steps, the
  /// way a real pinch arrives, and leaves both fingers down.
  Future<(TestGesture, TestGesture)> pinch(
    WidgetTester tester, {
    required (double, double) from,
    required (double, double) to,
  }) async {
    const y = 240.0, steps = 10;
    final a = await tester.startGesture(Offset(from.$1, y));
    final b = await tester.startGesture(Offset(from.$2, y));
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      await a.moveTo(Offset(from.$1 + (to.$1 - from.$1) * t, y));
      await b.moveTo(Offset(from.$2 + (to.$2 - from.$2) * t, y));
    }
    await tester.pump();
    return (a, b);
  }

  double zoom(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const Key('terminal-zoom')))
      .transform
      .getMaxScaleOnAxis();

  testWidgets('one-finger swipes send navigation keys', (tester) async {
    await pumpSurface(tester);
    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    expect(conn.sent, '\x1b[D'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 240), const Offset(-200, 0));
    expect(conn.sent, '\x1b[C'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 300), const Offset(0, -200));
    expect(conn.sent, '\x1b[6~'.codeUnits);
    conn.sent.clear();
    await tester.dragFrom(const Offset(400, 100), const Offset(0, 200));
    expect(conn.sent, '\x1b[5~'.codeUnits);
    await disposeSurface(tester);
  });

  testWidgets('short and diagonal drags send nothing', (tester) async {
    await pumpSurface(tester);
    await tester.dragFrom(const Offset(400, 240), const Offset(30, 0));
    await tester.dragFrom(const Offset(400, 240), const Offset(150, 150));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('swipes send nothing when input is disabled', (tester) async {
    await pumpSurface(tester, inputEnabled: false);
    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  // Review Focus 5
  testWidgets('pinch and panning while zoomed send nothing', (tester) async {
    await pumpSurface(tester);
    expect(zoom(tester), closeTo(1, 0.001));

    final (a, b) = await pinch(tester, from: (300, 500), to: (150, 650));
    await a.up();
    // The remaining finger keeps moving after the other lifts.
    await b.moveTo(const Offset(650, 440));
    await b.up();
    await tester.pump();
    expect(zoom(tester), greaterThan(1.5));
    expect(conn.sent, isEmpty);

    await tester.dragFrom(const Offset(400, 240), const Offset(200, 0));
    await tester.dragFrom(const Offset(400, 240), const Offset(0, -200));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(zoom(tester), greaterThan(1.5));
    await disposeSurface(tester);
  });

  testWidgets('zoom is limited to between 1x and 4x', (tester) async {
    await pumpSurface(tester);
    var (a, b) = await pinch(tester, from: (390, 410), to: (10, 790));
    await a.up();
    await b.up();
    await tester.pump();
    expect(zoom(tester), closeTo(4, 0.001));

    (a, b) = await pinch(tester, from: (10, 790), to: (399, 401));
    await a.up();
    await b.up();
    await tester.pump();
    expect(zoom(tester), closeTo(1, 0.001));
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('tapping a URL opens it; tapping elsewhere reports a background tap',
      (tester) async {
    await pumpSurface(tester);
    conn.emit('see https://example.com/a now'.codeUnits);
    await tester.pump();

    await tester.tapAt(const Offset(105, 10));
    expect(opened, ['https://example.com/a']);
    expect(backgroundTaps, 0);

    await tester.tapAt(const Offset(5, 10));
    await tester.tapAt(const Offset(400, 300));
    expect(opened.length, 1);
    expect(backgroundTaps, 2);
    expect(conn.sent, isEmpty);
    await disposeSurface(tester);
  });

  testWidgets('long-press drag selects and copies text', (tester) async {
    await pumpSurface(tester);
    conn.emit(codec.encode('Hello 中文 World').bytes);
    await tester.pump();

    final g = await tester.startGesture(const Offset(5, 10));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(const Offset(95, 10));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(clipboard, 'Hello 中文');
    expect(copied, ['Hello 中文']);
    expect(conn.sent, isEmpty);

    // The next tap only clears the selection.
    await tester.tapAt(const Offset(400, 300));
    expect(backgroundTaps, 0);
    await tester.tapAt(const Offset(400, 300));
    expect(backgroundTaps, 1);
    await disposeSurface(tester);
  });

  testWidgets('survives very small and very large sizes', (tester) async {
    await pumpSurface(tester);
    conn.emit(codec.encode('中文 ABC █').bytes);
    for (final size in const [Size(1, 1), Size(40, 20), Size(4000, 3000), Size(400, 900)]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tapAt(Offset(size.width / 2, size.height / 2));
      expect(tester.takeException(), isNull);
    }
    await disposeSurface(tester);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/input/swipe_test.dart test/ui/terminal_surface_test.dart
```

Expected: FAIL，訊息為找不到 `swipe.dart` 與 `terminal_surface.dart`。

- [ ] **Step 3: 實作滑動判定**

`lib/core/input/swipe.dart`：

```dart
import '../terminal/term_keys.dart';

enum Swipe { left, right, up, down }

/// How much longer the main axis must be than the other for a drag to count
/// as a swipe, so a diagonal drag is not misread.
const double _dominance = 1.5;

/// Classifies a finished one-finger drag by its total displacement, or
/// returns null if it is too short or too diagonal.
Swipe? classifySwipe(double dx, double dy, {double minDistance = 48}) {
  if (!dx.isFinite || !dy.isFinite) return null;
  final ax = dx.abs(), ay = dy.abs();
  if (ax < minDistance && ay < minDistance) return null;
  if (ax >= ay * _dominance) return dx > 0 ? Swipe.right : Swipe.left;
  if (ay >= ax * _dominance) return dy > 0 ? Swipe.down : Swipe.up;
  return null;
}

/// Swiping right goes back, left enters, up and down page through content.
TermKey keyForSwipe(Swipe swipe) => switch (swipe) {
      Swipe.right => TermKey.left,
      Swipe.left => TermKey.right,
      Swipe.up => TermKey.pageDown,
      Swipe.down => TermKey.pageUp,
    };
```

- [ ] **Step 4: 實作終端機畫面**

`lib/ui/terminal_surface.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/connection/connection.dart';
import '../core/input/swipe.dart';
import '../core/session.dart';
import '../core/terminal/selection.dart';
import '../core/terminal/term_keys.dart';
import 'terminal_painter.dart';

/// Draws the terminal and turns touch gestures into keys, zoom, selection,
/// and link taps.
class TerminalSurface extends StatefulWidget {
  const TerminalSurface({
    super.key,
    required this.session,
    this.inputEnabled = true,
    this.onTapBackground,
    this.onOpenUrl,
    this.onCopied,
  });

  final TerminalSession session;

  /// When false, swipes do not send keys.
  final bool inputEnabled;
  final VoidCallback? onTapBackground;
  final ValueChanged<String>? onOpenUrl;
  final ValueChanged<String>? onCopied;

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  static const Duration _blinkInterval = Duration(milliseconds: 600);

  /// 80 columns of 1:2 cells by 24 rows.
  static const double _aspectRatio = 80 / (24 * 2);
  static const double _maxScale = 4;

  /// Below this the view snaps back to exactly 1x.
  static const double _snapScale = 1.05;

  late final StreamSubscription<void> _updates;
  late final Timer _blink;
  bool _blinkOn = true;

  /// Size and top-left corner of the unzoomed terminal within this widget.
  Size _size = Size.zero;
  Offset _origin = Offset.zero;

  double _scale = 1;
  Offset _offset = Offset.zero;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  // Swipes are measured from raw pointer positions, touch-down to lift-off,
  // because the scale recognizer only reports movement after its slop.
  int _pointers = 0;
  int? _firstPointer;
  Offset _downPosition = Offset.zero;
  Offset _lastPosition = Offset.zero;
  double _scaleAtDown = 1;

  /// True from the moment a second finger touches until every finger lifts.
  bool _hadMultiTouch = false;

  /// True while a long-press selection is in progress.
  bool _selecting = false;
  Selection? _selection;

  @override
  void initState() {
    super.initState();
    _updates = widget.session.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _blink = Timer.periodic(_blinkInterval, (_) {
      if (mounted) setState(() => _blinkOn = !_blinkOn);
    });
  }

  @override
  void dispose() {
    _blink.cancel();
    _updates.cancel();
    super.dispose();
  }

  Offset _clampOffset(Offset o, double scale) {
    final minX = _size.width * (1 - scale), minY = _size.height * (1 - scale);
    return Offset(
      o.dx.clamp(minX, 0.0).toDouble(),
      o.dy.clamp(minY, 0.0).toDouble(),
    );
  }

  CellPos _cellAt(Offset local) {
    final screen = widget.session.screen;
    final cw = _size.width / screen.cols, ch = _size.height / screen.rows;
    if (cw <= 0 || ch <= 0) return const CellPos(0, 0);
    final p = (local - _origin - _offset) / _scale;
    int cell(double v, int count) {
      if (!v.isFinite) return 0;
      final i = v.floor();
      return i < 0 ? 0 : (i >= count ? count - 1 : i);
    }

    return CellPos(cell(p.dy / ch, screen.rows), cell(p.dx / cw, screen.cols));
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _firstPointer = e.pointer;
      _downPosition = _lastPosition = e.localPosition;
      _scaleAtDown = _scale;
      _hadMultiTouch = false;
      _selecting = false;
    } else {
      _hadMultiTouch = true;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer == _firstPointer) _lastPosition = e.localPosition;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer == _firstPointer) _lastPosition = e.localPosition;
    if (_pointers > 0) _pointers--;
    if (_pointers > 0) return;
    final plainDrag = !_hadMultiTouch && !_selecting && _scaleAtDown == 1;
    if (!plainDrag || !widget.inputEnabled) return;
    final drag = _lastPosition - _downPosition;
    final swipe = classifySwipe(drag.dx, drag.dy);
    if (swipe != null) {
      widget.session.sendBytes(bytesForKey(keyForSwipe(swipe)));
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_pointers > 0) _pointers--;
    // A cancelled touch must never end up as a swipe.
    _hadMultiTouch = true;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      final scale = (_startScale * d.scale).clamp(1.0, _maxScale).toDouble();
      // Keep the point under the fingers fixed while zooming.
      final anchor = (_startFocal - _origin - _startOffset) / _startScale;
      final offset = d.localFocalPoint - _origin - anchor * scale;
      setState(() {
        _scale = scale;
        _offset = _clampOffset(offset, scale);
      });
    } else if (_scale > 1) {
      setState(() {
        _offset = _clampOffset(
          _startOffset + (d.localFocalPoint - _startFocal),
          _scale,
        );
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return;
    if (_scale < _snapScale && (_scale != 1 || _offset != Offset.zero)) {
      setState(() {
        _scale = 1;
        _offset = Offset.zero;
      });
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (_selection != null) {
      setState(() => _selection = null);
      return;
    }
    final session = widget.session;
    final url = urlAt(session.screen, session.codec, _cellAt(d.localPosition));
    if (url != null) {
      widget.onOpenUrl?.call(url);
    } else {
      widget.onTapBackground?.call();
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _selecting = true;
    final cell = _cellAt(d.localPosition);
    setState(() => _selection = Selection(cell, cell));
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final anchor = _selection?.anchor;
    if (anchor == null) return;
    setState(() => _selection = Selection(anchor, _cellAt(d.localPosition)));
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final selection = _selection;
    if (selection == null) return;
    final session = widget.session;
    final text = textInRange(session.screen, session.codec, selection);
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    widget.onCopied?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        var w = constraints.maxWidth, h = w / _aspectRatio;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * _aspectRatio;
        }
        _size = Size(w, h);
        _origin = Offset((constraints.maxWidth - w) / 2, 0);
        _offset = _clampOffset(_offset, _scale);

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onTapUp: _onTapUp,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          child: ColoredBox(
            color: Colors.black,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: w,
                height: h,
                child: ClipRect(
                  child: Transform.translate(
                    offset: _offset,
                    child: Transform.scale(
                      key: const Key('terminal-zoom'),
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: CustomPaint(
                        size: _size,
                        painter: TerminalPainter(
                          screen: session.screen,
                          codec: session.codec,
                          blinkOn: _blinkOn,
                          showCursor:
                              session.status == ConnectionStatus.connected,
                          selection: _selection,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
```

寫入後執行 `dart format lib/ui/terminal_surface.dart` 整理縮排。

- [ ] **Step 5: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/input/swipe_test.dart test/ui/terminal_surface_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/core/input lib/ui/terminal_surface.dart test/core/input test/ui/terminal_surface_test.dart
git commit -m "feat: add terminal surface with swipe, zoom, selection, and link taps"
```

---

### Task 3: 輸入列與按鍵列

**Files:**
- Modify: `lib/core/session.dart`（整個取代）
- Create: `lib/ui/input_strip.dart`
- Create: `lib/ui/key_bar.dart`
- Modify: `test/core/session_test.dart`（新增兩個測試）
- Test: `test/ui/input_strip_test.dart`、`test/ui/key_bar_test.dart`

**Interfaces:**
- Consumes: `TerminalSession`、`TermKey`、`bytesForKey`、`bytesForCtrl`、`rowString`、`FakeConnection`（計畫一）
- Produces:
  - `TerminalSession` 新增：`Stream<void> get userActivity`（使用者送出資料時觸發，自動回覆不觸發）；`String get cursorRowText`；`sendBytes(List<int> bytes, {bool userInitiated = true})`。其餘簽章不變。
  - `class InputStrip extends StatefulWidget { const InputStrip({super.key, required TerminalSession session, required FocusNode focusNode, required ValueNotifier<bool> ctrlLatch}); }`
  - `class KeyBar extends StatelessWidget { const KeyBar({super.key, required TerminalSession session, required ValueNotifier<bool> ctrlLatch}); }`
  - `ctrlLatch` 為 true 時，輸入列收到的下一個英文字母以 Ctrl 組合送出，然後自動變回 false。

輸入列的運作方式：文字欄位裡固定放一個看不見的佔位字元。使用者輸入的文字在輸入法選字完成後立刻送出並清空欄位；佔位字元被刪掉代表按了 Backspace。實體鍵盤的方向鍵、Enter 等由外層攔截後直接送出。

- [ ] **Step 1: 寫失敗的測試**

在 `test/core/session_test.dart` 的 `the placeholder recogniser reports unknown` 測試之前加入：

```dart
  test('user sends fire userActivity; automatic replies do not', () async {
    var activity = 0;
    session.userActivity.listen((_) => activity++);
    await session.connect();
    conn.emit([255, 253, 31]);
    conn.emit('\x1b[6n'.codeUnits);
    expect(activity, 0);
    session.sendBytes([0x41]);
    session.sendText('中');
    expect(activity, 2);
    session.sendBytes([0x42], userInitiated: false);
    expect(activity, 2);
    expect(conn.sent.last, 0x42);
  });

  test('cursorRowText is the text of the row the cursor is on', () async {
    await session.connect();
    conn.emit(codec.encode('first\r\n請輸入代號: ').bytes);
    expect(session.cursorRowText, '請輸入代號:');
  });
```

`test/ui/input_strip_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/input_strip.dart';

import '../support/fake_connection.dart';

const sentinel = '\u200B';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late FocusNode focus;
  late ValueNotifier<bool> ctrl;

  Future<void> pumpStrip(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    focus = FocusNode();
    ctrl = ValueNotifier(false);
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InputStrip(session: session, focusNode: focus, ctrlLatch: ctrl),
      ),
    ));
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
  }

  Future<void> disposeStrip(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    ctrl.dispose();
    await tester.runAsync(session.dispose);
  }

  TextEditingValue value(String text, {TextRange composing = TextRange.empty}) =>
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: composing,
      );

  testWidgets('committed text is sent immediately as Big5', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('${sentinel}a'));
    expect(conn.sent, [0x61]);
    conn.sent.clear();
    tester.testTextInput.updateEditingValue(value('$sentinel中文'));
    expect(conn.sent, [0xA4, 0xA4, 0xA4, 0xE5]);
    await disposeStrip(tester);
  });

  testWidgets('nothing is sent while the IME is composing', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(
      value('$sentinelㄓㄨ', composing: const TextRange(start: 1, end: 3)),
    );
    expect(conn.sent, isEmpty);
    tester.testTextInput.updateEditingValue(value('$sentinel中'));
    expect(conn.sent, [0xA4, 0xA4]);
    await disposeStrip(tester);
  });

  // Review Focus 3
  testWidgets('keys pressed while composing are left to the IME', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(
      value('$sentinelㄓ', composing: const TextRange(start: 1, end: 2)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(conn.sent, isEmpty);
    await disposeStrip(tester);
  });

  testWidgets('deleting the placeholder sends Backspace', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value(''));
    expect(conn.sent, [0x08]);
    tester.testTextInput.updateEditingValue(value(''));
    expect(conn.sent, [0x08, 0x08]);
    await disposeStrip(tester);
  });

  testWidgets('the keyboard action key sends Enter and keeps focus', (tester) async {
    await pumpStrip(tester);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(conn.sent, [0x0D]);
    expect(focus.hasFocus, isTrue);
    await disposeStrip(tester);
  });

  testWidgets('hardware special keys are sent once each', (tester) async {
    await pumpStrip(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(conn.sent, [...'\x1b[A'.codeUnits, 0x0D, 0x08, ...'\x1b[6~'.codeUnits]);

    conn.sent.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(conn.sent, [0x10]);
    await disposeStrip(tester);
  });

  testWidgets('Ctrl latch applies to the next letter only', (tester) async {
    await pumpStrip(tester);
    ctrl.value = true;
    tester.testTextInput.updateEditingValue(value('${sentinel}x'));
    expect(conn.sent, [0x18]);
    expect(ctrl.value, isFalse);
    tester.testTextInput.updateEditingValue(value('${sentinel}x'));
    expect(conn.sent, [0x18, 0x78]);
    await disposeStrip(tester);
  });

  testWidgets('Ctrl latch is released by text that is not a single letter',
      (tester) async {
    await pumpStrip(tester);
    ctrl.value = true;
    tester.testTextInput.updateEditingValue(value('$sentinel中'));
    expect(conn.sent, [0xA4, 0xA4]);
    expect(ctrl.value, isFalse);
    await disposeStrip(tester);
  });

  testWidgets('unsupported characters wait for confirmation', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('${sentinel}a😀b😀'));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(find.text('有 2 個字 PTT 不支援，將以 ? 取代'), findsOneWidget);

    await tester.tap(find.text('送出'));
    await tester.pump();
    expect(conn.sent, [0x61, 0x3F, 0x62, 0x3F]);
    expect(find.textContaining('PTT 不支援'), findsNothing);
    await disposeStrip(tester);
  });

  testWidgets('cancelling unsupported text sends nothing', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('$sentinel😀'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(find.textContaining('PTT 不支援'), findsNothing);
    await disposeStrip(tester);
  });
}
```

`test/ui/key_bar_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/key_bar.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late ValueNotifier<bool> ctrl;

  Future<void> pumpBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    ctrl = ValueNotifier(false);
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KeyBar(session: session, ctrlLatch: ctrl)),
    ));
  }

  Future<void> disposeBar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    await tester.runAsync(session.dispose);
  }

  testWidgets('each key sends its bytes', (tester) async {
    await pumpBar(tester);
    const expected = {
      '←': '\x1b[D', '↑': '\x1b[A', '↓': '\x1b[B', '→': '\x1b[C',
      'Enter': '\r', 'PgUp': '\x1b[5~', 'PgDn': '\x1b[6~',
      'Home': '\x1b[1~', 'End': '\x1b[4~', 'Esc': '\x1b', 'Tab': '\t',
    };
    for (final entry in expected.entries) {
      conn.sent.clear();
      await tester.tap(find.text(entry.key));
      expect(conn.sent, entry.value.codeUnits, reason: entry.key);
    }
    await disposeBar(tester);
  });

  testWidgets('Ctrl toggles the latch and sends nothing itself', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Ctrl'));
    expect(ctrl.value, isTrue);
    await tester.tap(find.text('Ctrl'));
    expect(ctrl.value, isFalse);
    expect(conn.sent, isEmpty);
    await disposeBar(tester);
  });

  testWidgets('tapping a key does not take keyboard focus', (tester) async {
    await pumpBar(tester);
    final field = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextField(focusNode: field, autofocus: true),
          KeyBar(session: session, ctrlLatch: ctrl),
        ]),
      ),
    ));
    await tester.pump();
    expect(field.hasFocus, isTrue);
    await tester.tap(find.text('↑'));
    await tester.pump();
    expect(field.hasFocus, isTrue);
    field.dispose();
    await disposeBar(tester);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/session_test.dart test/ui/input_strip_test.dart test/ui/key_bar_test.dart
```

Expected: FAIL。`session_test.dart` 因 `userActivity`、`cursorRowText` 不存在而無法編譯；另外兩個找不到 `input_strip.dart` 與 `key_bar.dart`。

- [ ] **Step 3: 修改工作階段**

`lib/core/session.dart`（整個取代）：

```dart
import 'dart:async';

import 'connection/connection.dart';
import 'encoding/big5_codec.dart';
import 'terminal/row_glyphs.dart';
import 'terminal/screen_buffer.dart';
import 'terminal/telnet_filter.dart';
import 'terminal/terminal.dart';

/// Wires a [Connection] to a terminal and exposes the resulting screen.
class TerminalSession {
  TerminalSession(this.connection, this.codec, {int cols = 80, int rows = 24})
      : screen = ScreenBuffer(cols: cols, rows: rows) {
    _terminal = Terminal(screen, onReply: _reply);
    _telnet = TelnetFilter(
      onData: (bytes) {
        _terminal.feed(bytes);
        _updates.add(null);
      },
      onReply: _reply,
      cols: cols,
      rows: rows,
    );
    _dataSub = connection.data.listen(_telnet.feed);
    _statusSub = connection.statusChanges.listen((_) => _updates.add(null));
  }

  final Connection connection;
  final Big5Codec codec;
  final ScreenBuffer screen;

  late final Terminal _terminal;
  late final TelnetFilter _telnet;
  late final StreamSubscription<void> _dataSub;
  late final StreamSubscription<void> _statusSub;
  final _updates = StreamController<void>.broadcast(sync: true);
  final _userActivity = StreamController<void>.broadcast(sync: true);

  ConnectionStatus get status => connection.status;

  /// Fires whenever the screen content or the connection status changes.
  Stream<void> get updates => _updates.stream;

  /// Fires when the user sends something; protocol replies and keep-alives
  /// do not count.
  Stream<void> get userActivity => _userActivity.stream;

  /// Text of the row the cursor is on, without trailing spaces.
  String get cursorRowText => rowString(screen, screen.cursorRow, codec);

  /// Starts a new connection from a blank terminal. Does nothing if a
  /// connection is already open or in progress.
  Future<void> connect() async {
    if (connection.status != ConnectionStatus.disconnected) return;
    _terminal.reset();
    _telnet.reset();
    await connection.connect();
  }

  void _reply(List<int> bytes) => sendBytes(bytes, userInitiated: false);

  void sendBytes(List<int> bytes, {bool userInitiated = true}) {
    if (connection.status != ConnectionStatus.connected) return;
    connection.send(bytes);
    if (userInitiated) _userActivity.add(null);
  }

  /// Returns the number of characters that had no Big5 mapping.
  int sendText(String text) {
    if (connection.status != ConnectionStatus.connected) return 0;
    final encoded = codec.encode(text);
    connection.send(encoded.bytes);
    _userActivity.add(null);
    return encoded.unmappable;
  }

  /// Starts every teardown step immediately, so the connection is closed
  /// even if the caller never awaits the result.
  Future<void> dispose() async {
    await Future.wait([
      _dataSub.cancel(),
      _statusSub.cancel(),
      connection.close(),
      _updates.close(),
      _userActivity.close(),
    ]);
  }
}
```

- [ ] **Step 4: 實作輸入列**

`lib/ui/input_strip.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';

/// The text field that receives the system keyboard, IME, and hardware keys
/// and forwards them to the BBS.
///
/// iOS keyboard behaviour that cannot be checked on Windows lives here.
class InputStrip extends StatefulWidget {
  const InputStrip({
    super.key,
    required this.session,
    required this.focusNode,
    required this.ctrlLatch,
  });

  final TerminalSession session;
  final FocusNode focusNode;

  /// When true, the next single letter typed is sent as a Ctrl combination.
  final ValueNotifier<bool> ctrlLatch;

  @override
  State<InputStrip> createState() => _InputStripState();
}

class _InputStripState extends State<InputStrip> {
  /// A zero-width character kept in the field so that Backspace on a soft
  /// keyboard, which produces no key event, shows up as a deletion.
  static const String _sentinel = '\u200B';
  static const TextEditingValue _blank = TextEditingValue(
    text: _sentinel,
    selection: TextSelection.collapsed(offset: 1),
  );

  static final Map<LogicalKeyboardKey, TermKey> _keys = {
    LogicalKeyboardKey.arrowUp: TermKey.up,
    LogicalKeyboardKey.arrowDown: TermKey.down,
    LogicalKeyboardKey.arrowRight: TermKey.right,
    LogicalKeyboardKey.arrowLeft: TermKey.left,
    LogicalKeyboardKey.enter: TermKey.enter,
    LogicalKeyboardKey.numpadEnter: TermKey.enter,
    LogicalKeyboardKey.backspace: TermKey.backspace,
    LogicalKeyboardKey.tab: TermKey.tab,
    LogicalKeyboardKey.escape: TermKey.escape,
    LogicalKeyboardKey.home: TermKey.home,
    LogicalKeyboardKey.end: TermKey.end,
    LogicalKeyboardKey.pageUp: TermKey.pageUp,
    LogicalKeyboardKey.pageDown: TermKey.pageDown,
    LogicalKeyboardKey.insert: TermKey.insert,
    LogicalKeyboardKey.delete: TermKey.delete,
  };

  final _controller = TextEditingController.fromValue(_blank);
  bool _resetting = false;

  /// Text held back because it contains characters PTT cannot store.
  String? _pending;
  int _pendingUnsupported = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _composing {
    final c = _controller.value.composing;
    return c.isValid && !c.isCollapsed;
  }

  void _reset() {
    _resetting = true;
    _controller.value = _blank;
    _resetting = false;
  }

  void _onChanged() {
    if (_resetting || _composing) return;
    final text = _controller.text;
    if (text == _sentinel) return;
    _reset();
    if (text.isEmpty) {
      widget.session.sendBytes(bytesForKey(TermKey.backspace));
    } else {
      _submit(text.replaceAll(_sentinel, ''));
    }
  }

  void _submit(String text) {
    if (text.isEmpty) return;
    final session = widget.session;

    if (widget.ctrlLatch.value) {
      widget.ctrlLatch.value = false;
      final bytes = bytesForCtrl(text);
      if (bytes != null) {
        session.sendBytes(bytes);
        return;
      }
    }

    final unsupported = session.codec.encode(text).unmappable;
    if (unsupported > 0) {
      setState(() {
        _pending = text;
        _pendingUnsupported = unsupported;
      });
      return;
    }
    session.sendText(text);
  }

  void _resolvePending({required bool send}) {
    final text = _pending;
    setState(() => _pending = null);
    if (send && text != null) widget.session.sendText(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _composing) return KeyEventResult.ignored;
    final session = widget.session;

    final key = _keys[event.logicalKey];
    if (key != null) {
      session.sendBytes(bytesForKey(key));
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      final bytes = bytesForCtrl(event.logicalKey.keyLabel);
      if (bytes == null) return KeyEventResult.ignored;
      session.sendBytes(bytes);
      return KeyEventResult.handled;
    }
    // Printable characters arrive through the text field instead.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('有 $_pendingUnsupported 個字 PTT 不支援，將以 ? 取代'),
                ),
                TextButton(
                  onPressed: () => _resolvePending(send: false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => _resolvePending(send: true),
                  child: const Text('送出'),
                ),
              ],
            ),
          ),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              // Keep focus so the keyboard stays open after Enter.
              onEditingComplete: () {},
              onSubmitted: (_) =>
                  widget.session.sendBytes(bytesForKey(TermKey.enter)),
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '輸入 ',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: 實作按鍵列**

`lib/ui/key_bar.dart`：

```dart
import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';

/// A scrollable row of the keys a soft keyboard lacks.
class KeyBar extends StatelessWidget {
  const KeyBar({super.key, required this.session, required this.ctrlLatch});

  final TerminalSession session;

  /// Toggled by the Ctrl button; consumed by the input strip.
  final ValueNotifier<bool> ctrlLatch;

  static const double _height = 44;
  static const List<(String, TermKey)> _keys = [
    ('←', TermKey.left),
    ('↑', TermKey.up),
    ('↓', TermKey.down),
    ('→', TermKey.right),
    ('Enter', TermKey.enter),
    ('PgUp', TermKey.pageUp),
    ('PgDn', TermKey.pageDown),
    ('Home', TermKey.home),
    ('End', TermKey.end),
    ('Esc', TermKey.escape),
    ('Tab', TermKey.tab),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      // Buttons must not take focus, or the soft keyboard would close.
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            for (final (label, key) in _keys)
              _KeyButton(
                label: label,
                onPressed: () => session.sendBytes(bytesForKey(key)),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: ctrlLatch,
              builder: (context, latched, _) => _KeyButton(
                label: 'Ctrl',
                selected: latched,
                onPressed: () => ctrlLatch.value = !latched,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 36),
          backgroundColor: selected ? Colors.white24 : Colors.white10,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
```

- [ ] **Step 6: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/session_test.dart test/ui/input_strip_test.dart test/ui/key_bar_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/core/session.dart lib/ui/input_strip.dart lib/ui/key_bar.dart test/core/session_test.dart test/ui/input_strip_test.dart test/ui/key_bar_test.dart
git commit -m "feat: add IME input strip and key bar"
```

---

### Task 4: 自動登入、帳密介面、防閒置

**Files:**
- Create: `lib/core/login/credentials.dart`
- Create: `lib/core/login/auto_login.dart`
- Create: `lib/core/anti_idle.dart`
- Test: `test/core/login/auto_login_test.dart`、`test/core/anti_idle_test.dart`

**Interfaces:**
- Consumes: `TerminalSession`（Task 3）
- Produces:
  - `class Credentials { const Credentials(String userId, String password); final String userId; final String password; }`
  - `abstract class CredentialStore { Future<Credentials?> load(); Future<void> save(Credentials credentials); Future<void> clear(); }`
  - `bool isValidUserId(String id)`（1 到 12 個英數字元）
  - `enum AutoLoginState { waitingForId, waitingForPassword, done, gaveUp }`
  - `class AutoLogin { AutoLogin(Credentials credentials); AutoLoginState get state; bool get active; String? onCursorRow(String row); void giveUp(); }`。`onCursorRow` 回傳要送出的文字（含結尾的 `\r`），不需送出時回傳 null。
  - `class AntiIdle { AntiIdle(TerminalSession session, {Duration interval = const Duration(minutes: 3)}); static const List<int> keepAlive; void start(); void stop(); }`。`start` 可重複呼叫。

提示字樣的假設：帳號提示所在列含有「請輸入代號」（已在歡迎畫面實測看到）；密碼提示所在列同時含有「請輸入」與「密碼」（依使用者實際登入時所見，未以程式實測）。若實際字樣不同，只需修改 `auto_login.dart` 中的兩個常數。

- [ ] **Step 1: 寫失敗的測試**

`test/core/login/auto_login_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/login/auto_login.dart';
import 'package:myptt/core/login/credentials.dart';

const idPrompt = '請輸入代號，或以 guest 參觀，或以 new 註冊:';
const passwordPrompt = '請輸入您的密碼:';

void main() {
  late AutoLogin login;

  setUp(() => login = AutoLogin(const Credentials('alice', 's3cret')));

  test('sends the id at the id prompt, then the password at the password prompt', () {
    expect(login.state, AutoLoginState.waitingForId);
    expect(login.onCursorRow(''), isNull);
    expect(login.onCursorRow(idPrompt), 'alice\r');
    expect(login.state, AutoLoginState.waitingForPassword);
    expect(login.onCursorRow(passwordPrompt), 's3cret\r');
    expect(login.state, AutoLoginState.done);
    expect(login.active, isFalse);
  });

  test('the id is sent only once while the prompt stays on screen', () {
    expect(login.onCursorRow(idPrompt), 'alice\r');
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow('$idPrompt alice'), isNull);
  });

  test('the password is never sent before the id', () {
    expect(login.onCursorRow(passwordPrompt), isNull);
    expect(login.state, AutoLoginState.waitingForId);
  });

  // Review Focus 1
  test('password is not sent to a row that merely mentions it', () {
    login.onCursorRow(idPrompt);
    expect(
      login.onCursorRow('忘記密碼可參考 https://www.ptt.cc/bbs/ID_GetBack/M.1.A.html'),
      isNull,
    );
    expect(login.onCursorRow('密碼'), isNull);
    expect(login.onCursorRow('請輸入代號'), isNull);
    expect(login.state, AutoLoginState.waitingForPassword);
  });

  // Review Focus 2
  test('does not retry after a failed login', () {
    login.onCursorRow(idPrompt);
    login.onCursorRow(passwordPrompt);
    expect(login.onCursorRow('密碼不對或無此帳號。請檢查大小寫及有無輸入錯誤。'), isNull);
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow(passwordPrompt), isNull);
    expect(login.state, AutoLoginState.done);
  });

  test('giving up stops everything', () {
    login.giveUp();
    expect(login.state, AutoLoginState.gaveUp);
    expect(login.active, isFalse);
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow(passwordPrompt), isNull);
  });

  test('giving up between id and password withholds the password', () {
    login.onCursorRow(idPrompt);
    login.giveUp();
    expect(login.onCursorRow(passwordPrompt), isNull);
  });

  test('giving up after success leaves the state as done', () {
    login.onCursorRow(idPrompt);
    login.onCursorRow(passwordPrompt);
    login.giveUp();
    expect(login.state, AutoLoginState.done);
  });

  test('user id validation', () {
    expect(isValidUserId('alice'), isTrue);
    expect(isValidUserId('A1b2C3d4E5f6'), isTrue);
    expect(isValidUserId(''), isFalse);
    expect(isValidUserId('A1b2C3d4E5f6g'), isFalse);
    expect(isValidUserId('al ice'), isFalse);
    expect(isValidUserId('alice\r'), isFalse);
    expect(isValidUserId('愛麗絲'), isFalse);
  });
}
```

`test/core/anti_idle_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/anti_idle.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  const interval = Duration(seconds: 60);
  late FakeConnection conn;
  late TerminalSession session;
  late AntiIdle idle;

  Future<void> start(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    await session.connect();
    idle = AntiIdle(session, interval: interval)..start();
  }

  Future<void> finish(WidgetTester tester) async {
    idle.stop();
    await tester.runAsync(session.dispose);
  }

  test('the keep-alive is ESC O A ESC O B and the default interval is 3 minutes', () {
    expect(AntiIdle.keepAlive, [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42]);
    expect(AntiIdle.defaultInterval, const Duration(minutes: 3));
  });

  testWidgets('sends a keep-alive after each idle interval', (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 59));
    expect(conn.sent, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(conn.sent, AntiIdle.keepAlive);
    await tester.pump(interval);
    expect(conn.sent, [...AntiIdle.keepAlive, ...AntiIdle.keepAlive]);
    await finish(tester);
  });

  testWidgets('user input restarts the countdown', (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 50));
    session.sendBytes([0x41]);
    await tester.pump(const Duration(seconds: 50));
    expect(conn.sent, [0x41]);
    await tester.pump(const Duration(seconds: 11));
    expect(conn.sent, [0x41, ...AntiIdle.keepAlive]);
    await finish(tester);
  });

  testWidgets('nothing is sent while disconnected or after stop', (tester) async {
    await start(tester);
    conn.drop();
    await tester.pump(interval * 2);
    expect(conn.sent, isEmpty);

    await session.connect();
    idle.stop();
    await tester.pump(interval * 2);
    expect(conn.sent, isEmpty);
    await finish(tester);
  });

  testWidgets('start is idempotent', (tester) async {
    await start(tester);
    idle.start();
    idle.start();
    await tester.pump(const Duration(seconds: 61));
    expect(conn.sent, AntiIdle.keepAlive);
    await finish(tester);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/login test/core/anti_idle_test.dart
```

Expected: FAIL，訊息為找不到 `auto_login.dart`、`credentials.dart`、`anti_idle.dart`。

- [ ] **Step 3: 實作帳密介面與自動登入**

`lib/core/login/credentials.dart`：

```dart
class Credentials {
  const Credentials(this.userId, this.password);

  final String userId;
  final String password;
}

/// Where saved credentials live. The real implementation uses the platform
/// keychain; nothing else may persist a password.
abstract class CredentialStore {
  Future<Credentials?> load();
  Future<void> save(Credentials credentials);
  Future<void> clear();
}

final RegExp _userId = RegExp(r'^[A-Za-z0-9]{1,12}$');

/// PTT ids are 1 to 12 letters or digits. Rejecting anything else also keeps
/// control characters out of what auto-login types.
bool isValidUserId(String id) => _userId.hasMatch(id);
```

`lib/core/login/auto_login.dart`：

```dart
import 'credentials.dart';

enum AutoLoginState { waitingForId, waitingForPassword, done, gaveUp }

/// Types the user id and password when PTT asks for them, once per
/// connection. It only reacts to the row the cursor is on, so text elsewhere
/// on the screen can never trigger it.
class AutoLogin {
  AutoLogin(this._credentials);

  /// Text that identifies the id prompt on the cursor's row.
  static const String _idPrompt = '請輸入代號';

  /// Both must appear on the cursor's row for it to be the password prompt.
  static const List<String> _passwordPrompt = ['請輸入', '密碼'];

  final Credentials _credentials;
  AutoLoginState _state = AutoLoginState.waitingForId;

  AutoLoginState get state => _state;

  bool get active =>
      _state == AutoLoginState.waitingForId ||
      _state == AutoLoginState.waitingForPassword;

  /// Call after each screen update with the text of the cursor's row.
  /// Returns what to type, or null.
  String? onCursorRow(String row) {
    switch (_state) {
      case AutoLoginState.waitingForId:
        if (!row.contains(_idPrompt)) return null;
        _state = AutoLoginState.waitingForPassword;
        return '${_credentials.userId}\r';
      case AutoLoginState.waitingForPassword:
        if (!_passwordPrompt.every(row.contains)) return null;
        _state = AutoLoginState.done;
        return '${_credentials.password}\r';
      case AutoLoginState.done:
      case AutoLoginState.gaveUp:
        return null;
    }
  }

  /// Stops reacting, for example after a timeout. A finished login stays done.
  void giveUp() {
    if (active) _state = AutoLoginState.gaveUp;
  }
}
```

- [ ] **Step 4: 實作防閒置**

`lib/core/anti_idle.dart`：

```dart
import 'dart:async';

import 'session.dart';

/// Sends a harmless key sequence when the user has been idle, so the BBS
/// does not drop the connection.
class AntiIdle {
  AntiIdle(this.session, {this.interval = defaultInterval});

  static const Duration defaultInterval = Duration(minutes: 3);

  /// Up then down in application cursor mode; the same default PCMan uses.
  static const List<int> keepAlive = [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42];

  final TerminalSession session;
  final Duration interval;

  StreamSubscription<void>? _activity;
  Timer? _timer;

  /// Safe to call repeatedly.
  void start() {
    if (_activity != null) return;
    _activity = session.userActivity.listen((_) => _restart());
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(
      interval,
      (_) => session.sendBytes(keepAlive, userInitiated: false),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _activity?.cancel();
    _activity = null;
  }
}
```

- [ ] **Step 5: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/login test/core/anti_idle_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/core/login lib/core/anti_idle.dart test/core/login test/core/anti_idle_test.dart
git commit -m "feat: add auto-login state machine, credential interface, anti-idle"
```

---

### Task 5: 連線控制與終端機頁

**Files:**
- Create: `lib/ui/session_controller.dart`
- Create: `lib/ui/terminal_page.dart`
- Modify: `lib/main.dart`（整個取代）
- Modify: `test/support/fake_connection.dart`（整個取代）
- Delete: `lib/ui/terminal_view.dart`、`test/ui/terminal_view_test.dart`
- Test: `test/ui/session_controller_test.dart`、`test/ui/terminal_page_test.dart`

**Interfaces:**
- Consumes: `TerminalSession`（Task 3）；`AutoLogin`、`Credentials`、`AntiIdle`（Task 4）；`TerminalSurface`（Task 2）；`InputStrip`、`KeyBar`（Task 3）
- Produces:
  - `FakeConnection` 新增 `Object? connectError`（非 null 時 `connect()` 丟出它）與 `int connectCalls`。
  - `class SessionController extends ChangeNotifier { SessionController(TerminalSession session, {Credentials? credentials, Duration loginTimeout = const Duration(seconds: 10)}); final TerminalSession session; ConnectionStatus get status; bool get connecting; bool get offline; bool get everConnected; String? get error; bool get showDisconnectedOverlay; bool get inputEnabled; Future<void> connect(); void browseOffline(); void onResumed(); }`
  - `class TerminalPage extends StatefulWidget { const TerminalPage({super.key, required SessionController controller, Future<bool> Function(String url)? openUrl}); }`。頁面在 `initState` 呼叫 `controller.connect()`，在 `dispose` 釋放 controller。

狀態規則：

| 狀況 | `showDisconnectedOverlay` | `inputEnabled` | 畫面 |
|---|---|---|---|
| 連線中 | false | false | 上方顯示「連線中…」 |
| 已連線 | false | true | 顯示輸入列與按鍵列 |
| 已斷線，尚未選擇 | true | false | 畫面變暗，顯示「已斷線」或「連線失敗」、重新連線、繼續瀏覽 |
| 已斷線，選擇繼續瀏覽 | false | false | 上方顯示「已離線」與重新連線；畫面可縮放、選取、開連結 |

「繼續瀏覽」只在曾經連上過時提供。回到前景時，若已斷線、曾經連上過、且使用者沒有選擇離線瀏覽，自動重連一次。

- [ ] **Step 1: 更新假連線**

`test/support/fake_connection.dart`（整個取代）：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:myptt/core/connection/connection.dart';

class FakeConnection implements Connection {
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final _status = StreamController<ConnectionStatus>.broadcast(sync: true);

  /// Everything passed to [send], in order.
  final List<int> sent = [];

  /// When set, [connect] throws this instead of connecting.
  Object? connectError;

  /// Number of times [connect] actually attempted a connection.
  int connectCalls = 0;

  @override
  ConnectionStatus status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _status.stream;

  @override
  Future<void> connect() async {
    if (status != ConnectionStatus.disconnected) return;
    connectCalls++;
    _set(ConnectionStatus.connecting);
    // Yield once so callers can observe the connecting state.
    await Future<void>.value();
    final error = connectError;
    if (error != null) {
      _set(ConnectionStatus.disconnected);
      throw error;
    }
    _set(ConnectionStatus.connected);
  }

  @override
  void send(List<int> bytes) => sent.addAll(bytes);

  @override
  Future<void> close() async => _set(ConnectionStatus.disconnected);

  /// Simulates bytes arriving from the server.
  void emit(List<int> bytes) => _data.add(Uint8List.fromList(bytes));

  /// Simulates the server dropping the connection.
  void drop() => _set(ConnectionStatus.disconnected);

  void _set(ConnectionStatus s) {
    if (status == s) return;
    status = s;
    _status.add(s);
  }
}
```

執行既有測試，確認假連線的改動沒有破壞它們：

```bash
/c/dev/flutter/bin/flutter.bat test test/core test/ui/terminal_surface_test.dart test/ui/input_strip_test.dart test/ui/key_bar_test.dart
```

Expected: 只有 `session_test.dart` 的 `status follows the connection and fires an update` 失敗（更新次數由 2 變 3，因為多了「連線中」狀態）。把該測試最後一行的 `expect(updates, 2);` 改為 `expect(updates, 3);` 後重跑，應全部通過。

- [ ] **Step 2: 寫失敗的測試**

`test/ui/session_controller_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/anti_idle.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/login/credentials.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/session_controller.dart';

import '../support/fake_connection.dart';

const idPrompt = '請輸入代號，或以 guest 參觀，或以 new 註冊: ';
const passwordPrompt = '請輸入您的密碼: ';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late SessionController controller;

  void create({Credentials? credentials}) {
    conn = FakeConnection();
    controller = SessionController(
      TerminalSession(conn, codec),
      credentials: credentials,
    );
  }

  void show(String text) => conn.emit(codec.encode('\x1b[2J\x1b[H$text').bytes);
  String sentText() => String.fromCharCodes(conn.sent);

  testWidgets('connecting, connected, and dropped states', (tester) async {
    create();
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.everConnected, isFalse);

    final connecting = controller.connect();
    expect(controller.connecting, isTrue);
    expect(controller.showDisconnectedOverlay, isFalse);
    expect(controller.inputEnabled, isFalse);
    await connecting;
    expect(controller.status, ConnectionStatus.connected);
    expect(controller.inputEnabled, isTrue);
    expect(controller.everConnected, isTrue);

    conn.drop();
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.inputEnabled, isFalse);
    expect(controller.error, isNull);
    controller.dispose();
  });

  testWidgets('a failed connection reports the error', (tester) async {
    create();
    conn.connectError = const SocketException('no route');
    await controller.connect();
    expect(controller.status, ConnectionStatus.disconnected);
    expect(controller.error, contains('no route'));
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.everConnected, isFalse);

    conn.connectError = null;
    await controller.connect();
    expect(controller.error, isNull);
    expect(controller.status, ConnectionStatus.connected);
    controller.dispose();
  });

  testWidgets('auto-login types the id and password at their prompts', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show('歡迎');
    expect(conn.sent, isEmpty);
    show(idPrompt);
    expect(sentText(), 'alice\r');
    show(passwordPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    show(idPrompt);
    show(passwordPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    controller.dispose();
  });

  testWidgets('without credentials nothing is typed', (tester) async {
    create();
    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    expect(conn.sent, isEmpty);
    controller.dispose();
  });

  testWidgets('auto-login gives up after the timeout', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show(idPrompt);
    expect(sentText(), 'alice\r');
    await tester.pump(const Duration(seconds: 11));
    show(passwordPrompt);
    expect(sentText(), 'alice\r');
    controller.dispose();
  });

  testWidgets('reconnecting logs in again exactly once', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    conn.drop();
    conn.sent.clear();

    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    show(idPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    controller.dispose();
  });

  testWidgets('choosing offline hides the overlay and stays disconnected',
      (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.browseOffline();
    expect(controller.offline, isTrue);
    expect(controller.showDisconnectedOverlay, isFalse);
    expect(controller.inputEnabled, isFalse);

    await controller.connect();
    expect(controller.offline, isFalse);
    expect(controller.inputEnabled, isTrue);
    controller.dispose();
  });

  testWidgets('resuming after a drop reconnects', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.onResumed();
    await tester.pump();
    expect(controller.status, ConnectionStatus.connected);
    expect(conn.connectCalls, 2);
    controller.dispose();
  });

  // Review Focus 4
  testWidgets('resuming repeatedly connects once', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.onResumed();
    controller.onResumed();
    controller.onResumed();
    await tester.pump();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 2);
    expect(controller.status, ConnectionStatus.connected);
    controller.dispose();
  });

  // Review Focus 4
  testWidgets('resuming in offline mode does not reconnect', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.browseOffline();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 1);
    expect(controller.status, ConnectionStatus.disconnected);
    controller.dispose();
  });

  testWidgets('resuming before any successful connection does not connect',
      (tester) async {
    create();
    conn.connectError = const SocketException('down');
    await controller.connect();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 1);
    controller.dispose();
  });

  testWidgets('anti-idle runs only while connected', (tester) async {
    create();
    await controller.connect();
    await tester.pump(AntiIdle.defaultInterval + const Duration(seconds: 1));
    expect(conn.sent, AntiIdle.keepAlive);
    conn.drop();
    conn.sent.clear();
    await tester.pump(AntiIdle.defaultInterval * 2);
    expect(conn.sent, isEmpty);
    controller.dispose();
  });

  testWidgets('listeners are told about state changes, not every screen update',
      (tester) async {
    create();
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.connect();
    final afterConnect = notifications;
    show('a');
    show('b');
    show('c');
    expect(notifications, afterConnect);
    conn.drop();
    expect(notifications, afterConnect + 1);
    controller.dispose();
  });

  testWidgets('nothing happens after dispose', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    controller.dispose();
    controller.onResumed();
    await tester.pump(AntiIdle.defaultInterval * 2);
    expect(conn.sent, isEmpty);
  });
}
```

`test/ui/terminal_page_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/input_strip.dart';
import 'package:myptt/ui/key_bar.dart';
import 'package:myptt/ui/session_controller.dart';
import 'package:myptt/ui/terminal_page.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late List<String> opened;

  Future<void> pumpPage(WidgetTester tester, {Object? connectError}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    conn = FakeConnection()..connectError = connectError;
    opened = [];
    await tester.pumpWidget(MaterialApp(
      home: TerminalPage(
        controller: SessionController(TerminalSession(conn, codec)),
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
      ),
    ));
    await tester.pump();
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('connects on open and shows the input controls', (tester) async {
    await pumpPage(tester);
    expect(conn.status, ConnectionStatus.connected);
    expect(find.byType(InputStrip), findsOneWidget);
    expect(find.byType(KeyBar), findsOneWidget);
    expect(find.text('已斷線'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('a drop dims the screen and offers reconnect or keep browsing',
      (tester) async {
    await pumpPage(tester);
    conn.emit('last screen https://example.com/x'.codeUnits);
    conn.drop();
    await tester.pump();

    expect(find.text('已斷線'), findsOneWidget);
    expect(find.text('重新連線'), findsOneWidget);
    expect(find.text('繼續瀏覽'), findsOneWidget);
    expect(find.byType(InputStrip), findsNothing);
    expect(find.byType(KeyBar), findsNothing);

    await tester.tap(find.text('繼續瀏覽'));
    await tester.pump();
    expect(find.text('已斷線'), findsNothing);
    expect(find.text('已離線'), findsOneWidget);
    expect(find.byType(InputStrip), findsNothing);

    // Offline: links still open, swipes send nothing.
    final topLeft = tester.getTopLeft(find.byKey(const Key('terminal-zoom')));
    await tester.tapAt(topLeft + const Offset(125, 10));
    expect(opened, ['https://example.com/x']);
    await tester.dragFrom(topLeft + const Offset(400, 200), const Offset(200, 0));
    expect(conn.sent, isEmpty);

    await tester.tap(find.text('重新連線'));
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(find.text('已離線'), findsNothing);
    expect(find.byType(InputStrip), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('a failed first connection shows the reason and only a retry',
      (tester) async {
    await pumpPage(tester, connectError: const SocketException('no route'));
    expect(find.text('連線失敗'), findsOneWidget);
    expect(find.textContaining('no route'), findsOneWidget);
    expect(find.text('重新連線'), findsOneWidget);
    expect(find.text('繼續瀏覽'), findsNothing);

    conn.connectError = null;
    await tester.tap(find.text('重新連線'));
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(find.text('連線失敗'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('returning to the foreground reconnects after a drop', (tester) async {
    await pumpPage(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    conn.drop();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(conn.connectCalls, 2);
    expect(find.text('已斷線'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('swipes on the page reach the server when connected', (tester) async {
    await pumpPage(tester);
    final topLeft = tester.getTopLeft(find.byKey(const Key('terminal-zoom')));
    await tester.dragFrom(topLeft + const Offset(400, 200), const Offset(200, 0));
    expect(conn.sent, '\x1b[D'.codeUnits);
    await disposePage(tester);
  });

  testWidgets('leaving the page closes the connection', (tester) async {
    await pumpPage(tester);
    await disposePage(tester);
    expect(conn.status, ConnectionStatus.disconnected);
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui/session_controller_test.dart test/ui/terminal_page_test.dart
```

Expected: FAIL，訊息為找不到 `session_controller.dart` 與 `terminal_page.dart`。

- [ ] **Step 4: 實作連線控制**

`lib/ui/session_controller.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/anti_idle.dart';
import '../core/connection/connection.dart';
import '../core/login/auto_login.dart';
import '../core/login/credentials.dart';
import '../core/session.dart';

/// Owns one [TerminalSession] and decides when to connect, log in, keep the
/// connection alive, and what the page should show when it drops.
///
/// Foreground-return reconnect timing, which can only be checked on a real
/// iPhone, lives in [onResumed].
class SessionController extends ChangeNotifier {
  SessionController(
    this.session, {
    this.credentials,
    this.loginTimeout = const Duration(seconds: 10),
  }) {
    _antiIdle = AntiIdle(session);
    _updates = session.updates.listen((_) => _onUpdate());
  }

  final TerminalSession session;

  /// When set, typed automatically at the login prompts.
  final Credentials? credentials;

  /// How long after connecting auto-login keeps waiting for its prompts.
  final Duration loginTimeout;

  late final AntiIdle _antiIdle;
  late final StreamSubscription<void> _updates;
  AutoLogin? _autoLogin;
  Timer? _loginTimer;
  bool _connecting = false;
  bool _offline = false;
  bool _everConnected = false;
  bool _disposed = false;
  String? _error;
  Object? _lastNotified;

  ConnectionStatus get status => session.status;
  bool get connecting => _connecting;

  /// The user chose to keep looking at the last screen instead of reconnecting.
  bool get offline => _offline;
  bool get everConnected => _everConnected;
  String? get error => _error;

  bool get showDisconnectedOverlay =>
      status == ConnectionStatus.disconnected && !_connecting && !_offline;
  bool get inputEnabled => status == ConnectionStatus.connected;

  Future<void> connect() async {
    if (_disposed || _connecting) return;
    if (status != ConnectionStatus.disconnected) return;
    _connecting = true;
    _offline = false;
    _error = null;
    _stopAutoLogin();
    final credentials = this.credentials;
    if (credentials != null) _autoLogin = AutoLogin(credentials);
    _notifyIfChanged();
    try {
      await session.connect();
    } catch (e) {
      _error = '$e';
      _stopAutoLogin();
    }
    _connecting = false;
    _notifyIfChanged();
  }

  void browseOffline() {
    if (status != ConnectionStatus.disconnected) return;
    _offline = true;
    _notifyIfChanged();
  }

  /// Call when the app returns to the foreground.
  void onResumed() {
    if (_disposed || !_everConnected || _offline) return;
    connect();
  }

  void _onUpdate() {
    if (_disposed) return;
    if (status == ConnectionStatus.connected) {
      _everConnected = true;
      _antiIdle.start();
      final login = _autoLogin;
      if (login != null && login.active) {
        _loginTimer ??= Timer(loginTimeout, login.giveUp);
        final reply = login.onCursorRow(session.cursorRowText);
        if (reply != null) session.sendText(reply);
      }
    } else if (status == ConnectionStatus.disconnected) {
      _antiIdle.stop();
      _stopAutoLogin();
    }
    _notifyIfChanged();
  }

  void _stopAutoLogin() {
    _loginTimer?.cancel();
    _loginTimer = null;
    _autoLogin = null;
  }

  /// Screen updates arrive constantly; listeners only care about these.
  void _notifyIfChanged() {
    if (_disposed) return;
    final snapshot = (status, _connecting, _offline, _everConnected, _error);
    if (snapshot == _lastNotified) return;
    _lastNotified = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _antiIdle.stop();
    _stopAutoLogin();
    _updates.cancel();
    unawaited(session.dispose());
    super.dispose();
  }
}
```

- [ ] **Step 5: 實作終端機頁**

`lib/ui/terminal_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../core/connection/connection.dart';
import 'input_strip.dart';
import 'key_bar.dart';
import 'session_controller.dart';
import 'terminal_surface.dart';

/// The terminal screen: the surface, the input controls, and what to show
/// while connecting, disconnected, or browsing offline.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.controller, this.openUrl});

  /// Owned by this page: connected on open, disposed on close.
  final SessionController controller;

  /// Opens a link in the system browser. Null disables link taps.
  final Future<bool> Function(String url)? openUrl;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  final _inputFocus = FocusNode();
  final _ctrlLatch = ValueNotifier<bool>(false);

  SessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChanged);
    _controller.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _inputFocus.dispose();
    _ctrlLatch.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.onResumed();
  }

  void _toggleKeyboard() {
    if (!_controller.inputEnabled) return;
    if (_inputFocus.hasFocus) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _showCopied(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('已複製 ${text.runes.length} 個字'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final openUrl = widget.openUrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (c.connecting || c.status == ConnectionStatus.connecting)
              const _Banner(label: '連線中…')
            else if (c.offline)
              _Banner(label: '已離線', actionLabel: '重新連線', onAction: c.connect),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TerminalSurface(
                    session: c.session,
                    inputEnabled: c.inputEnabled,
                    onTapBackground: _toggleKeyboard,
                    onOpenUrl: openUrl == null ? null : (url) => openUrl(url),
                    onCopied: _showCopied,
                  ),
                  if (c.showDisconnectedOverlay)
                    _DisconnectedOverlay(
                      error: c.error,
                      canBrowse: c.everConnected,
                      onReconnect: c.connect,
                      onBrowse: c.browseOffline,
                    ),
                ],
              ),
            ),
            if (c.inputEnabled) ...[
              InputStrip(
                session: c.session,
                focusNode: _inputFocus,
                ctrlLatch: _ctrlLatch,
              ),
              KeyBar(session: c.session, ctrlLatch: _ctrlLatch),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.label, this.actionLabel, this.onAction});

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _DisconnectedOverlay extends StatelessWidget {
  const _DisconnectedOverlay({
    required this.error,
    required this.canBrowse,
    required this.onReconnect,
    required this.onBrowse,
  });

  /// Why connecting failed, or null for a connection that simply dropped.
  final String? error;

  /// Whether there is a last screen worth looking at.
  final bool canBrowse;
  final VoidCallback onReconnect;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error == null ? '已斷線' : '連線失敗',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center, maxLines: 4),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: onReconnect, child: const Text('重新連線')),
              if (canBrowse)
                TextButton(onPressed: onBrowse, child: const Text('繼續瀏覽')),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 更新啟動程式並移除舊元件**

`lib/main.dart`（整個取代；登入頁在 Task 6 接上）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/connection/ws_connection.dart';
import 'core/encoding/big5_codec.dart';
import 'core/session.dart';
import 'ui/session_controller.dart';
import 'ui/terminal_page.dart';

Future<Big5Codec> loadCodec() async {
  final b2u = await rootBundle.load('assets/uao/b2u.bin');
  final u2b = await rootBundle.load('assets/uao/u2b.bin');
  return Big5Codec(
    b2u.buffer.asUint8List(b2u.offsetInBytes, b2u.lengthInBytes),
    u2b.buffer.asUint8List(u2b.offsetInBytes, u2b.lengthInBytes),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final codec = await loadCodec();
  runApp(MaterialApp(
    title: 'MyPTT',
    theme: ThemeData.dark(),
    home: TerminalPage(
      controller: SessionController(TerminalSession(WsConnection(), codec)),
    ),
  ));
}
```

```bash
git rm -q lib/ui/terminal_view.dart test/ui/terminal_view_test.dart
```

- [ ] **Step 7: 執行全部測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
```

Expected: `No issues found!` 與 `All tests passed!`

- [ ] **Step 8: Commit**

```bash
git add -A lib test
git commit -m "feat: add session controller and terminal page with offline browsing"
```

---

### Task 6: 登入頁、鑰匙圈、開啟連結

**Files:**
- Modify: `pubspec.yaml`（由 `flutter pub add` 修改）
- Create: `lib/platform/secure_credential_store.dart`
- Create: `lib/platform/link_opener.dart`
- Create: `lib/ui/login_page.dart`
- Modify: `lib/main.dart`（整個取代）
- Create: `test/support/fake_credential_store.dart`
- Test: `test/ui/login_page_test.dart`、`test/platform/link_opener_test.dart`

**Interfaces:**
- Consumes: `Credentials`、`CredentialStore`、`isValidUserId`（Task 4）；`SessionController`、`TerminalPage`、`FakeConnection`（Task 5）；`loadCodec`（Task 5 的 `main.dart`）
- Produces:
  - `class SecureCredentialStore implements CredentialStore { const SecureCredentialStore(); }`
  - `Uri? externalUri(String url)`（只接受 http 與 https，否則回傳 null）
  - `Future<bool> openExternalUrl(String url)`
  - `class LoginPage extends StatefulWidget { const LoginPage({super.key, required Big5Codec codec, required CredentialStore store, Connection Function() connectionFactory = LoginPage.defaultConnection, Future<bool> Function(String url)? openUrl}); static Connection defaultConnection(); }`
  - 測試用 `class FakeCredentialStore implements CredentialStore`，有 `Credentials? saved`、`int clears`、`Object? loadError`、`Object? saveError`。

登入頁行為：

- 開啟時讀取已存的帳密並填入，同時勾選「記住帳號密碼」。讀取失敗時當作沒有存過。
- 「登入」：帳號須為 1 到 12 個英數字元且密碼不可為空，否則顯示提示而不連線。勾選記住則存入鑰匙圈，否則清除已存的帳密。儲存失敗不阻擋登入。
- 「不自動登入，直接連線」：不檢查欄位、不動鑰匙圈，連線後由使用者自行輸入。

- [ ] **Step 1: 加入套件**

```bash
/c/dev/flutter/bin/flutter.bat pub add flutter_secure_storage url_launcher
/c/dev/flutter/bin/flutter.bat build windows --debug
```

Expected: 結尾顯示 `√ Built build\windows\x64\runner\Debug\myptt.exe`。

若建置因找不到 `atlstr.h` 而失敗，代表 `flutter_secure_storage` 的 Windows 版需要 Visual Studio 的 ATL 元件。此時停下並請使用者在 Visual Studio Installer 的「個別元件」中加裝「適用於最新 v143 建置工具的 C++ ATL」，裝好後重跑上面的建置指令。不要改用其他儲存方式繞過。

- [ ] **Step 2: 寫失敗的測試**

`test/support/fake_credential_store.dart`：

```dart
import 'package:myptt/core/login/credentials.dart';

class FakeCredentialStore implements CredentialStore {
  FakeCredentialStore([this.saved]);

  /// What the store currently holds.
  Credentials? saved;

  /// Number of times [clear] was called.
  int clears = 0;

  /// When set, [load] or [save] throws it.
  Object? loadError;
  Object? saveError;

  @override
  Future<Credentials?> load() async {
    final error = loadError;
    if (error != null) throw error;
    return saved;
  }

  @override
  Future<void> save(Credentials credentials) async {
    final error = saveError;
    if (error != null) throw error;
    saved = credentials;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}
```

`test/platform/link_opener_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/platform/link_opener.dart';

void main() {
  test('accepts http and https URLs', () {
    expect(externalUri('https://www.ptt.cc/bbs/Stock/index.html')?.host, 'www.ptt.cc');
    expect(externalUri('http://example.com/a?b=c')?.scheme, 'http');
  });

  test('rejects other schemes and malformed input', () {
    expect(externalUri('javascript:alert(1)'), isNull);
    expect(externalUri('file:///etc/passwd'), isNull);
    expect(externalUri('tel:110'), isNull);
    expect(externalUri('myapp://open'), isNull);
    expect(externalUri('https://'), isNull);
    expect(externalUri('not a url'), isNull);
    expect(externalUri(''), isNull);
  });
}
```

`test/ui/login_page_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/login/credentials.dart';
import 'package:myptt/ui/login_page.dart';
import 'package:myptt/ui/terminal_page.dart';

import '../support/fake_connection.dart';
import '../support/fake_credential_store.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeCredentialStore store;
  late List<FakeConnection> connections;

  Future<void> pumpLogin(WidgetTester tester, {Credentials? saved}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store = FakeCredentialStore(saved);
    connections = [];
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        codec: codec,
        store: store,
        connectionFactory: () {
          final c = FakeConnection();
          connections.add(c);
          return c;
        },
      ),
    ));
    await tester.pump();
  }

  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  String sentText() => String.fromCharCodes(connections.single.sent);
  void show(String text) => connections.single.emit(codec.encode(text).bytes);

  testWidgets('logging in connects and types the credentials', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalPage), findsOneWidget);
    expect(connections.single.status, ConnectionStatus.connected);
    show('請輸入代號，或以 guest 參觀，或以 new 註冊: ');
    expect(sentText(), 'alice\r');
    show('\r\n請輸入您的密碼: ');
    expect(sentText(), 'alice\rs3cret\r');
    await disposeAll(tester);
  });

  testWidgets('credentials are saved only when remember is checked', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(store.clears, 1);
    await disposeAll(tester);

    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'bob');
    await tester.enterText(field('密碼'), 'pw');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(store.saved?.userId, 'bob');
    expect(store.saved?.password, 'pw');
    await disposeAll(tester);
  });

  testWidgets('saved credentials are filled in with remember checked', (tester) async {
    await pumpLogin(tester, saved: const Credentials('alice', 's3cret'));
    expect(find.text('alice'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.widget<TextField>(field('密碼')).obscureText, isTrue);
    expect(tester.widget<TextField>(field('密碼')).controller?.text, 's3cret');
    await disposeAll(tester);
  });

  testWidgets('invalid input shows a message and does not connect', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('請輸入帳號與密碼'), findsOneWidget);

    await tester.enterText(field('帳號'), '愛麗絲');
    await tester.enterText(field('密碼'), 'pw');
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('帳號只能是 1 到 12 個英文字母或數字'), findsOneWidget);

    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), '');
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('請輸入帳號與密碼'), findsOneWidget);

    expect(connections, isEmpty);
    expect(find.byType(TerminalPage), findsNothing);
    await disposeAll(tester);
  });

  testWidgets('surrounding spaces in the id are ignored', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), '  alice ');
    await tester.enterText(field('密碼'), ' pw ');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    show('請輸入代號: ');
    expect(sentText(), 'alice\r');
    show('\r\n請輸入您的密碼: ');
    expect(sentText(), 'alice\r pw \r');
    await disposeAll(tester);
  });

  testWidgets('connecting without auto-login types nothing and keeps the keychain',
      (tester) async {
    await pumpLogin(tester, saved: const Credentials('alice', 's3cret'));
    await tester.tap(find.text('不自動登入，直接連線'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalPage), findsOneWidget);
    show('請輸入代號: ');
    expect(connections.single.sent, isEmpty);
    expect(store.saved?.userId, 'alice');
    expect(store.clears, 0);
    await disposeAll(tester);
  });

  testWidgets('keychain failures do not block logging in', (tester) async {
    await pumpLogin(tester);
    store.saveError = StateError('keychain locked');
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeAll(tester);

    store = FakeCredentialStore()..loadError = StateError('keychain locked');
    connections = [];
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(codec: codec, store: store),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('登入'), findsOneWidget);
    await disposeAll(tester);
  });

  testWidgets('going back from the terminal closes the connection and each login gets a new one',
      (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(TerminalPage))).pop();
    await tester.pumpAndSettle();
    expect(connections.single.status, ConnectionStatus.disconnected);
    expect(find.text('登入'), findsOneWidget);

    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(connections.length, 2);
    expect(connections.last.status, ConnectionStatus.connected);
    await disposeAll(tester);
  });

  testWidgets('the password never appears in visible text', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 'Sup3rSecret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    connections.single.drop();
    await tester.pump();
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(contains('Sup3rSecret')));
    }
    await disposeAll(tester);
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui/login_page_test.dart test/platform/link_opener_test.dart
```

Expected: FAIL，訊息為找不到 `login_page.dart` 與 `link_opener.dart`。

- [ ] **Step 4: 實作平台相關的兩個檔案**

`lib/platform/link_opener.dart`：

```dart
import 'package:url_launcher/url_launcher.dart';

/// Parses [url] if it is safe to hand to the system browser: only absolute
/// http and https URLs with a host. Text on a BBS screen is untrusted.
Uri? externalUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Opens [url] in the system browser. Returns false if it was rejected or
/// could not be opened.
Future<bool> openExternalUrl(String url) async {
  final uri = externalUri(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
```

`lib/platform/secure_credential_store.dart`：

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/login/credentials.dart';

/// Stores the PTT credentials in the platform keychain.
///
/// Keychain behaviour that can only be checked on a real iPhone lives here.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore();

  static const String _userIdKey = 'ptt_user_id';
  static const String _passwordKey = 'ptt_password';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<Credentials?> load() async {
    final userId = await _storage.read(key: _userIdKey);
    final password = await _storage.read(key: _passwordKey);
    if (userId == null || password == null) return null;
    return Credentials(userId, password);
  }

  @override
  Future<void> save(Credentials credentials) async {
    await _storage.write(key: _userIdKey, value: credentials.userId);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _passwordKey);
  }
}
```

- [ ] **Step 5: 實作登入頁**

`lib/ui/login_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../core/connection/connection.dart';
import '../core/connection/ws_connection.dart';
import '../core/encoding/big5_codec.dart';
import '../core/login/credentials.dart';
import '../core/session.dart';
import 'session_controller.dart';
import 'terminal_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.codec,
    required this.store,
    this.connectionFactory = defaultConnection,
    this.openUrl,
  });

  final Big5Codec codec;
  final CredentialStore store;

  /// Creates the connection for each new session.
  final Connection Function() connectionFactory;
  final Future<bool> Function(String url)? openUrl;

  static Connection defaultConnection() => WsConnection();

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    Credentials? saved;
    try {
      saved = await widget.store.load();
    } catch (_) {
      // An unreadable keychain is the same as an empty one.
    }
    final credentials = saved;
    if (!mounted || credentials == null) return;
    setState(() {
      _userId.text = credentials.userId;
      _password.text = credentials.password;
      _remember = true;
    });
  }

  Future<void> _login() async {
    final userId = _userId.text.trim();
    final password = _password.text;
    if (userId.isEmpty || password.isEmpty) {
      setState(() => _message = '請輸入帳號與密碼');
      return;
    }
    if (!isValidUserId(userId)) {
      setState(() => _message = '帳號只能是 1 到 12 個英文字母或數字');
      return;
    }
    setState(() => _message = null);

    final credentials = Credentials(userId, password);
    try {
      if (_remember) {
        await widget.store.save(credentials);
      } else {
        await widget.store.clear();
      }
    } catch (_) {
      // Failing to remember must not stop the user from logging in.
    }
    if (!mounted) return;
    _openTerminal(credentials);
  }

  void _openTerminal(Credentials? credentials) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TerminalPage(
        controller: SessionController(
          TerminalSession(widget.connectionFactory(), widget.codec),
          credentials: credentials,
        ),
        openUrl: widget.openUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'MyPTT',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _userId,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '帳號'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(labelText: '密碼'),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? false),
                      ),
                      const Expanded(child: Text('記住帳號密碼')),
                    ],
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        message,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  FilledButton(onPressed: _login, child: const Text('登入')),
                  TextButton(
                    onPressed: () => _openTerminal(null),
                    child: const Text('不自動登入，直接連線'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 接上啟動程式**

`lib/main.dart`（整個取代）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/encoding/big5_codec.dart';
import 'platform/link_opener.dart';
import 'platform/secure_credential_store.dart';
import 'ui/login_page.dart';

Future<Big5Codec> loadCodec() async {
  final b2u = await rootBundle.load('assets/uao/b2u.bin');
  final u2b = await rootBundle.load('assets/uao/u2b.bin');
  return Big5Codec(
    b2u.buffer.asUint8List(b2u.offsetInBytes, b2u.lengthInBytes),
    u2b.buffer.asUint8List(u2b.offsetInBytes, u2b.lengthInBytes),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final codec = await loadCodec();
  runApp(MaterialApp(
    title: 'MyPTT',
    theme: ThemeData.dark(),
    home: LoginPage(
      codec: codec,
      store: const SecureCredentialStore(),
      openUrl: openExternalUrl,
    ),
  ));
}
```

- [ ] **Step 7: 執行全部測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
```

Expected: `No issues found!` 與 `All tests passed!`

- [ ] **Step 8: 在 Windows 上建置並檢查畫面**

```bash
/c/dev/flutter/bin/flutter.bat build windows --debug
```

Expected: `√ Built build\windows\x64\runner\Debug\myptt.exe`。

啟動程式並擷取它自己的視窗（不擷取桌面其他內容），確認登入頁出現「帳號」「密碼」「記住帳號密碼」「登入」「不自動登入，直接連線」。不要在此步驟輸入任何真實帳密。

- [ ] **Step 9: Commit**

```bash
git add -A lib test pubspec.yaml pubspec.lock windows ios
git commit -m "feat: add login page, keychain storage, and link opening"
```

---

### Task 7: iOS 建置說明與專案說明

**Files:**
- Create: `docs/ios-build.md`
- Modify: `README.md`（整個取代）
- Modify: `pubspec.yaml`（`description` 一行）
- Modify: `ios/Runner/Info.plist`（顯示名稱）
- Test: `test/project_metadata_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: 無

- [ ] **Step 1: 寫失敗的測試**

`test/project_metadata_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the iOS app is named MyPTT on the home screen', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    expect(match?.group(1), 'MyPTT');
  });

  test('template text has been replaced', () {
    expect(File('README.md').readAsStringSync(), isNot(contains('A new Flutter project')));
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('A new Flutter project')));
  });

  test('the iOS build guide covers every item that needs a real iPhone', () {
    final guide = File('docs/ios-build.md').readAsStringSync();
    for (final topic in const ['鍵盤', '鑰匙圈', '回到前景', '手勢', '字體']) {
      expect(guide, contains(topic), reason: topic);
    }
    for (final file in const [
      'lib/ui/input_strip.dart',
      'lib/platform/secure_credential_store.dart',
      'lib/ui/session_controller.dart',
      'lib/ui/terminal_surface.dart',
      'lib/ui/terminal_painter.dart',
    ]) {
      expect(guide, contains(file), reason: file);
      expect(File(file).existsSync(), isTrue, reason: file);
    }
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/project_metadata_test.dart
```

Expected: FAIL。顯示名稱為 `Myptt`、README 仍含範本文字、`docs/ios-build.md` 不存在。

- [ ] **Step 3: 修改顯示名稱與描述**

```bash
sed -i 's|<string>Myptt</string>|<string>MyPTT</string>|' ios/Runner/Info.plist
sed -i 's|^description: .*|description: "PTT client for iOS, based on PCMan."|' pubspec.yaml
grep -n -A1 'CFBundleDisplayName' ios/Runner/Info.plist
grep -n '^description' pubspec.yaml
```

Expected: `CFBundleDisplayName` 的下一行為 `<string>MyPTT</string>`；描述為新的文字。若 `Info.plist` 中 `CFBundleDisplayName` 的原值不是 `Myptt`，以實際值修改 `sed` 的比對字串，只改這一個鍵。

- [ ] **Step 4: 撰寫說明文件**

`README.md`（整個取代）：

````markdown
# MyPTT

在 iPhone 上使用的 PTT 用戶端，以 [PCMan](https://github.com/pcman-bbs/pcman-windows) 為參考，用 Flutter 重新實作。

- 透過 `wss://ws.ptt.cc/bbs` 連線，畫面為 80×24 的終端機。
- 以滑動、縮放、按鍵列與系統輸入法操作。
- 帳號密碼存放在系統鑰匙圈。

## 開發

需要 Flutter stable。在 Windows 上開發與測試，在 Mac 上建置 iOS 版。

```
flutter test
flutter run -d windows
```

- 設計規格：`docs/superpowers/specs/2026-10-06-myptt-ios-design.md`
- iOS 建置步驟：`docs/ios-build.md`
- Big5 對照表的來源與重新產生方式：`assets/uao/README.md`

## 授權

GNU GPL 第 2 版，見 `LICENSE`。本專案移植了 PCMan 的部分邏輯。
````

`docs/ios-build.md`：

````markdown
# 在 Mac 上建置並安裝到 iPhone

這份文件給借到 Mac 的那段時間使用。程式已在 Windows 上通過測試，這裡只做建置、安裝，以及確認只能在實機上驗證的項目。

## 需要準備

- 一台 Mac，macOS 版本能安裝目前的 Xcode。
- 一支 iPhone 與傳輸線。
- 一個 Apple ID。免費帳號即可安裝到自己的手機，但 app 每 7 天需要重新安裝一次；付費開發者帳號則為一年。

## 步驟

1. **安裝 Xcode**：從 App Store 安裝，開啟一次並同意授權，讓它裝完附加元件。
2. **安裝命令列工具與 CocoaPods**：

   ```
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   brew install cocoapods
   ```

3. **安裝 Flutter**：

   ```
   git clone https://github.com/flutter/flutter.git -b stable ~/flutter
   export PATH="$PATH:$HOME/flutter/bin"
   flutter doctor
   ```

   `flutter doctor` 的 Xcode 一項必須是勾。

4. **取得專案並確認測試通過**：

   ```
   git clone https://github.com/user240925/MyPTT.git
   cd MyPTT
   flutter pub get
   flutter test
   ```

5. **設定簽章**：執行 `open ios/Runner.xcworkspace`。在 Xcode 左側選 Runner，到 Signing & Capabilities，勾選 Automatically manage signing，Team 選自己的 Apple ID。若出現識別碼已被使用的錯誤，把 Bundle Identifier 改成自己獨有的字串。

6. **安裝到手機**：接上 iPhone 並信任這台電腦。iOS 16 以上需到「設定 → 隱私權與安全性 → 開發者模式」開啟並重新啟動。然後執行：

   ```
   flutter run --release
   ```

   第一次開啟 app 前，到「設定 → 一般 → VPN 與裝置管理」信任自己的開發者憑證。

## 實機檢查清單

以下項目在 Windows 上無法驗證。每一項都標明了出問題時要改的檔案。

### 鍵盤與輸入法

檔案：`lib/ui/input_strip.dart`

- [ ] 點一下畫面，鍵盤彈出；再點一下，鍵盤收起。
- [ ] 鍵盤彈出時，終端機畫面、輸入列、按鍵列都看得到，沒有被鍵盤蓋住。
- [ ] 用注音或其他中文輸入法打字：組字過程中 PTT 畫面沒有變化，選字後才出現中文字。
- [ ] 打英文字母與數字，每按一下就立刻出現在 PTT 畫面上。
- [ ] 按鍵盤的刪除鍵，PTT 畫面上刪掉一個字。連按數次，每次都有效。
- [ ] 按鍵盤右下角的送出鍵，等同 Enter，且鍵盤不會收起。
- [ ] 按鍵列上的按鍵有作用，而且按了之後鍵盤不會收起。
- [ ] 按下 Ctrl 再打 `p`，等同 Ctrl+P。

刪除鍵沒有反應時，問題在欄位中的佔位字元機制，檢查 `_onChanged`。

### 鑰匙圈

檔案：`lib/platform/secure_credential_store.dart`

- [ ] 勾選「記住帳號密碼」登入後，完全關閉 app 再開啟，帳號與密碼已填好。
- [ ] 取消勾選後登入，關閉再開啟，欄位是空的。
- [ ] 手機重新開機後，已記住的帳密仍在。

### 回到前景重連

檔案：`lib/ui/session_controller.dart`

- [ ] 登入後按 Home 鍵離開 app，等 1 分鐘再回來：自動重新連線並登入。
- [ ] 短暫切到其他 app 幾秒再回來：連線仍在，或自動重連，不會卡在斷線畫面。
- [ ] 開啟飛航模式：一段時間內出現「已斷線」。若遲遲沒有出現，需要在 `lib/core/connection/ws_connection.dart` 加上連線存活偵測。
- [ ] 斷線後選「繼續瀏覽」，離開 app 再回來：維持離線，不會自動重連。

### 手勢

檔案：`lib/ui/terminal_surface.dart`、`lib/core/input/swipe.dart`

- [ ] 向右滑返回上一層，向左滑進入，向上滑下一頁，向下滑上一頁。
- [ ] 滑動的手感：不會太容易誤觸，也不需要滑很長。需要調整時改 `classifySwipe` 的 `minDistance`。
- [ ] 從螢幕左邊緣向右滑：確認是送出返回鍵，而不是被系統的返回手勢攔截並離開終端機頁。
- [ ] 雙指可放大到 4 倍，放大後單指可拖曳，縮回原大小後滑動手勢恢復。
- [ ] 長按並拖曳可選取文字，放開後出現「已複製」，貼到備忘錄確認內容正確。
- [ ] 點一下文章中的網址，以 Safari 開啟。

### 字體與顯示

檔案：`lib/ui/terminal_painter.dart`

- [ ] 直向時 80 欄的中文字可以辨識。
- [ ] 英文字母與數字沒有壓到相鄰的字，也沒有被壓得太扁。太扁時在 `_fonts` 之外為半形字指定等寬字型。
- [ ] 色塊圖案相鄰處沒有細縫。
- [ ] 橫向時畫面自動變大，旋轉過程沒有錯亂。
- [ ] 游標的底線在輸入帳號的位置閃爍。
- [ ] 瀏海或動態島沒有遮住畫面內容。

## 回報問題

檢查清單中沒通過的項目，記下操作步驟與實際看到的畫面，回到 Windows 後再修正。修正後在 Mac 上只需要：

```
git pull
flutter run --release
```
````

- [ ] **Step 5: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/project_metadata_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit 並推送**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add docs/ios-build.md README.md pubspec.yaml ios/Runner/Info.plist test/project_metadata_test.dart
git commit -m "docs: add iOS build guide and project readme"
git push -u origin feat/mobile-terminal
```

---

## 本計畫完成後的狀態

- Windows 上可完整操作的 PTT 用戶端：登入頁、自動登入、滑動與縮放、選取複製、開啟連結、中文輸入、按鍵列、斷線處理與離線檢視、防閒置。
- iOS 版尚未建置過。`docs/ios-build.md` 列出借到 Mac 後的步驟與實機檢查清單。
- 未登入的網頁瀏覽屬於計畫三。
