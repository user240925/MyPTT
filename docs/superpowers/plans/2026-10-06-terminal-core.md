# MyPTT 終端機核心 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 上做出可實際連上 PTT、正確顯示彩色畫面、可用實體鍵盤操作的 Flutter 程式，其連線與終端機核心為純 Dart 並有單元測試。

**Architecture:** 連線層收送位元組；Telnet 過濾器處理協商；終端機把位元組寫進 80×24 的畫面緩衝；介面層把緩衝畫出來。畫面緩衝每一欄存「原始位元組加屬性」，Big5 轉 Unicode 只在取出一列的字形時發生，這樣雙色字與被切開的全形字都不需要特殊處理。

**Tech Stack:** Flutter stable（Dart 3）、`dart:io` WebSocket、`flutter_test`。不加任何第三方套件。

**Spec:** `docs/superpowers/specs/2026-10-06-myptt-ios-design.md`

**本計畫的範圍：** 規格第 9 節的步驟 1 到 4（工具鏈、連線層、終端機核心、畫面繪製），加上實體鍵盤輸入以便在 Windows 上操作。步驟 5 到 7（手勢、按鍵列、輸入法、登入頁、重連、防閒置、離線瀏覽、iOS 建置文件）在本計畫完成後另寫第二份計畫，因為它們依賴這裡定下的實際介面。

## Global Constraints

- 連線網址固定為 `wss://ws.ptt.cc/bbs`。
- 連線必須帶 `Origin: app://pcman`，不帶會被 PTT 以 HTTP 403 拒絕。
- 資料為 WebSocket 二進位訊息，文字編碼為 Big5（UAO 2.50），不是 UTF-8。
- 畫面大小固定 80 欄 × 24 列。
- `lib/core/` 底下為純 Dart，不得 import `package:flutter` 或 `dart:ui`。
- 授權為 GPL 第 2 版。PCMan 原始碼不放進本 repo。
- 核心層遇到異常資料一律不當機：無法辨識的控制碼略過，無對應的 Big5 字碼顯示為 U+FFFD。
- 從 PTT 實際錄下的資料不進 git。測試資料一律手寫。
- 所有指令在 repo 根目錄 `C:\Project\MyPTT` 執行。若 `flutter` 不在 PATH，改用 `C:\dev\flutter\bin\flutter.bat` 與 `C:\dev\flutter\bin\dart.bat`。
- 每個 Task 結束前執行 `flutter analyze`，必須沒有 error。
- Commit 訊息結尾加上 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 一個全形字的兩個位元組分屬兩個 WebSocket 訊息：應顯示為一個完整的字。（Task 4 測試 `wide char split across feeds`）
2. 一個控制碼被切在兩個訊息之間：應視為同一個控制碼。（Task 4 測試 `escape sequence split across feeds`）
3. 游標參數超出畫面（例如 `ESC[99;999H`）：應夾在畫面邊界內，不當機。（Task 4 測試 `out-of-range cursor is clamped`）
4. 落單的 Big5 前導位元組（在列尾，或後面接的不是合法的第二位元組）：應顯示 U+FFFD，後續字元不受影響。（Task 4 測試 `lone lead byte`）
5. 畸形或超長的控制碼：應略過並回到正常狀態，後續文字照常顯示。（Task 4 測試 `garbage CSI is ignored`）

## File Structure

| 檔案 | 職責 |
|---|---|
| `tool/gen_uao_tables.dart` | 下載 UAO 對照表文字檔，產生二進位表 |
| `assets/uao/b2u.bin`、`assets/uao/u2b.bin` | Big5 與 Unicode 的雙向對照表 |
| `lib/core/encoding/big5_codec.dart` | Big5 與 Unicode 的轉換，全專案唯一碰編碼的地方 |
| `lib/core/terminal/screen_buffer.dart` | 畫面緩衝與屬性位元定義 |
| `lib/core/terminal/row_glyphs.dart` | 把緩衝的一列轉成字形清單 |
| `lib/core/terminal/terminal.dart` | ANSI／VT100 控制碼解析 |
| `lib/core/terminal/telnet_filter.dart` | Telnet 協商 |
| `lib/core/terminal/term_keys.dart` | 特殊按鍵對應的位元組 |
| `lib/core/connection/connection.dart` | 連線介面 |
| `lib/core/connection/ws_connection.dart` | WebSocket 實作 |
| `lib/core/recognition/screen_recognizer.dart` | 畫面辨識介面（僅定義，不實作規則） |
| `lib/core/session.dart` | 把連線、Telnet、終端機接在一起 |
| `lib/ui/palette.dart` | 16 色與屬性到顏色的換算 |
| `lib/ui/glyph_shapes.dart` | 色塊、三角形、框線字元的圖形繪製 |
| `lib/ui/terminal_painter.dart` | 把畫面緩衝畫到畫布 |
| `lib/ui/terminal_view.dart` | 終端機元件與實體鍵盤輸入 |
| `lib/main.dart` | 啟動、載入對照表、連線 |
| `tool/ptt_probe.dart` | 對真實 PTT 的手動驗證工具 |
| `test/support/fake_connection.dart` | 測試用假連線 |

---

### Task 1: 工具鏈與專案骨架

**Files:**
- Create: Flutter 專案骨架（`pubspec.yaml`、`lib/main.dart`、`windows/`、`ios/` 等，由 `flutter create` 產生）
- Create: `LICENSE`
- Modify: `.gitignore`
- Delete: `test/widget_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: 套件名稱 `myptt`（後續 import 皆為 `package:myptt/...`）；分支 `feat/terminal-core`

- [ ] **Step 1: 建立分支**

```bash
git checkout -b feat/terminal-core
```

- [ ] **Step 2: 安裝 Flutter SDK**

```bash
git clone https://github.com/flutter/flutter.git -b stable --depth 1 /c/dev/flutter
/c/dev/flutter/bin/flutter.bat --version
```

Expected: 印出 Flutter 與 Dart 的版本號，Dart 版本為 3.x。

- [ ] **Step 3: 檢查環境**

```bash
/c/dev/flutter/bin/flutter.bat doctor
```

Expected: `Flutter` 一項為勾。`Visual Studio - develop Windows apps` 一項若顯示缺少「Desktop development with C++」，表示使用者尚未在 Visual Studio Installer 加裝該工作負載；這不影響 Task 1 到 Task 6，只影響 Task 7 的 Windows 執行，記錄下來繼續。

- [ ] **Step 4: 產生專案**

```bash
/c/dev/flutter/bin/flutter.bat create --platforms=windows,ios --org com.github.user240925 --project-name myptt .
```

Expected: 結尾顯示 `All done!`。

- [ ] **Step 5: 修正 `.gitignore` 並移除範例測試**

確認 `.gitignore` 內仍有 `nul` 這一行；若被覆寫掉則在檔尾補回：

```
# Windows reserved-name artifact created by Git Bash
nul
```

```bash
rm test/widget_test.dart
```

- [ ] **Step 6: 加入授權檔**

```bash
curl -sL https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt -o LICENSE
head -3 LICENSE
```

Expected: 出現 `GNU GENERAL PUBLIC LICENSE` 與 `Version 2, June 1991`。

- [ ] **Step 7: 確認骨架可分析**

```bash
/c/dev/flutter/bin/flutter.bat analyze
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter project for Windows and iOS"
```

---

### Task 2: UAO 對照表與 Big5 轉換

**Files:**
- Create: `tool/gen_uao_tables.dart`
- Create: `assets/uao/b2u.bin`、`assets/uao/u2b.bin`、`assets/uao/README.md`
- Create: `lib/core/encoding/big5_codec.dart`
- Modify: `pubspec.yaml`（`flutter:` 區段加入 assets）
- Test: `test/core/encoding/big5_codec_test.dart`

**Interfaces:**
- Consumes: 無
- Produces:
  - `class Big5Codec { Big5Codec(Uint8List b2u, Uint8List u2b); static const int replacement = 0xFFFD; static bool isLead(int b); static bool isTrail(int b); int decodePair(int lead, int trail); EncodeResult encode(String text); }`
  - `class EncodeResult { final Uint8List bytes; final int unmappable; }`
  - 表格格式：`b2u.bin` 為 126×191 個小端序 uint16，索引 `(lead-0x81)*191 + (trail-0x40)`，0 表示無對應；`u2b.bin` 為 65536 個小端序 uint16，索引為 Unicode 碼位，值為 Big5 碼（高位元組為前導），0 表示無對應。

- [ ] **Step 1: 寫產生工具**

`tool/gen_uao_tables.dart`：

```dart
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
```

- [ ] **Step 2: 產生表格**

```bash
/c/dev/flutter/bin/dart.bat run tool/gen_uao_tables.dart
```

Expected: `b2u.bin 48132 bytes, u2b.bin 131072 bytes`

- [ ] **Step 3: 記錄表格來源並登記為 asset**

`assets/uao/README.md`：

```markdown
# UAO 對照表

`b2u.bin` 與 `u2b.bin` 由 `tool/gen_uao_tables.dart` 產生，來源為：

- https://moztw.org/docs/big5/table/uao250-b2u.txt
- https://moztw.org/docs/big5/table/uao250-u2b.txt

重新產生：`dart run tool/gen_uao_tables.dart`
```

在 `pubspec.yaml` 的 `flutter:` 區段（`uses-material-design: true` 之下）加入：

```yaml
  assets:
    - assets/uao/b2u.bin
    - assets/uao/u2b.bin
```

- [ ] **Step 4: 寫失敗的測試**

`test/core/encoding/big5_codec_test.dart`：

```dart
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
```

- [ ] **Step 5: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/encoding/big5_codec_test.dart
```

Expected: FAIL，訊息為找不到 `package:myptt/core/encoding/big5_codec.dart`。

- [ ] **Step 6: 實作**

`lib/core/encoding/big5_codec.dart`：

```dart
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
```

- [ ] **Step 7: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/encoding/big5_codec_test.dart
```

Expected: `All tests passed!`。若 `round-trips` 因某個字在 UAO 中沒有對應而失敗，從測試字串移除該字，不要改動轉換邏輯。

- [ ] **Step 8: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
git add tool/gen_uao_tables.dart assets/uao pubspec.yaml lib/core/encoding test/core/encoding
git commit -m "feat: add Big5/UAO codec and generated tables"
```

---

### Task 3: 畫面緩衝

**Files:**
- Create: `lib/core/terminal/screen_buffer.dart`
- Test: `test/core/terminal/screen_buffer_test.dart`

**Interfaces:**
- Consumes: 無
- Produces:
  - `abstract final class Attr`：常數 `fgMask = 0x07`、`bright = 0x08`、`bgShift = 4`、`bgMask = 0x70`、`blink = 0x80`、`underline = 0x100`、`inverse = 0x200`、`normal = 0x07`；靜態方法 `int fg(int a)`、`int bg(int a)`。
  - `class ScreenBuffer { ScreenBuffer({int cols = 80, int rows = 24}); final int cols, rows; final Uint8List bytes; final Uint16List attrs; int cursorRow, cursorCol, scrollTop, scrollBottom; int byteAt(int row, int col); int attrAt(int row, int col); void moveTo(int row, int col); void put(int byte, int attr); void lineFeed(); void reverseLineFeed(); void setScrollRegion(int top, int bottom); void scrollUp(int n, {int? top, int? bottom}); void scrollDown(int n, {int? top, int? bottom}); void insertLines(int n); void deleteLines(int n); void insertChars(int n); void deleteChars(int n); void eraseInLine(int mode); void eraseInDisplay(int mode); }`
  - 列與欄皆從 0 起算。`cursorCol` 可以等於 `cols`，表示已寫滿一列、下一個字要換行。

- [ ] **Step 1: 寫失敗的測試**

`test/core/terminal/screen_buffer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';

String rowText(ScreenBuffer s, int r) =>
    String.fromCharCodes(s.bytes.sublist(r * s.cols, (r + 1) * s.cols))
        .trimRight();

void write(ScreenBuffer s, String text) {
  for (final c in text.codeUnits) {
    s.put(c, Attr.normal);
  }
}

ScreenBuffer withRows(List<String> rows) {
  final s = ScreenBuffer(cols: 10, rows: 5);
  for (var r = 0; r < rows.length; r++) {
    s.moveTo(r, 0);
    write(s, rows[r]);
  }
  return s;
}

void main() {
  test('starts blank with default attributes', () {
    final s = ScreenBuffer();
    expect(s.cols, 80);
    expect(s.rows, 24);
    expect(s.byteAt(23, 79), 0x20);
    expect(s.attrAt(0, 0), Attr.normal);
    expect(s.scrollBottom, 23);
  });

  test('put writes at the cursor and advances', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.put(0x41, 0x1F);
    expect(s.byteAt(0, 0), 0x41);
    expect(s.attrAt(0, 0), 0x1F);
    expect(s.cursorCol, 1);
  });

  test('put wraps only when the next character arrives', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    write(s, '0123456789');
    expect(s.cursorRow, 0);
    expect(s.cursorCol, 10);
    write(s, 'X');
    expect(rowText(s, 0), '0123456789');
    expect(rowText(s, 1), 'X');
  });

  test('moveTo clamps to the screen', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.moveTo(99, 99);
    expect(s.cursorRow, 4);
    expect(s.cursorCol, 9);
    s.moveTo(-3, -3);
    expect(s.cursorRow, 0);
    expect(s.cursorCol, 0);
  });

  test('lineFeed at the bottom scrolls the screen up', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.moveTo(4, 0);
    s.lineFeed();
    expect(rowText(s, 0), 'R1');
    expect(rowText(s, 3), 'R4');
    expect(rowText(s, 4), '');
    expect(s.cursorRow, 4);
  });

  test('lineFeed respects the scroll region', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.setScrollRegion(1, 3);
    s.moveTo(3, 0);
    s.lineFeed();
    expect(rowText(s, 0), 'R0');
    expect(rowText(s, 1), 'R2');
    expect(rowText(s, 2), 'R3');
    expect(rowText(s, 3), '');
    expect(rowText(s, 4), 'R4');
  });

  test('reverseLineFeed at the top scrolls down', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.moveTo(0, 0);
    s.reverseLineFeed();
    expect(rowText(s, 0), '');
    expect(rowText(s, 1), 'R0');
    expect(rowText(s, 4), 'R3');
  });

  test('an invalid scroll region resets to the full screen', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.setScrollRegion(3, 1);
    expect(s.scrollTop, 0);
    expect(s.scrollBottom, 4);
  });

  test('insertLines and deleteLines shift rows below the cursor', () {
    final a = withRows(['R0', 'R1', 'R2']);
    a.moveTo(1, 0);
    a.insertLines(1);
    expect(rowText(a, 1), '');
    expect(rowText(a, 2), 'R1');
    expect(rowText(a, 3), 'R2');

    final b = withRows(['R0', 'R1', 'R2']);
    b.moveTo(1, 0);
    b.deleteLines(1);
    expect(rowText(b, 1), 'R2');
    expect(rowText(b, 2), '');
  });

  test('insertChars and deleteChars shift within the row', () {
    final a = withRows(['ABCDE']);
    a.moveTo(0, 1);
    a.insertChars(2);
    expect(rowText(a, 0), 'A  BCDE');

    final b = withRows(['ABCDE']);
    b.moveTo(0, 1);
    b.deleteChars(2);
    expect(rowText(b, 0), 'ADE');
  });

  test('eraseInLine modes', () {
    final a = withRows(['ABCDE'])..moveTo(0, 2);
    a.eraseInLine(0);
    expect(rowText(a, 0), 'AB');

    final b = withRows(['ABCDE'])..moveTo(0, 2);
    b.eraseInLine(1);
    expect(rowText(b, 0), '   DE');

    final c = withRows(['ABCDE'])..moveTo(0, 2);
    c.eraseInLine(2);
    expect(rowText(c, 0), '');
  });

  test('eraseInDisplay modes', () {
    final a = withRows(['AAAAA', 'BBBBB', 'CCCCC'])..moveTo(1, 2);
    a.eraseInDisplay(0);
    expect(rowText(a, 0), 'AAAAA');
    expect(rowText(a, 1), 'BB');
    expect(rowText(a, 2), '');

    final b = withRows(['AAAAA', 'BBBBB', 'CCCCC'])..moveTo(1, 2);
    b.eraseInDisplay(1);
    expect(rowText(b, 0), '');
    expect(rowText(b, 1), '   BB');
    expect(rowText(b, 2), 'CCCCC');

    final c = withRows(['AAAAA', 'BBBBB'])..moveTo(1, 2);
    c.eraseInDisplay(2);
    expect(rowText(c, 0), '');
    expect(rowText(c, 1), '');
  });

  test('oversized counts are clamped instead of throwing', () {
    final s = withRows(['R0', 'R1', 'R2']);
    s.moveTo(1, 3);
    s.insertLines(999);
    s.deleteLines(999);
    s.insertChars(999);
    s.deleteChars(999);
    s.scrollUp(999);
    s.scrollDown(999);
    expect(rowText(s, 0), '');
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/screen_buffer_test.dart
```

Expected: FAIL，訊息為找不到 `screen_buffer.dart`。

- [ ] **Step 3: 實作**

`lib/core/terminal/screen_buffer.dart`：

```dart
import 'dart:typed_data';

/// Attribute bits stored for each column.
abstract final class Attr {
  static const int fgMask = 0x07;
  static const int bright = 0x08;
  static const int bgShift = 4;
  static const int bgMask = 0x70;
  static const int blink = 0x80;
  static const int underline = 0x100;
  static const int inverse = 0x200;

  /// Light grey on black.
  static const int normal = 0x07;

  static int fg(int a) => a & fgMask;
  static int bg(int a) => (a & bgMask) >> bgShift;
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// A grid of raw bytes plus attributes, one entry per column. A full-width
/// character occupies two columns, one byte each, so its halves can carry
/// different attributes.
class ScreenBuffer {
  ScreenBuffer({this.cols = 80, this.rows = 24})
      : bytes = Uint8List(cols * rows),
        attrs = Uint16List(cols * rows),
        scrollBottom = rows - 1 {
    _blank(0, cols * rows);
  }

  final int cols;
  final int rows;
  final Uint8List bytes;
  final Uint16List attrs;

  int cursorRow = 0;

  /// May equal [cols] after the last column is written; the next [put] wraps.
  int cursorCol = 0;
  int scrollTop = 0;
  int scrollBottom;

  int byteAt(int row, int col) => bytes[row * cols + col];
  int attrAt(int row, int col) => attrs[row * cols + col];

  int get _col => _clamp(cursorCol, 0, cols - 1);

  void _blank(int start, int end) {
    bytes.fillRange(start, end, 0x20);
    attrs.fillRange(start, end, Attr.normal);
  }

  void moveTo(int row, int col) {
    cursorRow = _clamp(row, 0, rows - 1);
    cursorCol = _clamp(col, 0, cols - 1);
  }

  void put(int byte, int attr) {
    if (cursorCol >= cols) {
      cursorCol = 0;
      lineFeed();
    }
    final i = cursorRow * cols + cursorCol;
    bytes[i] = byte;
    attrs[i] = attr;
    cursorCol++;
  }

  void lineFeed() {
    if (cursorRow == scrollBottom) {
      scrollUp(1);
    } else if (cursorRow < rows - 1) {
      cursorRow++;
    }
  }

  void reverseLineFeed() {
    if (cursorRow == scrollTop) {
      scrollDown(1);
    } else if (cursorRow > 0) {
      cursorRow--;
    }
  }

  void setScrollRegion(int top, int bottom) {
    if (top < 0 || bottom >= rows || top >= bottom) {
      scrollTop = 0;
      scrollBottom = rows - 1;
    } else {
      scrollTop = top;
      scrollBottom = bottom;
    }
  }

  void scrollUp(int n, {int? top, int? bottom}) {
    final t = top ?? scrollTop, b = bottom ?? scrollBottom;
    if (t > b) return;
    final count = _clamp(n, 1, b - t + 1);
    final keepEnd = (b + 1 - count) * cols;
    bytes.setRange(t * cols, keepEnd, bytes, (t + count) * cols);
    attrs.setRange(t * cols, keepEnd, attrs, (t + count) * cols);
    _blank(keepEnd, (b + 1) * cols);
  }

  void scrollDown(int n, {int? top, int? bottom}) {
    final t = top ?? scrollTop, b = bottom ?? scrollBottom;
    if (t > b) return;
    final count = _clamp(n, 1, b - t + 1);
    bytes.setRange((t + count) * cols, (b + 1) * cols, bytes, t * cols);
    attrs.setRange((t + count) * cols, (b + 1) * cols, attrs, t * cols);
    _blank(t * cols, (t + count) * cols);
  }

  void insertLines(int n) {
    if (cursorRow < scrollTop || cursorRow > scrollBottom) return;
    scrollDown(n, top: cursorRow);
  }

  void deleteLines(int n) {
    if (cursorRow < scrollTop || cursorRow > scrollBottom) return;
    scrollUp(n, top: cursorRow);
  }

  void insertChars(int n) {
    final from = cursorRow * cols + _col, end = (cursorRow + 1) * cols;
    final count = _clamp(n, 1, end - from);
    bytes.setRange(from + count, end, bytes, from);
    attrs.setRange(from + count, end, attrs, from);
    _blank(from, from + count);
  }

  void deleteChars(int n) {
    final from = cursorRow * cols + _col, end = (cursorRow + 1) * cols;
    final count = _clamp(n, 1, end - from);
    bytes.setRange(from, end - count, bytes, from + count);
    attrs.setRange(from, end - count, attrs, from + count);
    _blank(end - count, end);
  }

  /// 0: cursor to end of line. 1: start of line through cursor. 2: whole line.
  void eraseInLine(int mode) {
    final rowStart = cursorRow * cols;
    switch (mode) {
      case 1:
        _blank(rowStart, rowStart + _col + 1);
      case 2:
        _blank(rowStart, rowStart + cols);
      default:
        _blank(rowStart + _col, rowStart + cols);
    }
  }

  /// 0: cursor to end of screen. 1: start of screen through cursor. 2: all.
  void eraseInDisplay(int mode) {
    final pos = cursorRow * cols + _col;
    switch (mode) {
      case 1:
        _blank(0, pos + 1);
      case 2:
        _blank(0, cols * rows);
      default:
        _blank(pos, cols * rows);
    }
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/screen_buffer_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
git add lib/core/terminal/screen_buffer.dart test/core/terminal/screen_buffer_test.dart
git commit -m "feat: add terminal screen buffer"
```

---

### Task 4: 控制碼解析與字形輸出

**Files:**
- Create: `lib/core/terminal/terminal.dart`
- Create: `lib/core/terminal/row_glyphs.dart`
- Test: `test/core/terminal/terminal_test.dart`

**Interfaces:**
- Consumes: `ScreenBuffer`、`Attr`（Task 3）；`Big5Codec`（Task 2）
- Produces:
  - `class Terminal { Terminal(ScreenBuffer screen, {void Function(List<int> bytes)? onReply}); final ScreenBuffer screen; int attr; void feed(List<int> data); }`
  - `class Glyph { final int col; final int width; final int codePoint; final int leftAttr; final int rightAttr; }`（`width` 為 1 或 2）
  - `List<Glyph> glyphsOfRow(ScreenBuffer s, int row, Big5Codec codec)`
  - `String rowString(ScreenBuffer s, int row, Big5Codec codec)`（去除尾端空白）

支援的控制碼（依 PCMan 的 `ProcessAnsiEscapeSequence` 與 `OnText`）：

| 序列 | 動作 |
|---|---|
| CR、LF、BS、TAB | 回行首、換行、退一格、跳到下一個 8 的倍數欄 |
| `ESC D`、`ESC M`、`ESC E` | 換行、反向換行、回行首並換行 |
| `ESC 7`、`ESC 8`、`CSI s`、`CSI u` | 儲存與還原游標位置和屬性 |
| `CSI n m` | 0 重設、1 高亮、4 底線、5 閃爍、7 反白、30–37 前景、40–47 背景、39／49 預設前景／背景 |
| `CSI r;c H`、`CSI r;c f` | 移動游標（1 起算） |
| `CSI n A/B/C/D` | 上、下、右、左移 n 格 |
| `CSI n G`、`CSI n d` | 移到第 n 欄、第 n 列 |
| `CSI n J`、`CSI n K` | 清除畫面、清除行 |
| `CSI n L/M/@/P` | 插入行、刪除行、插入字元、刪除字元 |
| `CSI t;b r` | 設定捲動區域並把游標移到左上角 |
| `CSI 6 n`、`CSI 5 n` | 回報游標位置 `ESC[row;colR`、回報狀態 `ESC[0n` |

- [ ] **Step 1: 寫失敗的測試**

`test/core/terminal/terminal_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/terminal.dart';

const esc = '\x1b';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late ScreenBuffer screen;
  late Terminal term;
  late List<int> replies;

  setUp(() {
    screen = ScreenBuffer();
    replies = [];
    term = Terminal(screen, onReply: replies.addAll);
  });

  void feed(String s) => term.feed(s.codeUnits);
  String row(int r) => rowString(screen, r, codec);

  test('plain text with CR LF', () {
    feed('Hello\r\nWorld');
    expect(row(0), 'Hello');
    expect(row(1), 'World');
    expect(screen.cursorRow, 1);
    expect(screen.cursorCol, 5);
  });

  test('backspace and tab', () {
    feed('AB\bC\tD');
    expect(row(0), 'AC      D');
  });

  test('cursor positioning is one-based', () {
    feed('$esc[5;10HX');
    expect(screen.byteAt(4, 9), 0x58);
    feed('$esc[HY');
    expect(screen.byteAt(0, 0), 0x59);
  });

  test('relative cursor movement defaults to one', () {
    feed('$esc[10;10H$esc[A$esc[2B$esc[C$esc[3D');
    expect(screen.cursorRow, 10);
    expect(screen.cursorCol, 7);
  });

  test('SGR sets and resets attributes', () {
    feed('$esc[1;33;44mA$esc[mB$esc[5;7mC');
    final a = screen.attrAt(0, 0);
    expect(Attr.fg(a), 3);
    expect(Attr.bg(a), 4);
    expect(a & Attr.bright, isNot(0));
    expect(screen.attrAt(0, 1), Attr.normal);
    final c = screen.attrAt(0, 2);
    expect(c & Attr.blink, isNot(0));
    expect(c & Attr.inverse, isNot(0));
  });

  test('erase line and erase display', () {
    feed('ABCDE$esc[1;3H$esc[K');
    expect(row(0), 'AB');
    feed('$esc[2;1HXYZ$esc[2J');
    expect(row(0), '');
    expect(row(1), '');
  });

  test('text wraps at column 80', () {
    feed('A' * 80);
    expect(screen.cursorRow, 0);
    feed('B');
    expect(row(0), 'A' * 80);
    expect(row(1), 'B');
  });

  test('line feed on the last row scrolls', () {
    feed([for (var i = 0; i < 25; i++) 'L$i'].join('\r\n'));
    expect(row(0), 'L1');
    expect(row(23), 'L24');
  });

  test('scroll region limits scrolling', () {
    feed('R0\r\nR1\r\nR2\r\nR3\r\nR4');
    feed('$esc[2;4r');
    expect(screen.cursorRow, 0);
    feed('$esc[4;1H\n');
    expect(row(0), 'R0');
    expect(row(1), 'R2');
    expect(row(2), 'R3');
    expect(row(3), '');
    expect(row(4), 'R4');
  });

  test('insert and delete lines', () {
    feed('R0\r\nR1\r\nR2$esc[2;1H$esc[L');
    expect(row(1), '');
    expect(row(2), 'R1');
    expect(row(3), 'R2');
    feed('$esc[M');
    expect(row(1), 'R1');
    expect(row(2), 'R2');
  });

  test('insert and delete characters', () {
    feed('ABCDE$esc[1;2H$esc[2@');
    expect(row(0), 'A  BCDE');
    feed('$esc[2P');
    expect(row(0), 'ABCDE');
  });

  test('save and restore cursor and attributes', () {
    feed('$esc[3;4H$esc[31m${esc}7$esc[10;10H$esc[m${esc}8X');
    expect(screen.byteAt(2, 3), 0x58);
    expect(Attr.fg(screen.attrAt(2, 3)), 1);
    feed('$esc[5;6H$esc[s$esc[H$esc[uY');
    expect(screen.byteAt(4, 5), 0x59);
  });

  test('ESC D and ESC M move down and up', () {
    feed('$esc[3;1H${esc}D');
    expect(screen.cursorRow, 3);
    feed('${esc}M${esc}M');
    expect(screen.cursorRow, 1);
  });

  test('device status report replies with the cursor position', () {
    feed('$esc[3;7H$esc[6n');
    expect(String.fromCharCodes(replies), '$esc[3;7R');
  });

  test('decodes Big5 text into glyphs', () {
    term.feed([0x41, 0xA4, 0xA4, 0xA4, 0xE5, 0x42]);
    expect(row(0), 'A中文B');
    final g = glyphsOfRow(screen, 0, codec);
    expect(g[0].width, 1);
    expect(g[1].col, 1);
    expect(g[1].width, 2);
    expect(g[1].codePoint, 0x4E2D);
    expect(g[2].col, 3);
    expect(g[3].col, 5);
    expect(g.length, 78);
  });

  test('a colour change between the two bytes makes a two-colour glyph', () {
    term.feed([...'$esc[31m'.codeUnits, 0xA4, ...'$esc[32m'.codeUnits, 0xA4]);
    final g = glyphsOfRow(screen, 0, codec).first;
    expect(g.codePoint, 0x4E2D);
    expect(Attr.fg(g.leftAttr), 1);
    expect(Attr.fg(g.rightAttr), 2);
  });

  // Review Focus 1
  test('wide char split across feeds', () {
    term.feed([0xA4]);
    term.feed([0xA4]);
    expect(row(0), '中');
  });

  // Review Focus 2
  test('escape sequence split across feeds', () {
    feed(esc);
    feed('[1;3');
    feed('1mA');
    final a = screen.attrAt(0, 0);
    expect(Attr.fg(a), 1);
    expect(a & Attr.bright, isNot(0));
    expect(row(0), 'A');
  });

  // Review Focus 3
  test('out-of-range cursor is clamped', () {
    feed('$esc[99;999HX');
    expect(screen.byteAt(23, 79), 0x58);
    feed('$esc[0;0HY');
    expect(screen.byteAt(0, 0), 0x59);
    feed('$esc[999A$esc[999D$esc[999B$esc[999C');
    expect(screen.cursorRow, 23);
    expect(screen.cursorCol, 79);
  });

  // Review Focus 4
  test('lone lead byte', () {
    term.feed([0xA4, 0x31, 0x32]);
    final g = glyphsOfRow(screen, 0, codec);
    expect(g[0].codePoint, Big5Codec.replacement);
    expect(g[0].width, 1);
    expect(g[1].codePoint, 0x31);
    expect(g[2].codePoint, 0x32);

    feed('$esc[2;80H');
    term.feed([0xA4]);
    final last = glyphsOfRow(screen, 1, codec).last;
    expect(last.col, 79);
    expect(last.width, 1);
    expect(last.codePoint, Big5Codec.replacement);
  });

  // Review Focus 5
  test('garbage CSI is ignored', () {
    feed('$esc[${'9' * 500};${';' * 200}zA');
    feed('$esc[?25lB');
    feed('$esc[>0cC');
    feed('$esc${esc}[1mD');
    feed('$esc#E');
    expect(row(0), 'ABCDE');
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/terminal_test.dart
```

Expected: FAIL，訊息為找不到 `row_glyphs.dart` 與 `terminal.dart`。

- [ ] **Step 3: 實作字形輸出**

`lib/core/terminal/row_glyphs.dart`：

```dart
import '../encoding/big5_codec.dart';
import 'screen_buffer.dart';

class Glyph {
  const Glyph(this.col, this.width, this.codePoint, this.leftAttr, this.rightAttr);

  final int col;

  /// 1 for half-width, 2 for full-width.
  final int width;
  final int codePoint;
  final int leftAttr;

  /// Differs from [leftAttr] only for a two-colour full-width character.
  final int rightAttr;
}

List<Glyph> glyphsOfRow(ScreenBuffer s, int row, Big5Codec codec) {
  final out = <Glyph>[];
  var col = 0;
  while (col < s.cols) {
    final b = s.byteAt(row, col);
    final a = s.attrAt(row, col);
    if (b < 0x80) {
      out.add(Glyph(col, 1, b, a, a));
      col++;
    } else if (Big5Codec.isLead(b) &&
        col + 1 < s.cols &&
        Big5Codec.isTrail(s.byteAt(row, col + 1))) {
      final cp = codec.decodePair(b, s.byteAt(row, col + 1));
      out.add(Glyph(col, 2, cp, a, s.attrAt(row, col + 1)));
      col += 2;
    } else {
      out.add(Glyph(col, 1, Big5Codec.replacement, a, a));
      col++;
    }
  }
  return out;
}

String rowString(ScreenBuffer s, int row, Big5Codec codec) {
  final out = StringBuffer();
  for (final g in glyphsOfRow(s, row, codec)) {
    out.writeCharCode(g.codePoint);
  }
  return out.toString().trimRight();
}
```

- [ ] **Step 4: 實作控制碼解析**

`lib/core/terminal/terminal.dart`：

```dart
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
```

- [ ] **Step 5: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/terminal_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
git add lib/core/terminal/terminal.dart lib/core/terminal/row_glyphs.dart test/core/terminal/terminal_test.dart
git commit -m "feat: add ANSI terminal parser and glyph decoding"
```

---

### Task 5: Telnet 協商

**Files:**
- Create: `lib/core/terminal/telnet_filter.dart`
- Test: `test/core/terminal/telnet_filter_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: `class TelnetFilter { TelnetFilter({required void Function(List<int>) onData, required void Function(List<int>) onReply, int cols = 80, int rows = 24}); void feed(List<int> input); }`。`onData` 收到去除 Telnet 指令後的資料，每次 `feed` 最多呼叫一次。

協商規則照 PCMan 的 `OnIAC`：對方 `WILL ECHO`、`WILL SGA` 回 `DO`，其他 `WILL` 回 `DONT`；對方 `DO TERMINAL-TYPE` 回 `WILL`，`DO NAWS` 回 `WILL` 並接著送出視窗大小，其他 `DO` 回 `WONT`；對方詢問終端機類型時回 `VT100`。

- [ ] **Step 1: 寫失敗的測試**

`test/core/terminal/telnet_filter_test.dart`：

```dart
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
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/telnet_filter_test.dart
```

Expected: FAIL，訊息為找不到 `telnet_filter.dart`。

- [ ] **Step 3: 實作**

`lib/core/terminal/telnet_filter.dart`：

```dart
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
```

- [ ] **Step 4: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/terminal/telnet_filter_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
git add lib/core/terminal/telnet_filter.dart test/core/terminal/telnet_filter_test.dart
git commit -m "feat: add Telnet negotiation filter"
```

---

### Task 6: 連線層、工作階段、按鍵對應、畫面辨識介面

**Files:**
- Create: `lib/core/connection/connection.dart`
- Create: `lib/core/connection/ws_connection.dart`
- Create: `lib/core/terminal/term_keys.dart`
- Create: `lib/core/recognition/screen_recognizer.dart`
- Create: `lib/core/session.dart`
- Create: `tool/ptt_probe.dart`
- Create: `test/support/fake_connection.dart`
- Test: `test/core/session_test.dart`、`test/core/terminal/term_keys_test.dart`、`test/core/purity_test.dart`

**Interfaces:**
- Consumes: `ScreenBuffer`（Task 3）；`Terminal`、`rowString`（Task 4）；`TelnetFilter`（Task 5）；`Big5Codec`（Task 2）
- Produces:
  - `enum ConnectionStatus { disconnected, connecting, connected }`
  - `abstract class Connection { ConnectionStatus get status; Stream<ConnectionStatus> get statusChanges; Stream<Uint8List> get data; Future<void> connect(); void send(List<int> bytes); Future<void> close(); }`。`connect()` 失敗時丟出例外，且狀態回到 `disconnected`。
  - `class WsConnection implements Connection { WsConnection({Uri? uri, String origin = 'app://pcman'}); }`
  - `class TerminalSession { TerminalSession(Connection connection, Big5Codec codec, {int cols = 80, int rows = 24}); final Connection connection; final Big5Codec codec; final ScreenBuffer screen; ConnectionStatus get status; Stream<void> get updates; Future<void> connect(); void sendBytes(List<int> bytes); int sendText(String text); Future<void> dispose(); }`。`sendText` 回傳無法轉成 Big5 的字數。未連線時 `sendBytes` 與 `sendText` 不送出也不丟例外。
  - `enum TermKey { up, down, right, left, enter, backspace, tab, escape, home, end, pageUp, pageDown, insert, delete }`
  - `List<int> bytesForKey(TermKey key)`、`List<int>? bytesForCtrl(String letter)`
  - `enum ScreenKind { unknown }`、`abstract class ScreenRecognizer { ScreenKind recognize(ScreenBuffer screen); }`、`class NullScreenRecognizer implements ScreenRecognizer`
  - 測試用 `class FakeConnection implements Connection`，另有 `final List<int> sent`、`void emit(List<int> bytes)`、`void drop()`

- [ ] **Step 1: 寫連線介面與假連線**

`lib/core/connection/connection.dart`：

```dart
import 'dart:typed_data';

enum ConnectionStatus { disconnected, connecting, connected }

/// A byte pipe to the BBS. Implementations must be replaceable so the
/// terminal can be tested without a network.
abstract class Connection {
  ConnectionStatus get status;
  Stream<ConnectionStatus> get statusChanges;
  Stream<Uint8List> get data;

  /// Throws if the connection cannot be established; [status] is then
  /// [ConnectionStatus.disconnected].
  Future<void> connect();
  void send(List<int> bytes);
  Future<void> close();
}
```

`test/support/fake_connection.dart`：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:myptt/core/connection/connection.dart';

class FakeConnection implements Connection {
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final _status = StreamController<ConnectionStatus>.broadcast(sync: true);

  /// Everything passed to [send], in order.
  final List<int> sent = [];

  @override
  ConnectionStatus status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _status.stream;

  @override
  Future<void> connect() async => _set(ConnectionStatus.connected);

  @override
  void send(List<int> bytes) => sent.addAll(bytes);

  @override
  Future<void> close() async => _set(ConnectionStatus.disconnected);

  /// Simulates bytes arriving from the server.
  void emit(List<int> bytes) => _data.add(Uint8List.fromList(bytes));

  /// Simulates the server dropping the connection.
  void drop() => _set(ConnectionStatus.disconnected);

  void _set(ConnectionStatus s) {
    status = s;
    _status.add(s);
  }
}
```

- [ ] **Step 2: 寫失敗的測試**

`test/core/session_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/recognition/screen_recognizer.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;

  setUp(() {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
  });

  tearDown(() => session.dispose());

  test('incoming bytes reach the screen and fire an update', () async {
    var updates = 0;
    session.updates.listen((_) => updates++);
    await session.connect();
    final before = updates;
    conn.emit([0x48, 0x69, 0xA4, 0xA4]);
    expect(rowString(session.screen, 0, codec), 'Hi中');
    expect(updates, before + 1);
  });

  test('status follows the connection and fires an update', () async {
    var updates = 0;
    session.updates.listen((_) => updates++);
    expect(session.status, ConnectionStatus.disconnected);
    await session.connect();
    expect(session.status, ConnectionStatus.connected);
    conn.drop();
    expect(session.status, ConnectionStatus.disconnected);
    expect(updates, 2);
  });

  test('telnet negotiation is answered through the connection', () async {
    await session.connect();
    conn.emit([255, 253, 31]);
    expect(conn.sent, [255, 251, 31, 255, 250, 31, 0, 80, 0, 24, 255, 240]);
  });

  test('cursor position report is answered through the connection', () async {
    await session.connect();
    conn.emit('\x1b[2;3H\x1b[6n'.codeUnits);
    expect(String.fromCharCodes(conn.sent), '\x1b[2;3R');
  });

  test('sendText encodes to Big5 and reports unmappable characters', () async {
    await session.connect();
    expect(session.sendText('a中'), 0);
    expect(conn.sent, [0x61, 0xA4, 0xA4]);
    conn.sent.clear();
    expect(session.sendText('😀'), 1);
    expect(conn.sent, [0x3F]);
  });

  test('sending while disconnected is dropped without throwing', () {
    session.sendBytes([0x41]);
    expect(session.sendText('中'), 0);
    expect(conn.sent, isEmpty);
  });

  test('the screen keeps its content after a disconnect', () async {
    await session.connect();
    conn.emit('still here'.codeUnits);
    conn.drop();
    expect(rowString(session.screen, 0, codec), 'still here');
  });

  test('the placeholder recogniser reports unknown', () {
    expect(NullScreenRecognizer().recognize(session.screen), ScreenKind.unknown);
  });
}
```

`test/core/terminal/term_keys_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/term_keys.dart';

void main() {
  test('arrow keys', () {
    expect(bytesForKey(TermKey.up), '\x1b[A'.codeUnits);
    expect(bytesForKey(TermKey.down), '\x1b[B'.codeUnits);
    expect(bytesForKey(TermKey.right), '\x1b[C'.codeUnits);
    expect(bytesForKey(TermKey.left), '\x1b[D'.codeUnits);
  });

  test('editing and navigation keys', () {
    expect(bytesForKey(TermKey.enter), [0x0D]);
    expect(bytesForKey(TermKey.backspace), [0x08]);
    expect(bytesForKey(TermKey.tab), [0x09]);
    expect(bytesForKey(TermKey.escape), [0x1B]);
    expect(bytesForKey(TermKey.home), '\x1b[1~'.codeUnits);
    expect(bytesForKey(TermKey.insert), '\x1b[2~'.codeUnits);
    expect(bytesForKey(TermKey.delete), '\x1b[3~'.codeUnits);
    expect(bytesForKey(TermKey.end), '\x1b[4~'.codeUnits);
    expect(bytesForKey(TermKey.pageUp), '\x1b[5~'.codeUnits);
    expect(bytesForKey(TermKey.pageDown), '\x1b[6~'.codeUnits);
  });

  test('every key has a mapping', () {
    for (final k in TermKey.values) {
      expect(bytesForKey(k), isNotEmpty);
    }
  });

  test('control combinations', () {
    expect(bytesForCtrl('p'), [0x10]);
    expect(bytesForCtrl('X'), [0x18]);
    expect(bytesForCtrl('1'), isNull);
    expect(bytesForCtrl(''), isNull);
    expect(bytesForCtrl('ab'), isNull);
  });
}
```

`test/core/purity_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/core does not depend on Flutter', () {
    final offenders = Directory('lib/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final src = f.readAsStringSync();
      return src.contains("'package:flutter") || src.contains("'dart:ui'");
    }).map((f) => f.path);
    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/session_test.dart test/core/terminal/term_keys_test.dart
```

Expected: FAIL，訊息為找不到 `session.dart`、`screen_recognizer.dart`、`term_keys.dart`。

- [ ] **Step 4: 實作按鍵對應與畫面辨識介面**

`lib/core/terminal/term_keys.dart`：

```dart
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
```

`lib/core/recognition/screen_recognizer.dart`：

```dart
import '../terminal/screen_buffer.dart';

/// Kinds of BBS screen the app can tell apart. Only [unknown] exists for now;
/// native views for specific screens will add values here.
enum ScreenKind { unknown }

abstract class ScreenRecognizer {
  ScreenKind recognize(ScreenBuffer screen);
}

class NullScreenRecognizer implements ScreenRecognizer {
  @override
  ScreenKind recognize(ScreenBuffer screen) => ScreenKind.unknown;
}
```

- [ ] **Step 5: 實作工作階段**

`lib/core/session.dart`：

```dart
import 'dart:async';

import 'connection/connection.dart';
import 'encoding/big5_codec.dart';
import 'terminal/screen_buffer.dart';
import 'terminal/telnet_filter.dart';
import 'terminal/terminal.dart';

/// Wires a [Connection] to a terminal and exposes the resulting screen.
class TerminalSession {
  TerminalSession(this.connection, this.codec, {int cols = 80, int rows = 24})
      : screen = ScreenBuffer(cols: cols, rows: rows) {
    _terminal = Terminal(screen, onReply: sendBytes);
    _telnet = TelnetFilter(
      onData: (bytes) {
        _terminal.feed(bytes);
        _updates.add(null);
      },
      onReply: sendBytes,
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

  ConnectionStatus get status => connection.status;

  /// Fires whenever the screen content or the connection status changes.
  Stream<void> get updates => _updates.stream;

  Future<void> connect() => connection.connect();

  void sendBytes(List<int> bytes) {
    if (connection.status != ConnectionStatus.connected) return;
    connection.send(bytes);
  }

  /// Returns the number of characters that had no Big5 mapping.
  int sendText(String text) {
    if (connection.status != ConnectionStatus.connected) return 0;
    final encoded = codec.encode(text);
    connection.send(encoded.bytes);
    return encoded.unmappable;
  }

  Future<void> dispose() async {
    await _dataSub.cancel();
    await _statusSub.cancel();
    await connection.close();
    await _updates.close();
  }
}
```

- [ ] **Step 6: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core
```

Expected: `All tests passed!`

- [ ] **Step 7: 實作 WebSocket 連線**

`lib/core/connection/ws_connection.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'connection.dart';

/// Connects to PTT over WebSocket. PTT rejects the handshake with HTTP 403
/// unless an Origin header is present.
class WsConnection implements Connection {
  WsConnection({Uri? uri, this.origin = 'app://pcman'})
      : uri = uri ?? Uri.parse('wss://ws.ptt.cc/bbs');

  final Uri uri;
  final String origin;

  static const Duration _connectTimeout = Duration(seconds: 15);

  final _data = StreamController<Uint8List>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  WebSocket? _socket;

  @override
  ConnectionStatus status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _status.stream;

  void _set(ConnectionStatus s) {
    if (status == s) return;
    status = s;
    _status.add(s);
  }

  @override
  Future<void> connect() async {
    if (status != ConnectionStatus.disconnected) return;
    _set(ConnectionStatus.connecting);
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {'Origin': origin},
      ).timeout(_connectTimeout);
      _socket = socket;
      _set(ConnectionStatus.connected);
      socket.listen(
        (message) {
          if (message is List<int>) _data.add(Uint8List.fromList(message));
        },
        onError: (Object _) => _closed(socket),
        onDone: () => _closed(socket),
        cancelOnError: true,
      );
    } catch (_) {
      _set(ConnectionStatus.disconnected);
      rethrow;
    }
  }

  void _closed(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _set(ConnectionStatus.disconnected);
  }

  @override
  void send(List<int> bytes) => _socket?.add(bytes);

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    _set(ConnectionStatus.disconnected);
    await socket?.close();
  }
}
```

- [ ] **Step 8: 寫對真實 PTT 的驗證工具**

`tool/ptt_probe.dart`：

```dart
// Manual check against the real server: connects, waits for the welcome
// screen, writes it to build/ptt_probe.txt. Does not log in.
import 'dart:io';

import 'package:myptt/core/connection/ws_connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';

Future<void> main() async {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );
  final session = TerminalSession(WsConnection(), codec);
  await session.connect();
  await Future<void>.delayed(const Duration(seconds: 3));

  final lines = [
    for (var r = 0; r < session.screen.rows; r++)
      rowString(session.screen, r, codec),
  ];
  File('build/ptt_probe.txt')
    ..createSync(recursive: true)
    ..writeAsStringSync(lines.join('\n'));

  final ok = lines.any((l) => l.contains('批踢踢'));
  stdout.writeln(ok ? 'OK: welcome screen decoded' : 'FAIL: 批踢踢 not found');
  await session.dispose();
  exit(ok ? 0 : 1);
}
```

- [ ] **Step 9: 對真實 PTT 驗證**

```bash
/c/dev/flutter/bin/dart.bat run tool/ptt_probe.dart
```

Expected: `OK: welcome screen decoded`。用 Read 工具開啟 `build/ptt_probe.txt`，確認看得到「批踢踢實業坊」、`ptt.cc` 與由 █◢◣ 組成的圖案，且沒有成片的 `�`。`build/` 已被 `.gitignore` 排除，此檔不會進 git。

- [ ] **Step 10: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
git add lib/core tool/ptt_probe.dart test/core test/support
git commit -m "feat: add WebSocket connection, session, key map, recogniser interface"
```

---

### Task 7: 終端機畫面與實體鍵盤

**Files:**
- Create: `lib/ui/palette.dart`
- Create: `lib/ui/glyph_shapes.dart`
- Create: `lib/ui/terminal_painter.dart`
- Create: `lib/ui/terminal_view.dart`
- Modify: `lib/main.dart`（整個取代）
- Test: `test/ui/palette_test.dart`、`test/ui/terminal_view_test.dart`

**Interfaces:**
- Consumes: `TerminalSession`、`ConnectionStatus`、`WsConnection`、`TermKey`、`bytesForKey`、`bytesForCtrl`（Task 6）；`glyphsOfRow`、`Glyph`（Task 4）；`Attr`、`ScreenBuffer`（Task 3）；`Big5Codec`（Task 2）；`FakeConnection`（Task 6）
- Produces:
  - `const List<Color> ansiPalette`（16 色）、`Color foregroundOf(int attr)`、`Color backgroundOf(int attr)`
  - `bool drawShape(Canvas canvas, Rect box, int codePoint, Color color)`（能以圖形繪製時回傳 true）
  - `class TerminalPainter extends CustomPainter { TerminalPainter({required ScreenBuffer screen, required Big5Codec codec, required bool blinkOn}); }`
  - `class TerminalView extends StatefulWidget { const TerminalView({super.key, required TerminalSession session}); }`
  - `class MyPttApp extends StatefulWidget { const MyPttApp({super.key, required TerminalSession session}); }`

前置條件：Windows 執行需要 Visual Studio 的「使用 C++ 的桌面開發」工作負載。若 Task 1 Step 3 顯示缺少，Step 9 之前要先請使用者安裝；Step 1 到 Step 8 不受影響。

- [ ] **Step 1: 寫失敗的測試**

`test/ui/palette_test.dart`：

```dart
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
```

`test/ui/terminal_view_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/terminal_view.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;

  Future<void> pumpView(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    await session.connect();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(session: session))),
    );
  }

  Future<void> disposeView(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await session.dispose();
  }

  testWidgets('paints every kind of glyph without throwing', (tester) async {
    await pumpView(tester);
    // Text, a two-colour wide char, blink, inverse, and a lone lead byte.
    conn.emit([
      ...'\x1b[1;33;44mPTT \x1b[m'.codeUnits,
      ...codec.encode('批踢踢 █▄▌◢◣◤◥─│┌┐└┘├┤┬┴┼').bytes,
      ...'\x1b[31m'.codeUnits, 0xA4, ...'\x1b[32m'.codeUnits, 0xA4,
      ...'\x1b[5mblink\x1b[0;7minverse\x1b[m'.codeUnits,
      0xA4, 0x31,
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);

    // Advance past one blink interval so both blink phases get painted.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await disposeView(tester);
  });

  testWidgets('hardware keys are sent to the server', (tester) async {
    await pumpView(tester);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(conn.sent, [...'\x1b[A'.codeUnits, 0x0D, ...'\x1b[6~'.codeUnits]);

    conn.sent.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    expect(conn.sent, [0x61]);

    conn.sent.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(conn.sent, [0x10]);
    await disposeView(tester);
  });

  testWidgets('survives very small and very large sizes', (tester) async {
    await pumpView(tester);
    conn.emit(codec.encode('中文 ABC █').bytes);
    for (final size in const [Size(1, 1), Size(40, 20), Size(4000, 3000)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await disposeView(tester);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui
```

Expected: FAIL，訊息為找不到 `palette.dart` 與 `terminal_view.dart`。

- [ ] **Step 3: 實作調色盤**

`lib/ui/palette.dart`：

```dart
import 'dart:ui';

import '../core/terminal/screen_buffer.dart';

/// The 16 ANSI colours: 0–7 normal, 8–15 bright.
const List<Color> ansiPalette = [
  Color(0xFF000000), Color(0xFF800000), Color(0xFF008000), Color(0xFF808000),
  Color(0xFF000080), Color(0xFF800080), Color(0xFF008080), Color(0xFFC0C0C0),
  Color(0xFF808080), Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFFF00),
  Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFFFFFF),
];

bool _inverse(int attr) => (attr & Attr.inverse) != 0;

Color foregroundOf(int attr) {
  if (_inverse(attr)) return ansiPalette[Attr.bg(attr)];
  final bright = (attr & Attr.bright) != 0 ? 8 : 0;
  return ansiPalette[Attr.fg(attr) + bright];
}

Color backgroundOf(int attr) =>
    ansiPalette[_inverse(attr) ? Attr.fg(attr) : Attr.bg(attr)];
```

- [ ] **Step 4: 實作圖形字元**

`lib/ui/glyph_shapes.dart`：

```dart
import 'dart:ui';

const int _up = 1, _down = 2, _left = 4, _right = 8;

/// Box-drawing characters mapped to the arms they extend from the centre.
const Map<int, int> _boxArms = {
  0x2500: _left | _right, // ─
  0x2502: _up | _down, // │
  0x250C: _down | _right, // ┌
  0x2510: _down | _left, // ┐
  0x2514: _up | _right, // └
  0x2518: _up | _left, // ┘
  0x251C: _up | _down | _right, // ├
  0x2524: _up | _down | _left, // ┤
  0x252C: _down | _left | _right, // ┬
  0x2534: _up | _left | _right, // ┴
  0x253C: _up | _down | _left | _right, // ┼
};

/// Draws block, triangle, and box-drawing characters as geometry so adjacent
/// cells join without gaps. Returns false if [codePoint] is not one of them.
bool drawShape(Canvas canvas, Rect box, int codePoint, Color color) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = false;

  // Lower one-eighth block through full block.
  if (codePoint >= 0x2581 && codePoint <= 0x2588) {
    final h = box.height * (codePoint - 0x2580) / 8;
    canvas.drawRect(
      Rect.fromLTRB(box.left, box.bottom - h, box.right, box.bottom),
      paint,
    );
    return true;
  }
  // Left seven-eighths block down to left one-eighth block.
  if (codePoint >= 0x2589 && codePoint <= 0x258F) {
    final w = box.width * (0x2590 - codePoint) / 8;
    canvas.drawRect(
      Rect.fromLTRB(box.left, box.top, box.left + w, box.bottom),
      paint,
    );
    return true;
  }
  // Corner triangles ◢ ◣ ◤ ◥.
  if (codePoint >= 0x25E2 && codePoint <= 0x25E5) {
    final tl = box.topLeft, tr = box.topRight;
    final bl = box.bottomLeft, br = box.bottomRight;
    final points = switch (codePoint) {
      0x25E2 => [bl, br, tr],
      0x25E3 => [tl, bl, br],
      0x25E4 => [tl, tr, bl],
      _ => [tl, tr, br],
    };
    canvas.drawPath(Path()..addPolygon(points, true), paint);
    return true;
  }

  final arms = _boxArms[codePoint];
  if (arms == null) return false;
  final t = box.height / 14 < 1 ? 1.0 : box.height / 14;
  final cx = box.center.dx, cy = box.center.dy, h = t / 2;
  if (arms & _up != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, box.top, cx + h, cy + h), paint);
  }
  if (arms & _down != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, cy - h, cx + h, box.bottom), paint);
  }
  if (arms & _left != 0) {
    canvas.drawRect(Rect.fromLTRB(box.left, cy - h, cx + h, cy + h), paint);
  }
  if (arms & _right != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, cy - h, box.right, cy + h), paint);
  }
  return true;
}
```

- [ ] **Step 5: 實作畫面繪製**

`lib/ui/terminal_painter.dart`：

```dart
import 'package:flutter/widgets.dart';

import '../core/encoding/big5_codec.dart';
import '../core/terminal/row_glyphs.dart';
import '../core/terminal/screen_buffer.dart';
import 'glyph_shapes.dart';
import 'palette.dart';

/// Paints a [ScreenBuffer]. Every glyph is centred in its own cell, so column
/// alignment does not depend on the font's advance widths.
class TerminalPainter extends CustomPainter {
  TerminalPainter({
    required this.screen,
    required this.codec,
    required this.blinkOn,
  });

  final ScreenBuffer screen;
  final Big5Codec codec;

  /// Whether blinking text is in its visible phase.
  final bool blinkOn;

  static const int _maxCachedGlyphs = 4000;
  static const List<String> _fonts = [
    'MingLiU', 'Microsoft JhengHei', 'PingFang TC', 'Heiti TC', 'monospace',
  ];
  static final Map<(int, Color, double), TextPainter> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / screen.cols, ch = size.height / screen.rows;
    if (cw <= 0 || ch <= 0) return;
    final bgPaint = Paint()..isAntiAlias = false;

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
          bgPaint..color = bg,
        );
        start = end;
      }

      for (final g in glyphsOfRow(screen, r, codec)) {
        if (g.codePoint == 0x20 || g.codePoint == 0x3000) continue;
        final box = Rect.fromLTWH(g.col * cw, top, g.width * cw, ch);
        final left = _visibleFg(g.leftAttr), right = _visibleFg(g.rightAttr);
        if (g.width == 1 || left == right) {
          if (left != null) _draw(canvas, box, g.codePoint, left);
        } else {
          final mid = box.left + cw;
          _drawClipped(canvas, box, g.codePoint, left,
              Rect.fromLTRB(box.left, box.top, mid, box.bottom));
          _drawClipped(canvas, box, g.codePoint, right,
              Rect.fromLTRB(mid, box.top, box.right, box.bottom));
        }
      }
    }
  }

  Color? _visibleFg(int attr) =>
      (attr & Attr.blink) != 0 && !blinkOn ? null : foregroundOf(attr);

  void _drawClipped(Canvas canvas, Rect box, int cp, Color? color, Rect clip) {
    if (color == null) return;
    canvas.save();
    canvas.clipRect(clip);
    _draw(canvas, box, cp, color);
    canvas.restore();
  }

  void _draw(Canvas canvas, Rect box, int cp, Color color) {
    if (drawShape(canvas, box, cp, color)) return;
    final fontSize = box.height * 0.82;
    if (fontSize < 1) return;
    final tp = _painterFor(cp, color, fontSize);
    tp.paint(
      canvas,
      Offset(
        box.left + (box.width - tp.width) / 2,
        box.top + (box.height - tp.height) / 2,
      ),
    );
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

- [ ] **Step 6: 實作終端機元件**

`lib/ui/terminal_view.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';
import 'terminal_painter.dart';

/// Shows a [TerminalSession] and forwards hardware keyboard input to it.
class TerminalView extends StatefulWidget {
  const TerminalView({super.key, required this.session});

  final TerminalSession session;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  static const Duration _blinkInterval = Duration(milliseconds: 600);

  /// 80 columns of 1:2 cells by 24 rows.
  static const double _aspectRatio = 80 / (24 * 2);

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

  final _focus = FocusNode();
  late final StreamSubscription<void> _updates;
  late final Timer _blink;
  bool _blinkOn = true;

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
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
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
    final text = event.character;
    if (text == null || text.isEmpty) return KeyEventResult.ignored;
    session.sendText(text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _aspectRatio,
              child: CustomPaint(
                painter: TerminalPainter(
                  screen: widget.session.screen,
                  codec: widget.session.codec,
                  blinkOn: _blinkOn,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: 實作啟動程式**

`lib/main.dart`（整個取代）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/connection/connection.dart';
import 'core/connection/ws_connection.dart';
import 'core/encoding/big5_codec.dart';
import 'core/session.dart';
import 'ui/terminal_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final b2u = await rootBundle.load('assets/uao/b2u.bin');
  final u2b = await rootBundle.load('assets/uao/u2b.bin');
  final codec = Big5Codec(
    b2u.buffer.asUint8List(b2u.offsetInBytes, b2u.lengthInBytes),
    u2b.buffer.asUint8List(u2b.offsetInBytes, u2b.lengthInBytes),
  );
  runApp(MyPttApp(session: TerminalSession(WsConnection(), codec)));
}

class MyPttApp extends StatefulWidget {
  const MyPttApp({super.key, required this.session});

  final TerminalSession session;

  @override
  State<MyPttApp> createState() => _MyPttAppState();
}

class _MyPttAppState extends State<MyPttApp> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    try {
      await widget.session.connect();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyPTT',
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              StreamBuilder<void>(
                stream: widget.session.updates,
                builder: (context, _) => _StatusBar(
                  status: widget.session.status,
                  error: _error,
                  onReconnect: _connect,
                ),
              ),
              Expanded(child: TerminalView(session: widget.session)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.error,
    required this.onReconnect,
  });

  final ConnectionStatus status;
  final String? error;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ConnectionStatus.connected => '已連線',
      ConnectionStatus.connecting => '連線中…',
      ConnectionStatus.disconnected => error == null ? '已斷線' : '連線失敗：$error',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (status == ConnectionStatus.disconnected)
            TextButton(onPressed: onReconnect, child: const Text('重新連線')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: 執行全部測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
```

Expected: `No issues found!` 與 `All tests passed!`

- [ ] **Step 9: 在 Windows 上實際執行**

```bash
/c/dev/flutter/bin/flutter.bat run -d windows
```

逐項確認並記錄結果：

1. 視窗開啟後出現 PTT 歡迎畫面，上方顯示「已連線」。
2. 「批踢踢實業坊」等中文字清楚，沒有 `�` 或缺字方框。
3. 歡迎畫面的色塊圖案相鄰處沒有細縫。
4. 輸入 `guest` 再按 Enter，畫面有回應並進入下一個畫面。
5. 方向鍵、PageUp、PageDown 能移動游標或翻頁。
6. 拖曳視窗改變大小，畫面等比例縮放且不變形。
7. 拔掉網路或等待逾時後，上方顯示「已斷線」並出現「重新連線」按鈕，畫面內容仍保留；按下後能重新連上。

若因缺少 C++ 工作負載而無法建置，停在這一步並回報，不要標記完成。

- [ ] **Step 10: Commit 並推送**

```bash
git add lib/ui lib/main.dart test/ui
git commit -m "feat: add terminal view with hardware keyboard input"
git push -u origin feat/terminal-core
```

---

## 本計畫完成後的狀態

- Windows 上可執行的 PTT 用戶端：能連線、顯示彩色畫面、用實體鍵盤輸入英數與控制鍵。
- 尚未支援：中文輸入、觸控手勢、按鍵列、登入頁與自動登入、自動重連、防閒置、斷線後的「繼續瀏覽」模式、iOS 建置說明。這些屬於第二份計畫。
