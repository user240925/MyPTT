# MyPTT 未登入網頁瀏覽 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不登入也能以手機原生的清單與閱讀頁瀏覽 PTT 的公開看板，並在登入時被動記下「我的最愛」，讓未登入時也能直接進入常看的看板。

**Architecture:** 新增一條與終端機互不依賴的資料來源：抓取 `https://www.ptt.cc/bbs/` 的網頁並解析成結構化資料。抓取、解析、最愛辨識都是純 Dart，以手寫的網頁片段做單元測試。介面為三個頁面：看板清單、文章列表、文章閱讀。

**Tech Stack:** Flutter stable（Dart 3）、`dart:io` HttpClient、`html`（純 Dart 的 HTML 解析套件）、`shared_preferences`（儲存最愛清單）。

**Spec:** `docs/superpowers/specs/2026-10-06-myptt-ios-design.md` 第 10 節

## Global Constraints

- 網頁來源固定為 `https://www.ptt.cc`，只讀取 `/bbs/` 底下的路徑。
- 每個請求帶 `Cookie: over18=1` 與一個瀏覽器樣式的 `User-Agent`。
- 兩次請求之間至少間隔 500 毫秒；同一頁面 60 秒內重複讀取使用快取；失敗後不自動重試，由使用者按「重試」。
- 網頁上的連結視為不可信：文章路徑必須符合 `/bbs/<看板>/M.<數字>.A.<三碼>.html`（或 `G.` 開頭），翻頁路徑必須符合 `/bbs/<同一看板>/index<數字>.html`，其餘一律捨棄。內文連結只保留 http 與 https。
- 看板名稱只接受 1 到 12 個英文字母、數字、底線或連字號。
- 唯讀：不提供發文、推文。
- 解析失敗、被拒絕、找不到時顯示訊息並提供「重試」與「以瀏覽器開啟」，不當機。
- 最愛只在勾選「記住帳號密碼」並以自動登入連線時記錄；未勾選而登入時清除。程式不為了取得最愛而代替使用者送出任何按鍵。
- 最愛清單存於一般的本機設定，不放鑰匙圈；密碼仍只存於鑰匙圈。
- `lib/core/` 底下為純 Dart，不得 import `package:flutter` 或 `dart:ui`。
- 只新增兩個套件：`html` 與 `shared_preferences`。
- 測試資料一律手寫，不放入從 PTT 實際抓下的內容。
- 介面文字使用繁體中文。
- 所有指令在 repo 根目錄執行，Flutter 位於 `C:\dev\flutter\bin\flutter.bat`（不在 PATH）。
- 每個 Task 結束前執行 `flutter analyze` 與完整的 `flutter test`，皆須通過。
- Commit 訊息結尾加上 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 網頁結構改變、內容為空或為亂碼：應顯示「無法解析頁面內容」並可重試或改用瀏覽器開啟，不當機，且壞掉的內容不留在快取。（Task 1 測試 `unrecognised pages are format errors`、Task 2 測試 `a page that fails to parse is not cached`）
2. 網站回應 403、429、503 或 Cloudflare 驗證頁：應顯示「網站暫時拒絕連線」，且不自動重試。（Task 2 測試 `blocked responses are reported as blocked`）
3. 文章列表中的惡意連結（`javascript:`、外部網域、含 `..` 的路徑）：不得被抓取或開啟。（Task 1 測試 `hostile links are dropped`）
4. 終端機上只是「提到」我的最愛的畫面（一般看板列表、標題含該字樣的文章）：不得被當成最愛畫面而覆寫紀錄。（Task 3 測試 `screens that merely mention favourites are not read`）
5. 頁面尚未載入完成就離開，或連按兩次「載入更早的文章」：不得在頁面關閉後更新畫面，也不得出現重複的文章。（Task 4 測試 `leaving before the load finishes is safe` 與 `loading older posts twice does not duplicate them`）

## File Structure

| 檔案 | 職責 |
|---|---|
| `lib/core/web/models.dart` | 看板、文章列表、文章、推文的資料型別 |
| `lib/core/web/ptt_web_parser.dart` | 把網頁原始碼解析成資料型別，並過濾不可信的連結 |
| `lib/core/web/page_fetcher.dart` | 抓取介面與錯誤型別 |
| `lib/core/web/http_page_fetcher.dart` | 以 `dart:io` 實作抓取 |
| `lib/core/web/ptt_web_client.dart` | 組合抓取與解析，負責節流與快取 |
| `lib/core/favorites/favorites.dart` | 辨識「我的最愛」畫面、合併紀錄、儲存介面 |
| `lib/core/session.dart`（修改） | 提供各列的文字 |
| `lib/platform/prefs_favorites_store.dart` | 以 `shared_preferences` 儲存最愛 |
| `lib/ui/session_controller.dart`（修改） | 登入期間被動記錄最愛 |
| `lib/ui/web/load_view.dart` | 載入中、錯誤、重試的共用元件 |
| `lib/ui/web/board_list_page.dart` | 看板清單：前往看板、我的最愛、熱門看板 |
| `lib/ui/web/post_list_page.dart` | 文章列表 |
| `lib/ui/web/article_page.dart` | 文章閱讀 |
| `lib/ui/terminal_page.dart`（修改） | 斷線後提供「瀏覽看板」 |
| `lib/ui/login_page.dart`（修改） | 「不登入，直接瀏覽」入口；依是否記住決定記錄或清除最愛 |
| `lib/main.dart`（修改） | 建立並傳入新的服務 |
| `tool/web_probe.dart` | 對真實網站的手動驗證工具 |

---

### Task 1: 資料型別與網頁解析

**Files:**
- Modify: `pubspec.yaml`（由 `flutter pub add` 修改）
- Create: `lib/core/web/models.dart`
- Create: `lib/core/web/ptt_web_parser.dart`
- Create: `test/support/web_fixtures.dart`
- Test: `test/core/web/ptt_web_parser_test.dart`

**Interfaces:**
- Consumes: 無
- Produces:
  - `class BoardSummary { const BoardSummary({required String name, String title = '', String category = '', int? userCount}); }`
  - `class PostSummary { const PostSummary({required String title, required String author, required String date, required String pushCount, String? path}); bool get isAvailable; }`（`path` 為 null 表示文章已刪除或連結不可信）
  - `class BoardPage { const BoardPage({required String board, required List<PostSummary> posts, required List<PostSummary> pinned, String? olderPath}); }`（`posts` 由新到舊）
  - `class TextRun { const TextRun(String text, {int? fg, int? bg, bool bright = false, String? link}); }`（`fg`、`bg` 為 0 到 7）
  - `class Push { const Push({required String tag, required String userId, required String content, required String time}); }`
  - `class Article { const Article({required String board, required String title, required String author, required String time, required List<TextRun> body, required List<Push> pushes}); String get bodyText; }`
  - `class PttWebFormatException implements Exception { const PttWebFormatException(String message); final String message; }`
  - `bool isValidBoardName(String name)`、`bool isArticlePath(String path)`、`bool isIndexPath(String path, String board)`
  - `List<BoardSummary> parseHotBoards(String source)`、`BoardPage parseBoardIndex(String source, String board)`、`Article parseArticle(String source)`
  - 測試資料常數：`hotBoardsHtml`、`stockIndexHtml`、`stockOlderIndexHtml`、`hostileIndexHtml`、`articleHtml`

- [ ] **Step 1: 加入套件**

```bash
/c/dev/flutter/bin/flutter.bat pub add html
```

Expected: 輸出包含 `+ html`。

- [ ] **Step 2: 寫測試資料**

`test/support/web_fixtures.dart`：

```dart
// Hand-written pages with the same markup as www.ptt.cc. No real content.

const String hotBoardsHtml = '''
<html><body><div class="b-list-container action-bar-margin bbs-screen">
<div class="b-ent"><a class="board" href="/bbs/Gossiping/index.html">
  <div class="board-name">Gossiping</div>
  <div class="board-nuser"><span class="hl f1">4462</span></div>
  <div class="board-class">綜合</div>
  <div class="board-title">◎八卦板</div>
</a></div>
<div class="b-ent"><a class="board" href="/bbs/Stock/index.html">
  <div class="board-name">Stock</div>
  <div class="board-nuser"><span class="hl f6">1200</span></div>
  <div class="board-class">學術</div>
  <div class="board-title">◎股票板</div>
</a></div>
<div class="b-ent"><a class="board" href="/bbs/x/index.html">
  <div class="board-name"> </div>
</a></div>
<div class="b-ent"><a class="board" href="/bbs/bad/index.html">
  <div class="board-name">bad name!</div>
</a></div>
</div></body></html>
''';

const String stockIndexHtml = '''
<html><body>
<div class="btn-group btn-group-paging">
  <a class="btn wide" href="/bbs/Stock/index1.html">最舊</a>
  <a class="btn wide" href="/bbs/Stock/index99.html">&lsaquo; 上頁</a>
  <a class="btn wide disabled">下頁 &rsaquo;</a>
  <a class="btn wide" href="/bbs/Stock/index.html">最新</a>
</div>
<div class="r-list-container action-bar-margin bbs-screen">
<div class="r-ent">
  <div class="nrec"><span class="hl f2">5</span></div>
  <div class="title"><a href="/bbs/Stock/M.1000000001.A.AAA.html">[請益] 第一篇</a></div>
  <div class="meta"><div class="author">alice</div><div class="date">10/05</div></div>
</div>
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title">(本文已被刪除) [bob]</div>
  <div class="meta"><div class="author">-</div><div class="date">10/05</div></div>
</div>
<div class="r-ent">
  <div class="nrec"><span class="hl f1">爆</span></div>
  <div class="title"><a href="/bbs/Stock/M.1000000003.A.CCC.html">[新聞] 第三篇</a></div>
  <div class="meta"><div class="author">carol</div><div class="date">10/06</div></div>
</div>
<div class="r-list-sep"></div>
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="/bbs/Stock/M.1000000000.A.000.html">[公告] 板規</a></div>
  <div class="meta"><div class="author">mod</div><div class="date"> 1/01</div></div>
</div>
</div></body></html>
''';

const String stockOlderIndexHtml = '''
<html><body>
<div class="btn-group btn-group-paging">
  <a class="btn wide" href="/bbs/Stock/index1.html">最舊</a>
  <a class="btn wide" href="/bbs/Stock/index98.html">&lsaquo; 上頁</a>
  <a class="btn wide" href="/bbs/Stock/index100.html">下頁 &rsaquo;</a>
  <a class="btn wide" href="/bbs/Stock/index.html">最新</a>
</div>
<div class="r-list-container action-bar-margin bbs-screen">
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="/bbs/Stock/M.0900000001.A.111.html">[閒聊] 更早一</a></div>
  <div class="meta"><div class="author">dave</div><div class="date">10/03</div></div>
</div>
<div class="r-ent">
  <div class="nrec"><span class="hl f3">12</span></div>
  <div class="title"><a href="/bbs/Stock/M.0900000002.A.222.html">[閒聊] 更早二</a></div>
  <div class="meta"><div class="author">erin</div><div class="date">10/04</div></div>
</div>
</div></body></html>
''';

const String hostileIndexHtml = '''
<html><body>
<div class="btn-group btn-group-paging">
  <a class="btn wide" href="https://evil.example/bbs/Stock/index5.html">&lsaquo; 上頁</a>
</div>
<div class="r-list-container">
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="javascript:alert(1)">腳本連結</a></div>
  <div class="meta"><div class="author">a</div><div class="date">10/01</div></div>
</div>
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="https://evil.example/bbs/Stock/M.1.A.AAA.html">外部網域</a></div>
  <div class="meta"><div class="author">b</div><div class="date">10/01</div></div>
</div>
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="/bbs/Stock/../../etc/M.1.A.AAA.html">路徑穿越</a></div>
  <div class="meta"><div class="author">c</div><div class="date">10/01</div></div>
</div>
<div class="r-ent">
  <div class="nrec"></div>
  <div class="title"><a href="/bbs/Other/M.1000000009.A.999.html">別的看板</a></div>
  <div class="meta"><div class="author">d</div><div class="date">10/01</div></div>
</div>
</div></body></html>
''';

const String articleHtml = '''
<html><body><div id="main-content" class="bbs-screen bbs-content"><div class="article-metaline"><span class="article-meta-tag">作者</span><span class="article-meta-value">alice (愛麗絲)</span></div><div class="article-metaline-right"><span class="article-meta-tag">看板</span><span class="article-meta-value">Stock</span></div><div class="article-metaline"><span class="article-meta-tag">標題</span><span class="article-meta-value">[請益] 第一篇</span></div><div class="article-metaline"><span class="article-meta-tag">時間</span><span class="article-meta-value">Mon Oct  5 12:00:00 2026</span></div>
第一行內文
<span class="f2 hl">綠色高亮</span> 與 <span class="b4">藍底</span>
連結 <a href="https://example.com/a" target="_blank" rel="noreferrer noopener nofollow">https://example.com/a</a> 結束
<a href="javascript:alert(1)">壞連結</a>
<div class="richcontent"><img src="https://example.com/x.png" alt="內嵌圖片"></div>
--
<span class="f2">※ 發信站: 批踢踢實業坊(ptt.cc)</span>
<div class="push"><span class="hl push-tag">推 </span><span class="f3 hl push-userid">bob</span><span class="f3 push-content">: 推一個</span><span class="push-ipdatetime"> 10/05 12:01
</span></div><div class="push"><span class="f1 hl push-tag">噓 </span><span class="f3 hl push-userid">carol</span><span class="f3 push-content">: 不同意 <a href="https://example.com/b">https://example.com/b</a></span><span class="push-ipdatetime"> 10/05 12:02
</span></div><span class="f2">※ 編輯: alice</span>
</div></body></html>
''';
```

- [ ] **Step 3: 寫失敗的測試**

`test/core/web/ptt_web_parser_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/web/models.dart';
import 'package:myptt/core/web/ptt_web_parser.dart';

import '../../support/web_fixtures.dart';

void main() {
  group('names and paths', () {
    test('board names', () {
      expect(isValidBoardName('Stock'), isTrue);
      expect(isValidBoardName('C_Chat'), isTrue);
      expect(isValidBoardName('Tech-Job'), isTrue);
      expect(isValidBoardName('a'), isTrue);
      expect(isValidBoardName(''), isFalse);
      expect(isValidBoardName('ThirteenChars'), isFalse);
      expect(isValidBoardName('bad name'), isFalse);
      expect(isValidBoardName('../etc'), isFalse);
      expect(isValidBoardName('看板'), isFalse);
    });

    test('article paths', () {
      expect(isArticlePath('/bbs/Stock/M.1000000001.A.AAA.html'), isTrue);
      expect(isArticlePath('/bbs/Stock/G.1000000001.A.0F3.html'), isTrue);
      expect(isArticlePath('/bbs/Stock/index.html'), isFalse);
      expect(isArticlePath('/bbs/Stock/../x/M.1.A.AAA.html'), isFalse);
      expect(isArticlePath('https://evil.example/bbs/Stock/M.1.A.AAA.html'), isFalse);
      expect(isArticlePath('/bbs/Stock/M.1.A.AAA.html?x=1'), isFalse);
      expect(isArticlePath('javascript:alert(1)'), isFalse);
    });

    test('index paths are tied to one board', () {
      expect(isIndexPath('/bbs/Stock/index.html', 'Stock'), isTrue);
      expect(isIndexPath('/bbs/Stock/index99.html', 'Stock'), isTrue);
      expect(isIndexPath('/bbs/Other/index99.html', 'Stock'), isFalse);
      expect(isIndexPath('/bbs/Stock/index99.html#x', 'Stock'), isFalse);
      expect(isIndexPath('/bbs/Stock/M.1000000001.A.AAA.html', 'Stock'), isFalse);
      expect(isIndexPath('/bbs/C_Chat/index1.html', 'C.Chat'), isFalse);
    });
  });

  group('hot boards', () {
    test('lists boards with name, class, title, and user count', () {
      final boards = parseHotBoards(hotBoardsHtml);
      expect(boards.map((b) => b.name), ['Gossiping', 'Stock']);
      expect(boards[0].userCount, 4462);
      expect(boards[0].category, '綜合');
      expect(boards[0].title, '◎八卦板');
      expect(boards[1].userCount, 1200);
    });
  });

  group('board index', () {
    test('posts are newest first, with deleted posts unavailable', () {
      final page = parseBoardIndex(stockIndexHtml, 'Stock');
      expect(page.board, 'Stock');
      expect(page.posts.map((p) => p.title),
          ['[新聞] 第三篇', '(本文已被刪除) [bob]', '[請益] 第一篇']);
      expect(page.posts[0].path, '/bbs/Stock/M.1000000003.A.CCC.html');
      expect(page.posts[0].pushCount, '爆');
      expect(page.posts[0].author, 'carol');
      expect(page.posts[0].date, '10/06');
      expect(page.posts[0].isAvailable, isTrue);
      expect(page.posts[1].path, isNull);
      expect(page.posts[1].isAvailable, isFalse);
      expect(page.posts[2].pushCount, '5');
    });

    test('pinned posts are kept apart and the older page is found', () {
      final page = parseBoardIndex(stockIndexHtml, 'Stock');
      expect(page.pinned.single.title, '[公告] 板規');
      expect(page.pinned.single.date, '1/01');
      expect(page.olderPath, '/bbs/Stock/index99.html');
      expect(parseBoardIndex(stockOlderIndexHtml, 'Stock').olderPath,
          '/bbs/Stock/index98.html');
    });

    // Review Focus 3
    test('hostile links are dropped', () {
      final page = parseBoardIndex(hostileIndexHtml, 'Stock');
      expect(page.posts.length, 4);
      expect(page.posts.every((p) => p.path == null), isTrue);
      expect(page.posts.map((p) => p.title),
          ['別的看板', '路徑穿越', '外部網域', '腳本連結']);
      expect(page.olderPath, isNull);
    });

    test('an empty board is a valid page', () {
      final page = parseBoardIndex(
        '<div class="r-list-container"></div>',
        'Stock',
      );
      expect(page.posts, isEmpty);
      expect(page.pinned, isEmpty);
      expect(page.olderPath, isNull);
    });
  });

  group('article', () {
    late Article article;
    setUp(() => article = parseArticle(articleHtml));

    test('header fields', () {
      expect(article.author, 'alice (愛麗絲)');
      expect(article.board, 'Stock');
      expect(article.title, '[請益] 第一篇');
      expect(article.time, 'Mon Oct  5 12:00:00 2026');
    });

    test('body keeps text, colours, and safe links only', () {
      expect(article.bodyText, startsWith('第一行內文\n'));
      expect(article.bodyText, contains('※ 發信站: 批踢踢實業坊(ptt.cc)'));
      expect(article.bodyText, isNot(contains('作者')));
      expect(article.bodyText, isNot(contains('推一個')));
      expect(article.bodyText, isNot(contains('內嵌圖片')));

      final green = article.body.firstWhere((r) => r.text == '綠色高亮');
      expect((green.fg, green.bright, green.bg), (2, true, null));
      final blue = article.body.firstWhere((r) => r.text == '藍底');
      expect((blue.fg, blue.bright, blue.bg), (null, false, 4));

      final link = article.body.firstWhere((r) => r.text == 'https://example.com/a');
      expect(link.link, 'https://example.com/a');
      final bad = article.body.firstWhere((r) => r.text == '壞連結');
      expect(bad.link, isNull);
    });

    test('pushes', () {
      expect(article.pushes.length, 2);
      final first = article.pushes[0];
      expect((first.tag, first.userId, first.content, first.time),
          ('推', 'bob', '推一個', '10/05 12:01'));
      final second = article.pushes[1];
      expect((second.tag, second.userId), ('噓', 'carol'));
      expect(second.content, '不同意 https://example.com/b');
    });

    test('an article without header lines still parses', () {
      final plain = parseArticle('<div id="main-content">只有內文</div>');
      expect(plain.title, '');
      expect(plain.author, '');
      expect(plain.bodyText, '只有內文');
      expect(plain.pushes, isEmpty);
    });
  });

  // Review Focus 1
  test('unrecognised pages are format errors', () {
    const garbage = [
      '',
      'not html at all',
      '<html><body><p>維護中</p></body></html>',
      '<html><head><title>Just a moment...</title></head><body></body></html>',
      '\u0000\u0001\uFFFD<<<>>>',
    ];
    for (final source in garbage) {
      expect(() => parseHotBoards(source), throwsA(isA<PttWebFormatException>()),
          reason: 'hot: $source');
      expect(() => parseBoardIndex(source, 'Stock'),
          throwsA(isA<PttWebFormatException>()), reason: 'index: $source');
      expect(() => parseArticle(source), throwsA(isA<PttWebFormatException>()),
          reason: 'article: $source');
    }
  });
}
```

- [ ] **Step 4: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/web/ptt_web_parser_test.dart
```

Expected: FAIL，訊息為找不到 `models.dart` 與 `ptt_web_parser.dart`。

- [ ] **Step 5: 實作資料型別**

`lib/core/web/models.dart`：

```dart
class BoardSummary {
  const BoardSummary({
    required this.name,
    this.title = '',
    this.category = '',
    this.userCount,
  });

  final String name;
  final String title;
  final String category;

  /// People currently in the board, when the page shows it.
  final int? userCount;
}

class PostSummary {
  const PostSummary({
    required this.title,
    required this.author,
    required this.date,
    required this.pushCount,
    this.path,
  });

  final String title;
  final String author;
  final String date;

  /// As shown on the site: a number, "爆", "X1", or empty.
  final String pushCount;

  /// Site-relative article path. Null when the post was deleted or its link
  /// did not look like an article on this site.
  final String? path;

  bool get isAvailable => path != null;
}

class BoardPage {
  const BoardPage({
    required this.board,
    required this.posts,
    required this.pinned,
    this.olderPath,
  });

  final String board;

  /// Newest first.
  final List<PostSummary> posts;
  final List<PostSummary> pinned;

  /// Site-relative path of the page with older posts, or null at the end.
  final String? olderPath;
}

/// A stretch of article text sharing one style.
class TextRun {
  const TextRun(this.text, {this.fg, this.bg, this.bright = false, this.link});

  final String text;

  /// ANSI colour 0–7, or null for the default.
  final int? fg;
  final int? bg;
  final bool bright;

  /// An http(s) URL when this run is a link.
  final String? link;
}

class Push {
  const Push({
    required this.tag,
    required this.userId,
    required this.content,
    required this.time,
  });

  /// "推", "噓", or "→".
  final String tag;
  final String userId;
  final String content;
  final String time;
}

class Article {
  const Article({
    required this.board,
    required this.title,
    required this.author,
    required this.time,
    required this.body,
    required this.pushes,
  });

  final String board;
  final String title;
  final String author;
  final String time;
  final List<TextRun> body;
  final List<Push> pushes;

  String get bodyText => body.map((r) => r.text).join();
}
```

- [ ] **Step 6: 實作解析**

`lib/core/web/ptt_web_parser.dart`：

```dart
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'models.dart';

/// The page did not have the structure this parser knows.
class PttWebFormatException implements Exception {
  const PttWebFormatException(this.message);

  final String message;

  @override
  String toString() => 'PttWebFormatException: $message';
}

final RegExp _boardName = RegExp(r'^[A-Za-z0-9_\-]{1,12}$');
final RegExp _articlePath =
    RegExp(r'^/bbs/([A-Za-z0-9_\-]{1,12})/[MG]\.\d{1,12}\.A\.[0-9A-F]{3}\.html$');
final RegExp _colorClass = RegExp(r'^([fb])([0-7])$');

bool isValidBoardName(String name) => _boardName.hasMatch(name);

bool isArticlePath(String path) => _articlePath.hasMatch(path);

bool isIndexPath(String path, String board) =>
    isValidBoardName(board) &&
    RegExp('^/bbs/${RegExp.escape(board)}/index\\d{0,7}\\.html\$').hasMatch(path);

String _text(Element? e) => e?.text.trim() ?? '';

List<BoardSummary> parseHotBoards(String source) {
  final links = html.parse(source).querySelectorAll('a.board');
  if (links.isEmpty) {
    throw const PttWebFormatException('no board entries');
  }
  final boards = <BoardSummary>[];
  for (final a in links) {
    final name = _text(a.querySelector('.board-name'));
    if (!isValidBoardName(name)) continue;
    boards.add(BoardSummary(
      name: name,
      title: _text(a.querySelector('.board-title')),
      category: _text(a.querySelector('.board-class')),
      userCount: int.tryParse(_text(a.querySelector('.board-nuser'))),
    ));
  }
  return boards;
}

BoardPage parseBoardIndex(String source, String board) {
  final doc = html.parse(source);
  final container = doc.querySelector('.r-list-container');
  if (container == null) {
    throw const PttWebFormatException('no post list');
  }

  final posts = <PostSummary>[];
  final pinned = <PostSummary>[];
  var afterSeparator = false;
  for (final e in container.children) {
    if (e.classes.contains('r-list-sep')) {
      afterSeparator = true;
    } else if (e.classes.contains('r-ent')) {
      (afterSeparator ? pinned : posts).add(_post(e, board));
    }
  }

  String? olderPath;
  for (final a in doc.querySelectorAll('.btn-group-paging a')) {
    final href = a.attributes['href'];
    if (href != null && a.text.contains('上頁') && isIndexPath(href, board)) {
      olderPath = href;
    }
  }

  return BoardPage(
    board: board,
    // The site lists oldest first; a phone list reads better newest first.
    posts: posts.reversed.toList(),
    pinned: pinned,
    olderPath: olderPath,
  );
}

PostSummary _post(Element e, String board) {
  final link = e.querySelector('.title a');
  final href = link?.attributes['href'];
  final match = href == null ? null : _articlePath.firstMatch(href);
  // A link is only followed if it is an article of this very board.
  final path = match != null && match.group(1) == board ? href : null;
  return PostSummary(
    title: _text(link ?? e.querySelector('.title')),
    author: _text(e.querySelector('.author')),
    date: _text(e.querySelector('.date')),
    pushCount: _text(e.querySelector('.nrec')),
    path: path,
  );
}

class _Style {
  const _Style({this.fg, this.bg, this.bright = false, this.link});

  final int? fg;
  final int? bg;
  final bool bright;
  final String? link;
}

bool _isHttpUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

const Set<String> _notBody = {
  'article-metaline',
  'article-metaline-right',
  'push',
  'richcontent',
};

void _collect(Node node, _Style style, List<TextRun> out) {
  if (node is Text) {
    if (node.data.isNotEmpty) {
      out.add(TextRun(
        node.data,
        fg: style.fg,
        bg: style.bg,
        bright: style.bright,
        link: style.link,
      ));
    }
    return;
  }
  if (node is! Element) return;
  if (node.classes.any(_notBody.contains)) return;

  var fg = style.fg, bg = style.bg, bright = style.bright, link = style.link;
  for (final name in node.classes) {
    final m = _colorClass.firstMatch(name);
    if (m != null) {
      final value = int.parse(m.group(2)!);
      if (m.group(1) == 'f') {
        fg = value;
      } else {
        bg = value;
      }
    } else if (name == 'hl') {
      bright = true;
    }
  }
  if (node.localName == 'a') {
    final href = node.attributes['href'];
    link = href != null && _isHttpUrl(href) ? href : null;
  }
  final inner = _Style(fg: fg, bg: bg, bright: bright, link: link);
  for (final child in node.nodes) {
    _collect(child, inner, out);
  }
}

Article parseArticle(String source) {
  final main = html.parse(source).querySelector('#main-content');
  if (main == null) {
    throw const PttWebFormatException('no article content');
  }

  final meta = <String, String>{};
  for (final line
      in main.querySelectorAll('.article-metaline, .article-metaline-right')) {
    meta[_text(line.querySelector('.article-meta-tag'))] =
        _text(line.querySelector('.article-meta-value'));
  }

  // Everything before the first push is the article itself.
  final body = <TextRun>[];
  for (final node in main.nodes) {
    if (node is Element && node.classes.contains('push')) break;
    _collect(node, const _Style(), body);
  }
  while (body.isNotEmpty && body.first.text.trim().isEmpty) {
    body.removeAt(0);
  }
  if (body.isNotEmpty) {
    final first = body.first;
    body[0] = TextRun(
      first.text.trimLeft(),
      fg: first.fg,
      bg: first.bg,
      bright: first.bright,
      link: first.link,
    );
  }
  while (body.isNotEmpty && body.last.text.trim().isEmpty) {
    body.removeLast();
  }
  if (body.isNotEmpty) {
    final last = body.last;
    body[body.length - 1] = TextRun(
      last.text.trimRight(),
      fg: last.fg,
      bg: last.bg,
      bright: last.bright,
      link: last.link,
    );
  }

  final pushes = <Push>[];
  for (final e in main.querySelectorAll('div.push')) {
    var content = e.querySelector('.push-content')?.text ?? '';
    if (content.startsWith(':')) content = content.substring(1);
    pushes.add(Push(
      tag: _text(e.querySelector('.push-tag')),
      userId: _text(e.querySelector('.push-userid')),
      content: content.trim(),
      time: _text(e.querySelector('.push-ipdatetime')),
    ));
  }

  return Article(
    board: meta['看板'] ?? '',
    title: meta['標題'] ?? '',
    author: meta['作者'] ?? '',
    time: meta['時間'] ?? '',
    body: body,
    pushes: pushes,
  );
}
```

- [ ] **Step 7: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/web/ptt_web_parser_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add pubspec.yaml pubspec.lock lib/core/web/models.dart lib/core/web/ptt_web_parser.dart test/core/web/ptt_web_parser_test.dart test/support/web_fixtures.dart
git commit -m "feat: add PTT web page models and parser"
```

---

### Task 2: 抓取、節流與快取

**Files:**
- Create: `lib/core/web/page_fetcher.dart`
- Create: `lib/core/web/http_page_fetcher.dart`
- Create: `lib/core/web/ptt_web_client.dart`
- Create: `test/support/fake_page_fetcher.dart`
- Create: `tool/web_probe.dart`
- Test: `test/core/web/ptt_web_client_test.dart`、`test/core/web/http_page_fetcher_test.dart`

**Interfaces:**
- Consumes: Task 1 的型別與解析函式、`isValidBoardName`、`isArticlePath`、`isIndexPath`、`PttWebFormatException`
- Produces:
  - `enum PttWebError { network, notFound, blocked, format }`
  - `class PttWebException implements Exception { const PttWebException(PttWebError kind, [String detail = '']); final PttWebError kind; final String detail; }`
  - `abstract class PageFetcher { Future<String> fetch(Uri uri); }`（失敗時丟出 `PttWebException`）
  - `class HttpPageFetcher implements PageFetcher { HttpPageFetcher({HttpClient? client, Duration timeout = const Duration(seconds: 15)}); void close(); }`
  - `class PttWebClient { PttWebClient(PageFetcher fetcher, {Duration minInterval = const Duration(milliseconds: 500), Duration cacheTtl = const Duration(seconds: 60), int cacheSize = 30, DateTime Function()? now}); static final Uri base; Future<List<BoardSummary>> hotBoards({bool refresh = false}); Future<BoardPage> boardPage(String board, {String? path, bool refresh = false}); Future<Article> article(String path, {bool refresh = false}); static String browserUrl(String path); }`
  - 測試用 `class FakePageFetcher implements PageFetcher`，有 `Map<String, String> pages`、`Map<String, Object> errors`、`List<String> requests`。

- [ ] **Step 1: 寫介面與假的抓取器**

`lib/core/web/page_fetcher.dart`：

```dart
enum PttWebError {
  /// No connection, DNS failure, or timeout.
  network,

  /// The board or article does not exist or is not public.
  notFound,

  /// The site refused the request (rate limit or bot check).
  blocked,

  /// The page arrived but did not have the expected structure.
  format,
}

class PttWebException implements Exception {
  const PttWebException(this.kind, [this.detail = '']);

  final PttWebError kind;
  final String detail;

  @override
  String toString() => 'PttWebException(${kind.name}): $detail';
}

/// Downloads a page as text. Throws [PttWebException] on failure.
abstract class PageFetcher {
  Future<String> fetch(Uri uri);
}
```

`test/support/fake_page_fetcher.dart`：

```dart
import 'package:myptt/core/web/page_fetcher.dart';

class FakePageFetcher implements PageFetcher {
  /// Body returned for each URL path.
  final Map<String, String> pages = {};

  /// Thrown instead of returning a body, per URL path.
  final Map<String, Object> errors = {};

  /// Every path requested, in order.
  final List<String> requests = [];

  @override
  Future<String> fetch(Uri uri) async {
    requests.add(uri.path);
    final error = errors[uri.path];
    if (error != null) throw error;
    final body = pages[uri.path];
    if (body == null) throw const PttWebException(PttWebError.notFound);
    return body;
  }
}
```

- [ ] **Step 2: 寫失敗的測試**

`test/core/web/ptt_web_client_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/web/page_fetcher.dart';
import 'package:myptt/core/web/ptt_web_client.dart';

import '../../support/fake_page_fetcher.dart';
import '../../support/web_fixtures.dart';

const hotPath = '/bbs/hotboards.html';
const stockPath = '/bbs/Stock/index.html';
const olderPath = '/bbs/Stock/index99.html';
const articlePath = '/bbs/Stock/M.1000000001.A.AAA.html';

Matcher throwsWeb(PttWebError kind) =>
    throwsA(isA<PttWebException>().having((e) => e.kind, 'kind', kind));

void main() {
  late FakePageFetcher fetcher;
  late PttWebClient client;

  setUp(() {
    fetcher = FakePageFetcher()
      ..pages[hotPath] = hotBoardsHtml
      ..pages[stockPath] = stockIndexHtml
      ..pages[olderPath] = stockOlderIndexHtml
      ..pages[articlePath] = articleHtml;
    client = PttWebClient(fetcher, minInterval: Duration.zero);
  });

  test('fetches and parses each kind of page', () async {
    expect((await client.hotBoards()).length, 2);
    final page = await client.boardPage('Stock');
    expect(page.posts.length, 3);
    final older = await client.boardPage('Stock', path: page.olderPath);
    expect(older.posts.first.title, '[閒聊] 更早二');
    expect((await client.article(articlePath)).title, '[請益] 第一篇');
    expect(fetcher.requests, [hotPath, stockPath, olderPath, articlePath]);
  });

  test('requests go to www.ptt.cc over https', () {
    expect(PttWebClient.base.toString(), 'https://www.ptt.cc');
    expect(PttWebClient.browserUrl(articlePath), 'https://www.ptt.cc$articlePath');
  });

  test('repeat reads within the cache lifetime are not fetched again', () async {
    await client.boardPage('Stock');
    await client.boardPage('Stock');
    expect(fetcher.requests, [stockPath]);
    await client.boardPage('Stock', refresh: true);
    expect(fetcher.requests, [stockPath, stockPath]);
  });

  test('the cache expires', () async {
    var now = DateTime(2026, 10, 8, 12);
    client = PttWebClient(fetcher, minInterval: Duration.zero, now: () => now);
    await client.hotBoards();
    now = now.add(const Duration(seconds: 59));
    await client.hotBoards();
    expect(fetcher.requests.length, 1);
    now = now.add(const Duration(seconds: 2));
    await client.hotBoards();
    expect(fetcher.requests.length, 2);
  });

  test('the cache holds a limited number of pages', () async {
    client = PttWebClient(fetcher, minInterval: Duration.zero, cacheSize: 2);
    await client.hotBoards();
    await client.boardPage('Stock');
    await client.article(articlePath);
    await client.hotBoards();
    expect(fetcher.requests, [hotPath, stockPath, articlePath, hotPath]);
  });

  test('simultaneous reads of one page share a single request', () async {
    final results = await Future.wait([
      client.boardPage('Stock'),
      client.boardPage('Stock'),
      client.boardPage('Stock'),
    ]);
    expect(results.length, 3);
    expect(fetcher.requests, [stockPath]);
  });

  testWidgets('requests are spaced by the minimum interval', (tester) async {
    client = PttWebClient(
      fetcher,
      now: () => tester.binding.clock.now(),
    );
    final first = client.hotBoards();
    final second = client.boardPage('Stock');
    final third = client.article(articlePath);
    await tester.pump();
    expect(fetcher.requests, [hotPath]);
    await tester.pump(const Duration(milliseconds: 499));
    expect(fetcher.requests, [hotPath]);
    await tester.pump(const Duration(milliseconds: 2));
    expect(fetcher.requests, [hotPath, stockPath]);
    await tester.pump(const Duration(milliseconds: 501));
    expect(fetcher.requests, [hotPath, stockPath, articlePath]);
    await first;
    await second;
    await third;
  });

  test('invalid board names and paths never reach the network', () async {
    await expectLater(client.boardPage('bad name'), throwsWeb(PttWebError.notFound));
    await expectLater(client.boardPage('../etc'), throwsWeb(PttWebError.notFound));
    await expectLater(
      client.boardPage('Stock', path: '/bbs/Other/index1.html'),
      throwsWeb(PttWebError.notFound),
    );
    await expectLater(
      client.boardPage('Stock', path: 'https://evil.example/'),
      throwsWeb(PttWebError.notFound),
    );
    await expectLater(client.article('/etc/passwd'), throwsWeb(PttWebError.notFound));
    await expectLater(
      client.article('https://evil.example/bbs/Stock/M.1.A.AAA.html'),
      throwsWeb(PttWebError.notFound),
    );
    expect(fetcher.requests, isEmpty);
  });

  test('fetch errors pass through and are not cached', () async {
    fetcher.errors[stockPath] = const PttWebException(PttWebError.network, 'offline');
    await expectLater(client.boardPage('Stock'), throwsWeb(PttWebError.network));
    fetcher.errors.clear();
    expect((await client.boardPage('Stock')).posts.length, 3);
    expect(fetcher.requests, [stockPath, stockPath]);
  });

  test('a missing page is notFound', () async {
    await expectLater(client.boardPage('Nope'), throwsWeb(PttWebError.notFound));
  });

  test('unexpected fetcher failures become network errors', () async {
    fetcher.errors[hotPath] = StateError('boom');
    await expectLater(client.hotBoards(), throwsWeb(PttWebError.network));
  });

  // Review Focus 1
  test('a page that fails to parse is not cached', () async {
    fetcher.pages[stockPath] = '<html><body>維護中</body></html>';
    await expectLater(client.boardPage('Stock'), throwsWeb(PttWebError.format));
    fetcher.pages[stockPath] = stockIndexHtml;
    expect((await client.boardPage('Stock')).posts.length, 3);
    expect(fetcher.requests, [stockPath, stockPath]);
  });

  test('a failed request does not block the ones queued behind it', () async {
    fetcher.errors[hotPath] = const PttWebException(PttWebError.blocked);
    final failing = client.hotBoards();
    final following = client.boardPage('Stock');
    await expectLater(failing, throwsWeb(PttWebError.blocked));
    expect((await following).posts.length, 3);
  });
}
```

`test/core/web/http_page_fetcher_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/web/http_page_fetcher.dart';
import 'package:myptt/core/web/page_fetcher.dart';

Matcher throwsWeb(PttWebError kind) =>
    throwsA(isA<PttWebException>().having((e) => e.kind, 'kind', kind));

void main() {
  late HttpServer server;
  late HttpPageFetcher fetcher;
  late List<HttpHeaders> seen;

  setUp(() async {
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request.headers);
      final response = request.response;
      switch (request.uri.path) {
        case '/ok':
          response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
          response.write('<p>中文內容</p>');
        case '/missing':
          response.statusCode = 404;
        case '/forbidden':
          response.statusCode = 403;
        case '/limited':
          response.statusCode = 429;
        case '/unavailable':
          response.statusCode = 503;
        case '/challenge':
          response.write('<html><head><title>Just a moment...</title></head></html>');
        case '/error':
          response.statusCode = 500;
        case '/huge':
          response.write('x' * (3 * 1024 * 1024));
        case '/slow':
          await Future<void>.delayed(const Duration(seconds: 2));
          response.write('late');
      }
      await response.close();
    });
    fetcher = HttpPageFetcher(timeout: const Duration(milliseconds: 500));
  });

  tearDown(() async {
    fetcher.close();
    await server.close(force: true);
  });

  Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('returns the body as UTF-8 text', () async {
    expect(await fetcher.fetch(at('/ok')), '<p>中文內容</p>');
  });

  test('sends the age cookie and a browser user agent', () async {
    await fetcher.fetch(at('/ok'));
    expect(seen.single.value('cookie'), 'over18=1');
    expect(seen.single.value('user-agent'), contains('Mozilla/5.0'));
  });

  test('404 is notFound', () async {
    await expectLater(fetcher.fetch(at('/missing')), throwsWeb(PttWebError.notFound));
  });

  // Review Focus 2
  test('blocked responses are reported as blocked', () async {
    for (final path in ['/forbidden', '/limited', '/unavailable', '/challenge']) {
      await expectLater(fetcher.fetch(at(path)), throwsWeb(PttWebError.blocked),
          reason: path);
    }
    // One request each: nothing is retried automatically.
    expect(seen.length, 4);
  });

  test('other failures are network errors', () async {
    await expectLater(fetcher.fetch(at('/error')), throwsWeb(PttWebError.network));
    await expectLater(fetcher.fetch(at('/slow')), throwsWeb(PttWebError.network));
    await expectLater(fetcher.fetch(at('/huge')), throwsWeb(PttWebError.network));
    final port = server.port;
    await server.close(force: true);
    await expectLater(
      fetcher.fetch(Uri.parse('http://127.0.0.1:$port/ok')),
      throwsWeb(PttWebError.network),
    );
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/web/ptt_web_client_test.dart test/core/web/http_page_fetcher_test.dart
```

Expected: FAIL，訊息為找不到 `ptt_web_client.dart` 與 `http_page_fetcher.dart`。

- [ ] **Step 4: 實作 HTTP 抓取**

`lib/core/web/http_page_fetcher.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'page_fetcher.dart';

/// Downloads pages with dart:io, sending what www.ptt.cc expects from a
/// browser.
class HttpPageFetcher implements PageFetcher {
  HttpPageFetcher({HttpClient? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  static const String _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 '
      'Safari/604.1';

  /// Pages on the site are tens of kilobytes; anything far larger is not one.
  static const int _maxBytes = 2 * 1024 * 1024;

  /// Title of the interstitial Cloudflare serves instead of the page.
  static const String _challengeMarker = '<title>Just a moment...</title>';

  @override
  Future<String> fetch(Uri uri) async {
    try {
      return await _fetch(uri).timeout(timeout);
    } on PttWebException {
      rethrow;
    } on TimeoutException {
      throw const PttWebException(PttWebError.network, 'timeout');
    } catch (e) {
      throw PttWebException(PttWebError.network, e.runtimeType.toString());
    }
  }

  Future<String> _fetch(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.cookieHeader, 'over18=1');
    final response = await request.close();

    final status = response.statusCode;
    if (status == 404) {
      await response.drain<void>();
      throw const PttWebException(PttWebError.notFound);
    }
    if (status == 403 || status == 429 || status == 503) {
      await response.drain<void>();
      throw PttWebException(PttWebError.blocked, 'HTTP $status');
    }
    if (status != 200) {
      await response.drain<void>();
      throw PttWebException(PttWebError.network, 'HTTP $status');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _maxBytes) {
        throw const PttWebException(PttWebError.network, 'response too large');
      }
    }
    final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    if (body.contains(_challengeMarker)) {
      throw const PttWebException(PttWebError.blocked, 'bot check');
    }
    return body;
  }

  void close() => _client.close(force: true);
}
```

- [ ] **Step 5: 實作用戶端**

`lib/core/web/ptt_web_client.dart`：

```dart
import 'dart:async';

import 'models.dart';
import 'page_fetcher.dart';
import 'ptt_web_parser.dart';

class _Cached {
  const _Cached(this.at, this.body);

  final DateTime at;
  final String body;
}

/// Reads the public PTT web pages. Spaces requests out and caches recent
/// pages so that browsing does not hammer the site.
class PttWebClient {
  PttWebClient(
    this._fetcher, {
    this.minInterval = const Duration(milliseconds: 500),
    this.cacheTtl = const Duration(seconds: 60),
    this.cacheSize = 30,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final Uri base = Uri.parse('https://www.ptt.cc');
  static const String _hotBoardsPath = '/bbs/hotboards.html';

  final PageFetcher _fetcher;

  /// Shortest allowed gap between the starts of two requests.
  final Duration minInterval;
  final Duration cacheTtl;
  final int cacheSize;
  final DateTime Function() _now;

  // Insertion order doubles as least-recently-used order.
  final Map<String, _Cached> _cache = {};
  final Map<String, Future<String>> _inFlight = {};
  Future<void> _queue = Future<void>.value();
  DateTime? _lastRequest;

  /// The address of [path] for opening in a browser.
  static String browserUrl(String path) => base.resolve(path).toString();

  Future<List<BoardSummary>> hotBoards({bool refresh = false}) =>
      _read(_hotBoardsPath, refresh, parseHotBoards);

  /// The newest page of [board], or the page at [path] as given by an
  /// earlier page's [BoardPage.olderPath].
  Future<BoardPage> boardPage(String board, {String? path, bool refresh = false}) {
    final target = path ?? '/bbs/$board/index.html';
    if (!isIndexPath(target, board)) {
      return Future.error(const PttWebException(PttWebError.notFound, 'bad board'));
    }
    return _read(target, refresh, (source) => parseBoardIndex(source, board));
  }

  Future<Article> article(String path, {bool refresh = false}) {
    if (!isArticlePath(path)) {
      return Future.error(const PttWebException(PttWebError.notFound, 'bad path'));
    }
    return _read(path, refresh, parseArticle);
  }

  Future<T> _read<T>(String path, bool refresh, T Function(String) parse) async {
    final source = await _source(path, refresh);
    try {
      return parse(source);
    } on PttWebFormatException catch (e) {
      // Do not keep serving a page that cannot be understood.
      _cache.remove(path);
      throw PttWebException(PttWebError.format, e.message);
    }
  }

  Future<String> _source(String path, bool refresh) {
    if (!refresh) {
      final hit = _cache.remove(path);
      if (hit != null && _now().difference(hit.at) < cacheTtl) {
        _cache[path] = hit;
        return Future.value(hit.body);
      }
    }
    final running = _inFlight[path];
    if (running != null) return running;

    final request = _queue.then((_) => _fetch(path));
    // Later requests wait for this one whether it succeeds or fails.
    _queue = request.then<void>((_) {}, onError: (Object _) {});
    _inFlight[path] = request;
    return request.whenComplete(() {
      _inFlight.remove(path);
    });
  }

  Future<String> _fetch(String path) async {
    final last = _lastRequest;
    if (last != null) {
      final wait = minInterval - _now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequest = _now();

    final String body;
    try {
      body = await _fetcher.fetch(base.resolve(path));
    } on PttWebException {
      rethrow;
    } catch (e) {
      throw PttWebException(PttWebError.network, e.runtimeType.toString());
    }
    _cache.remove(path);
    _cache[path] = _Cached(_now(), body);
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return body;
  }
}
```

- [ ] **Step 6: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/web
```

Expected: `All tests passed!`

- [ ] **Step 7: 寫對真實網站的驗證工具並執行一次**

`tool/web_probe.dart`：

```dart
// Manual check against the real site: reads the hot boards, one board, and
// one article, and prints counts only. Four requests in total.
import 'dart:io';

import 'package:myptt/core/web/http_page_fetcher.dart';
import 'package:myptt/core/web/ptt_web_client.dart';

Future<void> main() async {
  final fetcher = HttpPageFetcher();
  final client = PttWebClient(fetcher);
  var ok = true;
  try {
    final boards = await client.hotBoards();
    stdout.writeln('hot boards: ${boards.length}');
    final page = await client.boardPage(boards.first.name);
    stdout.writeln('posts: ${page.posts.length}, pinned: ${page.pinned.length}, '
        'older page: ${page.olderPath != null}');
    final older = await client.boardPage(page.board, path: page.olderPath);
    stdout.writeln('older posts: ${older.posts.length}');
    final post = page.posts.firstWhere((p) => p.isAvailable);
    final article = await client.article(post.path!);
    stdout.writeln('article: title ${article.title.isNotEmpty}, '
        'body runs ${article.body.length}, pushes ${article.pushes.length}');
    ok = boards.isNotEmpty && page.posts.isNotEmpty && article.body.isNotEmpty;
  } catch (e) {
    stdout.writeln('FAIL: $e');
    ok = false;
  }
  fetcher.close();
  stdout.writeln(ok ? 'OK' : 'FAIL');
  exit(ok ? 0 : 1);
}
```

```bash
/c/dev/flutter/bin/dart.bat run tool/web_probe.dart
```

Expected: 最後一行為 `OK`，且看板數、文章數、內文段數皆大於 0。此工具只印出數量，不印出任何文章內容。

- [ ] **Step 8: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/core/web tool/web_probe.dart test/core/web test/support/fake_page_fetcher.dart
git commit -m "feat: add PTT web client with throttling and caching"
```

---

### Task 3: 記錄我的最愛

**Files:**
- Modify: `pubspec.yaml`（由 `flutter pub add` 修改）
- Create: `lib/core/favorites/favorites.dart`
- Create: `lib/platform/prefs_favorites_store.dart`
- Modify: `lib/core/session.dart`（新增兩個成員）
- Modify: `lib/ui/session_controller.dart`
- Create: `test/support/fake_favorites_store.dart`
- Test: `test/core/favorites/favorites_test.dart`、`test/platform/prefs_favorites_store_test.dart`
- Modify: `test/ui/session_controller_test.dart`（新增測試）

**Interfaces:**
- Consumes: `TerminalSession`、`SessionController`、`Credentials`、`rowString`、`isValidBoardName`（Task 1）
- Produces:
  - `class FavoritesSnapshot { const FavoritesSnapshot({required String userId, required Map<int, String> boards}); List<String> get names; Map<String, Object?> toJson(); static FavoritesSnapshot? fromJson(Object? json); bool sameAs(FavoritesSnapshot? other); }`（`names` 依編號排序且不重複）
  - `abstract class FavoritesStore { Future<FavoritesSnapshot?> load(); Future<void> save(FavoritesSnapshot snapshot); Future<void> clear(); }`
  - `bool isFavoritesTitle(String firstRow)`
  - `Map<int, String>? readFavoritesScreen(List<String> rows)`（不是最愛畫面時回傳 null）
  - `FavoritesSnapshot mergeFavorites(FavoritesSnapshot? old, String userId, Map<int, String> seen, {int pageSize = 20})`
  - `TerminalSession` 新增 `String rowText(int row)` 與 `List<String> get rowTexts`
  - `SessionController` 建構子新增具名參數 `FavoritesStore? favoritesStore`
  - `class PrefsFavoritesStore implements FavoritesStore { const PrefsFavoritesStore(); }`
  - 測試用 `class FakeFavoritesStore implements FavoritesStore`，有 `FavoritesSnapshot? saved`、`int saves`、`int clears`、`Object? loadError`、`Object? saveError`。

畫面格式的假設（依對 PTT 的了解，未以真實畫面驗證）：第一列去除開頭空白後以「【我的最愛】」開頭；每個看板一列，開頭最多 6 個非英數字元（空白或游標記號），接著是編號，再接一個可有可無的標記字元，然後是看板名稱。名稱為 `MyFavFolder` 的列是資料夾，略過。所有規則集中在 `favorites.dart` 開頭的常數與 `readFavoritesScreen`。

- [ ] **Step 1: 加入套件**

```bash
/c/dev/flutter/bin/flutter.bat pub add shared_preferences
```

Expected: 輸出包含 `+ shared_preferences`。

- [ ] **Step 2: 寫失敗的測試**

`test/support/fake_favorites_store.dart`：

```dart
import 'package:myptt/core/favorites/favorites.dart';

class FakeFavoritesStore implements FavoritesStore {
  FakeFavoritesStore([this.saved]);

  /// What the store currently holds.
  FavoritesSnapshot? saved;

  /// Number of times [save] and [clear] completed.
  int saves = 0;
  int clears = 0;

  /// When set, [load] or [save] throws it.
  Object? loadError;
  Object? saveError;

  @override
  Future<FavoritesSnapshot?> load() async {
    final error = loadError;
    if (error != null) throw error;
    return saved;
  }

  @override
  Future<void> save(FavoritesSnapshot snapshot) async {
    final error = saveError;
    if (error != null) throw error;
    saved = snapshot;
    saves++;
  }

  @override
  Future<void> clear() async {
    saved = null;
    clears++;
  }
}
```

`test/core/favorites/favorites_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/favorites/favorites.dart';

const title = '【我的最愛】                      批踢踢實業坊                 看板《SYSOP》';
const header = '   編號   看  板       類別   轉信  中   文   敘   述               人氣 板    主';
const footer = ' 選擇看板  (c)新文章模式 (v/V)已讀/未讀 (y)篩選/部分/全部 (m)切換最愛';

List<String> screen(List<String> boardRows, {String first = title}) =>
    [first, header, ...boardRows, footer];

void main() {
  group('reading the screen', () {
    test('reads number and name from each board row', () {
      final seen = readFavoritesScreen(screen([
        '     1 ˇGossiping     綜合 ◎【八卦】                              爆!',
        '●    2   Stock         學術 ◎股票板                                 HOT',
        '>    3   C_Chat        閒談 ◎希洽',
        '    12   Tech-Job      工作 ◎科技業',
      ]));
      expect(seen, {1: 'Gossiping', 2: 'Stock', 3: 'C_Chat', 12: 'Tech-Job'});
    });

    test('folders, dividers, and blank rows are skipped', () {
      final seen = readFavoritesScreen(screen([
        '     1   Stock         學術 ◎股票板',
        '     2   MyFavFolder   目錄 □我的資料夾',
        '     3   ------------------------------------------',
        '',
        '     5   Baseball      棒球 ◎棒球板',
      ]));
      expect(seen, {1: 'Stock', 5: 'Baseball'});
    });

    test('an empty favourites list is recognised as empty', () {
      expect(readFavoritesScreen(screen([])), isEmpty);
      expect(readFavoritesScreen([title]), isEmpty);
    });

    // Review Focus 4
    test('screens that merely mention favourites are not read', () {
      expect(
        readFavoritesScreen(screen(
          ['     1   Stock         學術 ◎股票板'],
          first: '【看板列表】                      批踢踢實業坊',
        )),
        isNull,
      );
      expect(
        readFavoritesScreen([
          ' 作者  alice (愛麗絲)                                     看板  Stock',
          ' 標題  【我的最愛】看板分享',
          '     1   Stock         學術 ◎股票板',
        ]),
        isNull,
      );
      expect(
        readFavoritesScreen(screen(
          ['     1   Stock         學術 ◎股票板'],
          first: '【板主:mod】      我的最愛討論      看板《Stock》',
        )),
        isNull,
      );
      expect(readFavoritesScreen([]), isNull);
      expect(isFavoritesTitle('   【我的最愛】  批踢踢實業坊'), isTrue);
      expect(isFavoritesTitle('我的最愛'), isFalse);
    });

    test('rows that only look numeric are ignored', () {
      final seen = readFavoritesScreen(screen([
        '2026/10/08 Stock 的公告',
        '     7',
        '     8   x',
        '     9   ThirteenChars 太長的名稱',
        '    10   中文板名      不是英數',
      ]));
      expect(seen, isEmpty);
    });
  });

  group('merging', () {
    FavoritesSnapshot snap(String user, Map<int, String> boards) =>
        FavoritesSnapshot(userId: user, boards: boards);

    test('the first screen starts the record', () {
      final merged = mergeFavorites(null, 'alice', {1: 'Stock', 2: 'C_Chat'});
      expect(merged.userId, 'alice');
      expect(merged.names, ['Stock', 'C_Chat']);
    });

    test('a later page adds to what was seen before', () {
      final page1 = {for (var i = 1; i <= 20; i++) i: 'Board$i'};
      final first = mergeFavorites(null, 'alice', page1);
      final merged = mergeFavorites(first, 'alice', {21: 'Stock', 22: 'C_Chat'});
      expect(merged.names.length, 22);
      expect(merged.names.first, 'Board1');
      expect(merged.names.last, 'C_Chat');
    });

    test('a changed entry replaces the old one at that number', () {
      final merged = mergeFavorites(
        snap('alice', {1: 'Stock', 2: 'C_Chat'}),
        'alice',
        {1: 'Stock', 2: 'Baseball'},
      );
      expect(merged.names, ['Stock', 'Baseball']);
    });

    test('a short page is the last page and drops later numbers', () {
      final merged = mergeFavorites(
        snap('alice', {1: 'A1', 2: 'B2', 3: 'C3', 25: 'Old'}),
        'alice',
        {1: 'A1', 2: 'B2'},
      );
      expect(merged.names, ['A1', 'B2']);
    });

    test('a full page keeps later numbers', () {
      final page1 = {for (var i = 1; i <= 20; i++) i: 'Board$i'};
      final merged = mergeFavorites(
        snap('alice', {...page1, 21: 'Later'}),
        'alice',
        page1,
      );
      expect(merged.names.last, 'Later');
    });

    test('an empty screen changes nothing', () {
      final old = snap('alice', {1: 'Stock'});
      expect(mergeFavorites(old, 'alice', {}).sameAs(old), isTrue);
    });

    test('a different account starts over', () {
      final merged = mergeFavorites(
        snap('alice', {1: 'Stock', 2: 'C_Chat'}),
        'bob',
        {1: 'Baseball'},
      );
      expect(merged.userId, 'bob');
      expect(merged.names, ['Baseball']);
    });

    test('names are ordered by number and not repeated', () {
      expect(snap('a', {3: 'Stock', 1: 'C_Chat', 2: 'Stock'}).names,
          ['C_Chat', 'Stock']);
    });
  });

  group('json', () {
    test('round trip', () {
      const original = FavoritesSnapshot(userId: 'alice', boards: {1: 'Stock', 12: 'C_Chat'});
      final restored = FavoritesSnapshot.fromJson(original.toJson());
      expect(restored!.sameAs(original), isTrue);
    });

    test('damaged data yields null or drops bad entries', () {
      expect(FavoritesSnapshot.fromJson(null), isNull);
      expect(FavoritesSnapshot.fromJson('text'), isNull);
      expect(FavoritesSnapshot.fromJson({'boards': {}}), isNull);
      expect(FavoritesSnapshot.fromJson({'userId': 5, 'boards': {}}), isNull);
      expect(FavoritesSnapshot.fromJson({'userId': 'a', 'boards': 'x'}), isNull);
      final partial = FavoritesSnapshot.fromJson({
        'userId': 'alice',
        'boards': {'1': 'Stock', 'x': 'C_Chat', '3': 'bad name', '4': 7, '-2': 'Neg'},
      });
      expect(partial!.boards, {1: 'Stock'});
    });
  });
}
```

`test/platform/prefs_favorites_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/favorites/favorites.dart';
import 'package:myptt/platform/prefs_favorites_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = PrefsFavoritesStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    expect(await store.load(), isNull);
  });

  test('saves, loads, and clears', () async {
    await store.save(const FavoritesSnapshot(userId: 'alice', boards: {1: 'Stock', 2: 'C_Chat'}));
    final loaded = await store.load();
    expect(loaded!.userId, 'alice');
    expect(loaded.names, ['Stock', 'C_Chat']);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('unreadable stored data is treated as empty', () async {
    SharedPreferences.setMockInitialValues({'favorites_v1': '{not json'});
    expect(await store.load(), isNull);
    SharedPreferences.setMockInitialValues({'favorites_v1': '[1,2,3]'});
    expect(await store.load(), isNull);
  });
}
```

在 `test/ui/session_controller_test.dart` 做三處修改。

檔案開頭的 import 區加入：

```dart
import 'package:myptt/core/favorites/favorites.dart';

import '../support/fake_favorites_store.dart';
```

把 `create` 函式換成：

```dart
  late FakeFavoritesStore favorites;

  void create({Credentials? credentials, bool recordFavorites = false}) {
    conn = FakeConnection();
    favorites = FakeFavoritesStore();
    controller = SessionController(
      TerminalSession(conn, codec),
      credentials: credentials,
      favoritesStore: recordFavorites ? favorites : null,
    );
  }
```

在 `nothing happens after dispose` 測試之前加入：

```dart
  const favouritesScreen = '【我的最愛】                      批踢踢實業坊\r\n'
      '   編號   看  板       類別   轉信  中   文   敘   述\r\n'
      '     1 ˇGossiping     綜合 ◎八卦\r\n'
      '●    2   Stock         學術 ◎股票';

  testWidgets('favourites are recorded when the screen is visited', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'), recordFavorites: true);
    await controller.connect();
    await tester.pump();
    show('主選單');
    await tester.pump();
    expect(favorites.saves, 0);

    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saved?.userId, 'alice');
    expect(favorites.saved?.names, ['Gossiping', 'Stock']);
    expect(conn.sent, isEmpty);

    // Redrawing the same screen does not write again.
    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saves, 1);
    controller.dispose();
  });

  testWidgets('favourites are not recorded without a store or credentials',
      (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saves, 0);
    controller.dispose();

    create(recordFavorites: true);
    await controller.connect();
    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saves, 0);
    controller.dispose();
  });

  testWidgets('recording builds on what was stored and survives store failures',
      (tester) async {
    create(credentials: const Credentials('alice', 's3cret'), recordFavorites: true);
    favorites.saved = FavoritesSnapshot(
      userId: 'alice',
      boards: {for (var i = 1; i <= 20; i++) i: 'Board$i', 21: 'Later'},
    );
    // A fresh controller so the stored list is loaded at construction.
    controller.dispose();
    controller = SessionController(
      TerminalSession(conn = FakeConnection(), codec),
      credentials: const Credentials('alice', 's3cret'),
      favoritesStore: favorites,
    );
    await controller.connect();
    await tester.pump();

    favorites.saveError = StateError('disk full');
    show(favouritesScreen);
    await tester.pump();
    expect(tester.takeException(), isNull);

    favorites.saveError = null;
    show('$favouritesScreen\r\n     3   C_Chat        閒談 ◎希洽');
    await tester.pump();
    // Three rows is a short page, so numbers after 3 are dropped.
    expect(favorites.saved?.names, ['Gossiping', 'Stock', 'C_Chat']);
    controller.dispose();
  });
```

- [ ] **Step 3: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/favorites test/platform/prefs_favorites_store_test.dart test/ui/session_controller_test.dart
```

Expected: FAIL，訊息為找不到 `favorites.dart`、`prefs_favorites_store.dart`，以及 `SessionController` 沒有 `favoritesStore` 參數。

- [ ] **Step 4: 實作辨識、合併與介面**

`lib/core/favorites/favorites.dart`：

```dart
import '../web/ptt_web_parser.dart';

/// How the favourites screen starts, after leading spaces.
const String _titlePrefix = '【我的最愛】';

/// Up to six non-alphanumeric characters (spaces, a cursor mark), the entry
/// number, an optional one-character mark, then the board name.
final RegExp _boardRow = RegExp(
  r'^[^0-9A-Za-z]{0,6}(\d{1,4})\s*[^\sA-Za-z0-9_\-]?\s*'
  r'([A-Za-z0-9][A-Za-z0-9_\-]{1,11})(?=\s|$)',
);

/// The name PTT shows for a folder inside the favourites list.
const String _folderName = 'MyFavFolder';

/// The favourite boards recorded for one account, by entry number.
class FavoritesSnapshot {
  const FavoritesSnapshot({required this.userId, required this.boards});

  final String userId;
  final Map<int, String> boards;

  /// Board names in entry order, without repeats.
  List<String> get names {
    final numbers = boards.keys.toList()..sort();
    final seen = <String>{};
    return [
      for (final n in numbers)
        if (seen.add(boards[n]!)) boards[n]!,
    ];
  }

  bool sameAs(FavoritesSnapshot? other) {
    if (other == null || other.userId != userId) return false;
    if (other.boards.length != boards.length) return false;
    return boards.entries.every((e) => other.boards[e.key] == e.value);
  }

  Map<String, Object?> toJson() => {
        'userId': userId,
        'boards': {for (final e in boards.entries) '${e.key}': e.value},
      };

  /// Returns null if [json] is not a snapshot; invalid entries are dropped.
  static FavoritesSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final userId = json['userId'];
    final raw = json['boards'];
    if (userId is! String || raw is! Map) return null;
    final boards = <int, String>{};
    for (final e in raw.entries) {
      final key = e.key;
      final value = e.value;
      final number = key is String ? int.tryParse(key) : null;
      if (number == null || number < 1) continue;
      if (value is! String || !isValidBoardName(value)) continue;
      boards[number] = value;
    }
    return FavoritesSnapshot(userId: userId, boards: boards);
  }
}

/// Where the recorded favourites live. Board names are not secret, so this
/// is ordinary local storage rather than the keychain.
abstract class FavoritesStore {
  Future<FavoritesSnapshot?> load();
  Future<void> save(FavoritesSnapshot snapshot);
  Future<void> clear();
}

/// Whether [firstRow] is the title bar of the favourites screen.
bool isFavoritesTitle(String firstRow) =>
    firstRow.trimLeft().startsWith(_titlePrefix);

/// Reads the entries shown on the favourites screen, or returns null if
/// [rows] is some other screen.
Map<int, String>? readFavoritesScreen(List<String> rows) {
  if (rows.isEmpty || !isFavoritesTitle(rows.first)) return null;
  final seen = <int, String>{};
  for (final row in rows.skip(1)) {
    final m = _boardRow.firstMatch(row);
    if (m == null) continue;
    final name = m.group(2)!;
    if (name == _folderName || !isValidBoardName(name)) continue;
    seen[int.parse(m.group(1)!)] = name;
  }
  return seen;
}

/// Folds one visit to the favourites screen into the stored record.
///
/// A screen showing fewer than [pageSize] entries is the last page, so
/// anything recorded after its highest number no longer exists.
FavoritesSnapshot mergeFavorites(
  FavoritesSnapshot? old,
  String userId,
  Map<int, String> seen, {
  int pageSize = 20,
}) {
  final boards = <int, String>{
    if (old != null && old.userId == userId) ...old.boards,
    ...seen,
  };
  if (seen.isNotEmpty && seen.length < pageSize) {
    final last = seen.keys.reduce((a, b) => a > b ? a : b);
    boards.removeWhere((number, _) => number > last);
  }
  return FavoritesSnapshot(userId: userId, boards: boards);
}
```

- [ ] **Step 5: 修改工作階段與連線控制**

在 `lib/core/session.dart` 的 `cursorRowText` 之後加入：

```dart
  /// Text of [row], without trailing spaces.
  String rowText(int row) => rowString(screen, row, codec);

  /// Text of every row, top to bottom.
  List<String> get rowTexts =>
      [for (var r = 0; r < screen.rows; r++) rowString(screen, r, codec)];
```

在 `lib/ui/session_controller.dart` 做下列修改。

import 區加入：

```dart
import '../core/favorites/favorites.dart';
```

建構子換成：

```dart
  SessionController(
    this.session, {
    this.credentials,
    this.favoritesStore,
    this.loginTimeout = const Duration(seconds: 10),
  }) {
    _antiIdle = AntiIdle(session);
    _updates = session.updates.listen((_) => _onUpdate());
    _loadFavorites();
  }
```

在 `loginTimeout` 欄位之前加入：

```dart
  /// When set together with [credentials], the favourites screen is
  /// recorded here whenever the user visits it.
  final FavoritesStore? favoritesStore;
```

在 `_lastNotified` 欄位之後加入：

```dart
  FavoritesSnapshot? _favorites;
  bool _favoritesLoaded = false;
```

在 `_onUpdate` 的 `if (status == ConnectionStatus.connected) {` 區塊內、`final login = _autoLogin;` 之前加入：

```dart
      _recordFavorites();
```

在 `_stopAutoLogin` 方法之前加入：

```dart
  Future<void> _loadFavorites() async {
    final store = favoritesStore;
    if (store == null || credentials == null) return;
    try {
      _favorites = await store.load();
    } catch (_) {
      // An unreadable record is the same as none.
    }
    _favoritesLoaded = true;
  }

  /// Notes down the favourites screen if that is what is showing. Never
  /// sends anything to the server.
  void _recordFavorites() {
    final store = favoritesStore;
    final userId = credentials?.userId;
    if (store == null || userId == null || !_favoritesLoaded) return;
    if (!isFavoritesTitle(session.rowText(0))) return;
    final seen = readFavoritesScreen(session.rowTexts);
    if (seen == null || seen.isEmpty) return;
    final merged = mergeFavorites(_favorites, userId, seen);
    if (merged.sameAs(_favorites)) return;
    _favorites = merged;
    unawaited(store.save(merged).catchError((Object _) {}));
  }
```

- [ ] **Step 6: 實作儲存**

`lib/platform/prefs_favorites_store.dart`：

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/favorites/favorites.dart';

/// Keeps the recorded favourites in the app's ordinary preferences.
class PrefsFavoritesStore implements FavoritesStore {
  const PrefsFavoritesStore();

  static const String _key = 'favorites_v1';

  @override
  Future<FavoritesSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return FavoritesSnapshot.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(FavoritesSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

- [ ] **Step 7: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/core/favorites test/platform test/ui/session_controller_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add -A lib test pubspec.yaml pubspec.lock windows ios
git commit -m "feat: record the favourites screen passively while logged in"
```

---

### Task 4: 瀏覽頁面

**Files:**
- Create: `lib/ui/web/load_view.dart`
- Create: `lib/ui/web/board_list_page.dart`
- Create: `lib/ui/web/post_list_page.dart`
- Create: `lib/ui/web/article_page.dart`
- Test: `test/ui/web/browse_pages_test.dart`

**Interfaces:**
- Consumes: `PttWebClient`、`PttWebException`、`PttWebError`、資料型別（Task 1、2）；`FavoritesStore`、`FavoritesSnapshot`（Task 3）；`ansiPalette`（計畫一）；`FakePageFetcher`、`FakeFavoritesStore`、測試資料
- Produces:
  - `String webErrorMessage(Object error)`
  - `class LoadView<T> extends StatefulWidget { const LoadView({super.key, required Future<T> Function(bool refresh) load, required Widget Function(BuildContext context, T data, Future<void> Function() refresh) builder, String? browserUrl, Future<bool> Function(String url)? openUrl}); }`
  - `class BoardListPage extends StatefulWidget { const BoardListPage({super.key, required PttWebClient client, FavoritesStore? favoritesStore, Future<bool> Function(String url)? openUrl}); }`
  - `class PostListPage extends StatelessWidget { const PostListPage({super.key, required PttWebClient client, required String board, Future<bool> Function(String url)? openUrl}); }`
  - `class ArticlePage extends StatelessWidget { const ArticlePage({super.key, required PttWebClient client, required String path, required String title, Future<bool> Function(String url)? openUrl}); }`

錯誤訊息：

| 錯誤 | 訊息 |
|---|---|
| `network` | 無法連線，請檢查網路 |
| `notFound` | 找不到這個看板或文章，可能不是公開看板 |
| `blocked` | 網站暫時拒絕連線，請稍後再試 |
| `format` | 無法解析頁面內容 |
| 其他 | 發生未預期的錯誤 |

- [ ] **Step 1: 寫失敗的測試**

`test/ui/web/browse_pages_test.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/favorites/favorites.dart';
import 'package:myptt/core/web/page_fetcher.dart';
import 'package:myptt/core/web/ptt_web_client.dart';
import 'package:myptt/ui/web/article_page.dart';
import 'package:myptt/ui/web/board_list_page.dart';
import 'package:myptt/ui/web/load_view.dart';
import 'package:myptt/ui/web/post_list_page.dart';

import '../../support/fake_favorites_store.dart';
import '../../support/fake_page_fetcher.dart';
import '../../support/web_fixtures.dart';

const hotPath = '/bbs/hotboards.html';
const stockPath = '/bbs/Stock/index.html';
const olderPath = '/bbs/Stock/index99.html';
const articlePath = '/bbs/Stock/M.1000000001.A.AAA.html';

/// A fetcher whose responses wait until the test releases them.
class GatedFetcher extends FakePageFetcher {
  Completer<void> gate = Completer<void>();

  @override
  Future<String> fetch(Uri uri) async {
    await gate.future;
    return super.fetch(uri);
  }
}

void main() {
  late FakePageFetcher fetcher;
  late PttWebClient client;
  late List<String> opened;

  Future<bool> openUrl(String url) async {
    opened.add(url);
    return true;
  }

  void useFetcher(FakePageFetcher f) {
    fetcher = f
      ..pages[hotPath] = hotBoardsHtml
      ..pages[stockPath] = stockIndexHtml
      ..pages[olderPath] = stockOlderIndexHtml
      ..pages[articlePath] = articleHtml;
    client = PttWebClient(fetcher, minInterval: Duration.zero);
  }

  setUp(() {
    opened = [];
    useFetcher(FakePageFetcher());
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump();
  }

  /// Lets a navigation animation and the new page's load finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  test('error messages are in Chinese and never show raw exceptions', () {
    expect(webErrorMessage(const PttWebException(PttWebError.network, 'SocketException')),
        '無法連線，請檢查網路');
    expect(webErrorMessage(const PttWebException(PttWebError.notFound)),
        '找不到這個看板或文章，可能不是公開看板');
    expect(webErrorMessage(const PttWebException(PttWebError.blocked)),
        '網站暫時拒絕連線，請稍後再試');
    expect(webErrorMessage(const PttWebException(PttWebError.format)), '無法解析頁面內容');
    expect(webErrorMessage(StateError('boom')), '發生未預期的錯誤');
  });

  group('board list', () {
    testWidgets('shows hot boards and opens one', (tester) async {
      await pumpPage(tester, BoardListPage(client: client, openUrl: openUrl));
      expect(find.text('熱門看板'), findsOneWidget);
      expect(find.text('Gossiping'), findsOneWidget);
      expect(find.text('Stock'), findsOneWidget);
      expect(find.textContaining('我的最愛'), findsNothing);

      await tester.tap(find.text('Stock'));
      await settle(tester);
      expect(find.byType(PostListPage), findsOneWidget);
      expect(find.text('[新聞] 第三篇'), findsOneWidget);
    });

    testWidgets('recorded favourites are listed above the hot boards',
        (tester) async {
      final store = FakeFavoritesStore(
        const FavoritesSnapshot(userId: 'alice', boards: {1: 'Baseball', 2: 'Stock'}),
      );
      await pumpPage(tester, BoardListPage(client: client, favoritesStore: store));
      expect(find.text('我的最愛（alice）'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Baseball'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Stock'), findsOneWidget);
      final favY = tester.getTopLeft(find.text('我的最愛（alice）')).dy;
      final hotY = tester.getTopLeft(find.text('熱門看板')).dy;
      expect(favY, lessThan(hotY));

      await tester.tap(find.widgetWithText(ActionChip, 'Stock'));
      await settle(tester);
      expect(find.byType(PostListPage), findsOneWidget);
    });

    testWidgets('favourites still show when the hot boards fail to load',
        (tester) async {
      fetcher.errors[hotPath] = const PttWebException(PttWebError.network);
      final store = FakeFavoritesStore(
        const FavoritesSnapshot(userId: 'alice', boards: {1: 'Stock'}),
      );
      await pumpPage(tester, BoardListPage(client: client, favoritesStore: store));
      expect(find.text('無法連線，請檢查網路'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Stock'), findsOneWidget);

      fetcher.errors.clear();
      await tester.tap(find.text('重試'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Gossiping'), findsOneWidget);
    });

    testWidgets('an unreadable favourites store is ignored', (tester) async {
      final store = FakeFavoritesStore()..loadError = StateError('broken');
      await pumpPage(tester, BoardListPage(client: client, favoritesStore: store));
      expect(tester.takeException(), isNull);
      expect(find.text('Gossiping'), findsOneWidget);
    });

    testWidgets('going to a board by name validates the name', (tester) async {
      await pumpPage(tester, BoardListPage(client: client));
      await tester.enterText(find.byType(TextField), 'bad name');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(find.text('看板名稱只能是 1 到 12 個英文字母、數字、底線或連字號'), findsOneWidget);
      expect(find.byType(PostListPage), findsNothing);

      await tester.enterText(find.byType(TextField), ' Stock ');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settle(tester);
      expect(find.byType(PostListPage), findsOneWidget);
    });
  });

  group('post list', () {
    testWidgets('lists posts newest first with pinned posts marked', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      expect(find.text('Stock'), findsOneWidget);
      final third = tester.getTopLeft(find.text('[新聞] 第三篇')).dy;
      final first = tester.getTopLeft(find.text('[請益] 第一篇')).dy;
      expect(third, lessThan(first));
      expect(find.text('置底'), findsOneWidget);
      expect(find.text('[公告] 板規'), findsOneWidget);
      expect(find.text('爆'), findsOneWidget);
    });

    testWidgets('deleted posts cannot be opened', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      await tester.tap(find.text('(本文已被刪除) [bob]'));
      await settle(tester);
      expect(find.byType(ArticlePage), findsNothing);
      expect(fetcher.requests, [stockPath]);
    });

    testWidgets('opens an article', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Stock', openUrl: openUrl));
      await tester.tap(find.text('[請益] 第一篇'));
      await settle(tester);
      expect(find.byType(ArticlePage), findsOneWidget);
      expect(find.textContaining('第一行內文', findRichText: true), findsOneWidget);
    });

    testWidgets('loads older posts below the current ones', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      expect(find.text('[閒聊] 更早二'), findsNothing);
      await tester.tap(find.text('載入更早的文章'));
      await tester.pump();
      await tester.pump();
      expect(find.text('[閒聊] 更早二'), findsOneWidget);
      expect(find.text('[閒聊] 更早一'), findsOneWidget);
      final current = tester.getTopLeft(find.text('[請益] 第一篇')).dy;
      final older = tester.getTopLeft(find.text('[閒聊] 更早二')).dy;
      expect(current, lessThan(older));
    });

    // Review Focus 5
    testWidgets('loading older posts twice does not duplicate them', (tester) async {
      final gated = GatedFetcher()..gate.complete();
      useFetcher(gated);
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));

      gated.gate = Completer<void>();
      await tester.tap(find.text('載入更早的文章'));
      await tester.pump();
      // The button is replaced by a progress indicator while loading.
      expect(find.text('載入更早的文章'), findsNothing);
      gated.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('[閒聊] 更早二'), findsOneWidget);
      expect(gated.requests.where((p) => p == olderPath).length, 1);
    });

    testWidgets('a failure loading older posts keeps the current list', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      fetcher.errors[olderPath] = const PttWebException(PttWebError.blocked);
      await tester.tap(find.text('載入更早的文章'));
      await tester.pump();
      await tester.pump();
      expect(find.text('網站暫時拒絕連線，請稍後再試'), findsOneWidget);
      expect(find.text('[請益] 第一篇'), findsOneWidget);
      expect(find.text('載入更早的文章'), findsOneWidget);
    });

    testWidgets('a missing board offers retry and the browser', (tester) async {
      await pumpPage(tester, PostListPage(client: client, board: 'Nope', openUrl: openUrl));
      expect(find.text('找不到這個看板或文章，可能不是公開看板'), findsOneWidget);
      await tester.tap(find.text('以瀏覽器開啟'));
      expect(opened, ['https://www.ptt.cc/bbs/Nope/index.html']);
      await tester.tap(find.text('重試'));
      await tester.pump();
      await tester.pump();
      expect(fetcher.requests, ['/bbs/Nope/index.html', '/bbs/Nope/index.html']);
    });

    testWidgets('a page that cannot be parsed is reported, not crashed on',
        (tester) async {
      fetcher.pages[stockPath] = '<html><body>維護中</body></html>';
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      expect(find.text('無法解析頁面內容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Review Focus 5
    testWidgets('leaving before the load finishes is safe', (tester) async {
      final gated = GatedFetcher();
      useFetcher(gated);
      await pumpPage(tester, PostListPage(client: client, board: 'Stock'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gated.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('article', () {
    Widget page() => ArticlePage(
          client: client,
          path: articlePath,
          title: '[請益] 第一篇',
          openUrl: openUrl,
        );

    testWidgets('shows header, body, and pushes', (tester) async {
      await pumpPage(tester, page());
      expect(find.text('[請益] 第一篇'), findsWidgets);
      expect(find.textContaining('alice (愛麗絲)'), findsOneWidget);
      expect(find.textContaining('第一行內文', findRichText: true), findsOneWidget);
      expect(find.textContaining('綠色高亮', findRichText: true), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('推一個'), findsOneWidget);
      expect(find.text('10/05 12:01'), findsOneWidget);
      expect(find.textContaining('不同意'), findsOneWidget);
    });

    testWidgets('coloured text uses the ANSI palette', (tester) async {
      await pumpPage(tester, page());
      final body = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('第一行內文'),
        ),
      );
      TextSpan? green;
      body.text.visitChildren((span) {
        if (span is TextSpan && span.text == '綠色高亮') green = span;
        return true;
      });
      expect(green?.style?.color, const Color(0xFF00FF00));
    });

    testWidgets('tapping a link in the body opens it', (tester) async {
      await pumpPage(tester, page());
      final body = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('第一行內文'),
      );
      final rich = tester.widget<RichText>(body);
      TextSpan? link;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'https://example.com/a') link = span;
        return true;
      });
      expect(link?.recognizer, isNotNull);
      (link!.recognizer! as dynamic).onTap();
      expect(opened, ['https://example.com/a']);

      TextSpan? bad;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '壞連結') bad = span;
        return true;
      });
      expect(bad?.recognizer, isNull);
    });

    testWidgets('the app bar action opens the article in the browser', (tester) async {
      await pumpPage(tester, page());
      await tester.tap(find.byTooltip('以瀏覽器開啟'));
      expect(opened, ['https://www.ptt.cc$articlePath']);
    });

    testWidgets('a blocked article shows the reason and can be retried',
        (tester) async {
      fetcher.errors[articlePath] = const PttWebException(PttWebError.blocked);
      await pumpPage(tester, page());
      expect(find.text('網站暫時拒絕連線，請稍後再試'), findsOneWidget);
      fetcher.errors.clear();
      await tester.tap(find.text('重試'));
      await tester.pump();
      await tester.pump();
      expect(find.text('推一個'), findsOneWidget);
    });

    testWidgets('an article with no pushes says so', (tester) async {
      fetcher.pages[articlePath] = '<div id="main-content">只有內文</div>';
      await pumpPage(tester, page());
      expect(find.textContaining('只有內文', findRichText: true), findsOneWidget);
      expect(find.text('尚無推文'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui/web/browse_pages_test.dart
```

Expected: FAIL，訊息為找不到 `lib/ui/web/` 底下的四個檔案。

- [ ] **Step 3: 實作共用的載入元件**

`lib/ui/web/load_view.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/web/page_fetcher.dart';

/// What to tell the user about [error]. Raw exception text is never shown.
String webErrorMessage(Object error) {
  if (error is! PttWebException) return '發生未預期的錯誤';
  return switch (error.kind) {
    PttWebError.network => '無法連線，請檢查網路',
    PttWebError.notFound => '找不到這個看板或文章，可能不是公開看板',
    PttWebError.blocked => '網站暫時拒絕連線，請稍後再試',
    PttWebError.format => '無法解析頁面內容',
  };
}

/// Loads something once, then shows a spinner, an error with a retry, or
/// the content. Failures are never retried automatically.
class LoadView<T> extends StatefulWidget {
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.browserUrl,
    this.openUrl,
  });

  /// Called with true when the user asked for fresh data.
  final Future<T> Function(bool refresh) load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() refresh,
  ) builder;

  /// Offered on the error screen as "open in browser".
  final String? browserUrl;
  final Future<bool> Function(String url)? openUrl;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = false;

  /// Bumped on every load so a slow earlier load cannot overwrite a newer one.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _run(false);
  }

  Future<void> _run(bool refresh) async {
    final attempt = ++_attempt;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load(refresh);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _data = data;
        _hasData = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (_hasData) {
      return Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(webErrorMessage(error)),
            ),
          Expanded(child: widget.builder(context, _data as T, () => _run(true))),
        ],
      );
    }
    if (_loading || error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final browserUrl = widget.browserUrl;
    final openUrl = widget.openUrl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(webErrorMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _run(true), child: const Text('重試')),
            if (browserUrl != null && openUrl != null)
              TextButton(
                onPressed: () => openUrl(browserUrl),
                child: const Text('以瀏覽器開啟'),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 實作文章閱讀頁**

`lib/ui/web/article_page.dart`：

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/web/models.dart';
import '../../core/web/ptt_web_client.dart';
import '../palette.dart';
import 'load_view.dart';

class ArticlePage extends StatelessWidget {
  const ArticlePage({
    super.key,
    required this.client,
    required this.path,
    required this.title,
    this.openUrl,
  });

  final PttWebClient client;

  /// Site-relative path of the article.
  final String path;

  /// Shown in the app bar while the article loads.
  final String title;
  final Future<bool> Function(String url)? openUrl;

  @override
  Widget build(BuildContext context) {
    final openUrl = this.openUrl;
    final browserUrl = PttWebClient.browserUrl(path);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (openUrl != null)
            IconButton(
              tooltip: '以瀏覽器開啟',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => openUrl(browserUrl),
            ),
        ],
      ),
      body: LoadView<Article>(
        load: (refresh) => client.article(path, refresh: refresh),
        browserUrl: browserUrl,
        openUrl: openUrl,
        builder: (context, article, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: _ArticleBody(
            key: ObjectKey(article),
            article: article,
            fallbackTitle: title,
            openUrl: openUrl,
          ),
        ),
      ),
    );
  }
}

class _ArticleBody extends StatefulWidget {
  const _ArticleBody({
    super.key,
    required this.article,
    required this.fallbackTitle,
    required this.openUrl,
  });

  final Article article;
  final String fallbackTitle;
  final Future<bool> Function(String url)? openUrl;

  @override
  State<_ArticleBody> createState() => _ArticleBodyState();
}

class _ArticleBodyState extends State<_ArticleBody> {
  final List<TapGestureRecognizer> _recognizers = [];
  late final List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = [for (final run in widget.article.body) _span(run)];
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TextSpan _span(TextRun run) {
    final fg = run.fg;
    final bg = run.bg;
    final link = run.link;
    final openUrl = widget.openUrl;
    TapGestureRecognizer? recognizer;
    if (link != null && openUrl != null) {
      recognizer = TapGestureRecognizer()..onTap = () => openUrl(link);
      _recognizers.add(recognizer);
    }
    return TextSpan(
      text: run.text,
      recognizer: recognizer,
      style: TextStyle(
        color: fg == null
            ? (run.bright ? ansiPalette[15] : null)
            : ansiPalette[fg + (run.bright ? 8 : 0)],
        backgroundColor: bg == null ? null : ansiPalette[bg],
        decoration: link == null ? null : TextDecoration.underline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final theme = Theme.of(context);
    final title = article.title.isEmpty ? widget.fallbackTitle : article.title;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          [article.author, article.board, article.time]
              .where((s) => s.isNotEmpty)
              .join('　'),
          style: theme.textTheme.bodySmall,
        ),
        const Divider(),
        Text.rich(
          TextSpan(children: _spans),
          style: TextStyle(color: ansiPalette[7], height: 1.4),
        ),
        const Divider(),
        if (article.pushes.isEmpty)
          Text('尚無推文', style: theme.textTheme.bodySmall)
        else
          for (final push in article.pushes) _PushRow(push: push),
      ],
    );
  }
}

class _PushRow extends StatelessWidget {
  const _PushRow({required this.push});

  final Push push;

  Color get _tagColor => switch (push.tag) {
        '推' => ansiPalette[15],
        '噓' => ansiPalette[9],
        _ => ansiPalette[8],
      };

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, child: Text(push.tag, style: TextStyle(color: _tagColor))),
          Text(push.userId, style: TextStyle(color: ansiPalette[11])),
          const SizedBox(width: 6),
          Expanded(child: Text(push.content)),
          const SizedBox(width: 6),
          Text(push.time, style: small),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 實作文章列表頁**

`lib/ui/web/post_list_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/web/models.dart';
import '../../core/web/ptt_web_client.dart';
import 'article_page.dart';
import 'load_view.dart';

class PostListPage extends StatelessWidget {
  const PostListPage({
    super.key,
    required this.client,
    required this.board,
    this.openUrl,
  });

  final PttWebClient client;
  final String board;
  final Future<bool> Function(String url)? openUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(board)),
      body: LoadView<BoardPage>(
        load: (refresh) => client.boardPage(board, refresh: refresh),
        browserUrl: PttWebClient.browserUrl('/bbs/$board/index.html'),
        openUrl: openUrl,
        builder: (context, page, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: _PostList(
            // A fresh first page discards the older pages loaded under it.
            key: ObjectKey(page),
            client: client,
            firstPage: page,
            openUrl: openUrl,
          ),
        ),
      ),
    );
  }
}

class _PostList extends StatefulWidget {
  const _PostList({
    super.key,
    required this.client,
    required this.firstPage,
    required this.openUrl,
  });

  final PttWebClient client;
  final BoardPage firstPage;
  final Future<bool> Function(String url)? openUrl;

  @override
  State<_PostList> createState() => _PostListState();
}

class _PostListState extends State<_PostList> {
  late final List<PostSummary> _posts = [...widget.firstPage.posts];
  late String? _olderPath = widget.firstPage.olderPath;
  bool _loadingOlder = false;
  Object? _olderError;

  Future<void> _loadOlder() async {
    final path = _olderPath;
    if (_loadingOlder || path == null) return;
    setState(() {
      _loadingOlder = true;
      _olderError = null;
    });
    try {
      final page = await widget.client.boardPage(widget.firstPage.board, path: path);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.posts);
        _olderPath = page.olderPath;
        _loadingOlder = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _olderError = e;
        _loadingOlder = false;
      });
    }
  }

  void _open(PostSummary post) {
    final path = post.path;
    if (path == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ArticlePage(
        client: widget.client,
        path: path,
        title: post.title,
        openUrl: widget.openUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final olderError = _olderError;
    return ListView(
      children: [
        for (final post in widget.firstPage.pinned)
          _PostTile(post: post, pinned: true, onTap: () => _open(post)),
        for (final post in _posts)
          _PostTile(post: post, onTap: () => _open(post)),
        if (olderError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(webErrorMessage(olderError), textAlign: TextAlign.center),
          ),
        if (_loadingOlder)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_olderPath != null)
          TextButton(onPressed: _loadOlder, child: const Text('載入更早的文章')),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onTap, this.pinned = false});

  final PostSummary post;
  final VoidCallback onTap;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      enabled: post.isAvailable,
      leading: SizedBox(
        width: 32,
        child: Text(post.pushCount, textAlign: TextAlign.center),
      ),
      title: Text(post.title),
      subtitle: Text('${post.author}　${post.date}'),
      trailing: pinned ? const Text('置底') : null,
      onTap: post.isAvailable ? onTap : null,
    );
  }
}
```

- [ ] **Step 6: 實作看板清單頁**

`lib/ui/web/board_list_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/favorites/favorites.dart';
import '../../core/web/models.dart';
import '../../core/web/ptt_web_client.dart';
import '../../core/web/ptt_web_parser.dart';
import 'load_view.dart';
import 'post_list_page.dart';

/// Entry point of read-only browsing: go to a board by name, pick a recorded
/// favourite, or pick a hot board.
class BoardListPage extends StatefulWidget {
  const BoardListPage({
    super.key,
    required this.client,
    this.favoritesStore,
    this.openUrl,
  });

  final PttWebClient client;

  /// Source of the favourites recorded while logged in, if any.
  final FavoritesStore? favoritesStore;
  final Future<bool> Function(String url)? openUrl;

  @override
  State<BoardListPage> createState() => _BoardListPageState();
}

class _BoardListPageState extends State<BoardListPage> {
  /// Tallest the favourites area may grow before it scrolls.
  static const double _maxFavoritesHeight = 132;

  final _boardName = TextEditingController();
  FavoritesSnapshot? _favorites;
  bool _nameInvalid = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _boardName.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    FavoritesSnapshot? loaded;
    try {
      loaded = await widget.favoritesStore?.load();
    } catch (_) {
      // Browsing works without favourites.
    }
    if (mounted && loaded != null) setState(() => _favorites = loaded);
  }

  void _open(String board) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostListPage(
        client: widget.client,
        board: board,
        openUrl: widget.openUrl,
      ),
    ));
  }

  void _goToTypedBoard() {
    final name = _boardName.text.trim();
    final valid = isValidBoardName(name);
    setState(() => _nameInvalid = !valid);
    if (valid) _open(name);
  }

  @override
  Widget build(BuildContext context) {
    final favorites = _favorites;
    final names = favorites?.names ?? const <String>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('瀏覽看板')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _boardName,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _goToTypedBoard(),
                    decoration: InputDecoration(
                      labelText: '前往看板',
                      isDense: true,
                      errorText: _nameInvalid
                          ? '看板名稱只能是 1 到 12 個英文字母、數字、底線或連字號'
                          : null,
                      errorMaxLines: 2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '前往',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _goToTypedBoard,
                ),
              ],
            ),
          ),
          if (favorites != null && names.isNotEmpty) ...[
            _SectionTitle('我的最愛（${favorites.userId}）'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxFavoritesHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final name in names)
                      ActionChip(label: Text(name), onPressed: () => _open(name)),
                  ],
                ),
              ),
            ),
          ],
          const _SectionTitle('熱門看板'),
          Expanded(
            child: LoadView<List<BoardSummary>>(
              load: (refresh) => widget.client.hotBoards(refresh: refresh),
              builder: (context, boards, refresh) => RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  children: [
                    for (final board in boards)
                      ListTile(
                        dense: true,
                        title: Text(board.name),
                        subtitle: Text(
                          '${board.category}　${board.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: board.userCount == null
                            ? null
                            : Text('${board.userCount}', style: theme.textTheme.bodySmall),
                        onTap: () => _open(board.name),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
```

- [ ] **Step 7: 執行測試確認通過**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui/web/browse_pages_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: Commit**

```bash
/c/dev/flutter/bin/flutter.bat analyze
/c/dev/flutter/bin/flutter.bat test
git add lib/ui/web test/ui/web
git commit -m "feat: add board list, post list, and article pages"
```

---

### Task 5: 入口、最愛的啟用與清除、說明文件

**Files:**
- Modify: `lib/ui/terminal_page.dart`
- Modify: `lib/ui/login_page.dart`
- Modify: `lib/main.dart`（整個取代）
- Modify: `docs/ios-build.md`
- Modify: `README.md`
- Modify: `test/ui/login_page_test.dart`、`test/ui/terminal_page_test.dart`、`test/project_metadata_test.dart`

**Interfaces:**
- Consumes: `BoardListPage`（Task 4）；`PttWebClient`、`HttpPageFetcher`（Task 2）；`FavoritesStore`、`PrefsFavoritesStore`（Task 3）；`SessionController(favoritesStore:)`（Task 3）
- Produces:
  - `TerminalPage` 建構子新增具名參數 `VoidCallback? onBrowseBoards`。非 null 時，在斷線畫面與離線狀態列顯示「瀏覽看板」。
  - `LoginPage` 建構子新增具名參數 `FavoritesStore? favoritesStore` 與 `PttWebClient? webClient`。`webClient` 非 null 時顯示「不登入，直接瀏覽」。

行為：

- 登入頁按「不登入，直接瀏覽」：開啟看板清單，不建立終端機連線。
- 勾選「記住帳號密碼」並登入：把 `favoritesStore` 交給連線控制，登入期間記錄最愛。
- 未勾選而登入：清除已記錄的最愛，且不記錄。
- 「不自動登入，直接連線」：不記錄，也不清除。
- 終端機斷線或離線時按「瀏覽看板」：在終端機頁之上開啟看板清單，返回後仍在終端機頁。

- [ ] **Step 1: 寫失敗的測試**

在 `test/ui/login_page_test.dart` 做下列修改。

import 區加入：

```dart
import 'package:myptt/core/favorites/favorites.dart';
import 'package:myptt/core/web/ptt_web_client.dart';
import 'package:myptt/ui/web/board_list_page.dart';

import '../support/fake_favorites_store.dart';
import '../support/fake_page_fetcher.dart';
import '../support/web_fixtures.dart';
```

把 `late List<FakeConnection> connections;` 之後到 `pumpLogin` 結束的部分換成：

```dart
  late FakeFavoritesStore favorites;
  late FakePageFetcher fetcher;

  Future<void> pumpLogin(
    WidgetTester tester, {
    Credentials? saved,
    bool withWeb = true,
  }) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store = FakeCredentialStore(saved);
    favorites = FakeFavoritesStore();
    fetcher = FakePageFetcher()..pages['/bbs/hotboards.html'] = hotBoardsHtml;
    connections = [];
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        codec: codec,
        store: store,
        favoritesStore: favorites,
        webClient: withWeb ? PttWebClient(fetcher, minInterval: Duration.zero) : null,
        connectionFactory: () {
          final c = FakeConnection();
          connections.add(c);
          return c;
        },
      ),
    ));
    await tester.pump();
  }
```

在 `the password never appears in visible text` 測試之前加入：

```dart
  const favouritesScreen = '\x1b[2J\x1b[H【我的最愛】                      批踢踢實業坊\r\n'
      '   編號   看  板       類別   轉信  中   文   敘   述\r\n'
      '     1   Stock         學術 ◎股票';

  testWidgets('browsing without logging in opens the board list and no connection',
      (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('不登入，直接瀏覽'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardListPage), findsOneWidget);
    expect(find.text('Gossiping'), findsOneWidget);
    expect(connections, isEmpty);
    await disposeAll(tester);
  });

  testWidgets('the browse entry is hidden when no web client is given',
      (tester) async {
    await pumpLogin(tester, withWeb: false);
    expect(find.text('不登入，直接瀏覽'), findsNothing);
    await disposeAll(tester);
  });

  testWidgets('favourites are recorded only when remember is checked',
      (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saved?.userId, 'alice');
    expect(favorites.saved?.names, ['Stock']);
    expect(favorites.clears, 0);
    await disposeAll(tester);
  });

  testWidgets('logging in without remember clears recorded favourites',
      (tester) async {
    await pumpLogin(tester);
    favorites.saved = const FavoritesSnapshot(userId: 'alice', boards: {1: 'Baseball'});
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(favorites.saved, isNull);
    expect(favorites.clears, 1);

    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saved, isNull);
    await disposeAll(tester);
  });

  testWidgets('connecting without auto-login neither records nor clears favourites',
      (tester) async {
    await pumpLogin(tester);
    favorites.saved = const FavoritesSnapshot(userId: 'alice', boards: {1: 'Baseball'});
    await tester.tap(find.text('不自動登入，直接連線'));
    await tester.pumpAndSettle();
    show(favouritesScreen);
    await tester.pump();
    expect(favorites.saved?.names, ['Baseball']);
    expect(favorites.clears, 0);
    expect(favorites.saves, 0);
    await disposeAll(tester);
  });

  testWidgets('a disconnected terminal can open the board list and come back',
      (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('不自動登入，直接連線'));
    await tester.pumpAndSettle();
    expect(find.text('瀏覽看板'), findsNothing);

    connections.single.drop();
    await tester.pump();
    await tester.tap(find.text('瀏覽看板'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardListPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(BoardListPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalPage), findsOneWidget);
    expect(find.text('已斷線'), findsOneWidget);
    await disposeAll(tester);
  });
```

在 `test/ui/terminal_page_test.dart` 的 `leaving the page closes the connection` 測試之前加入：

```dart
  testWidgets('the browse action appears offline only when a handler is given',
      (tester) async {
    await pumpPage(tester);
    conn.drop();
    await tester.pump();
    expect(find.text('瀏覽看板'), findsNothing);
    await disposePage(tester);

    var browsed = 0;
    conn = FakeConnection();
    await tester.pumpWidget(MaterialApp(
      home: TerminalPage(
        controller: SessionController(TerminalSession(conn, codec)),
        onBrowseBoards: () => browsed++,
      ),
    ));
    await tester.pump();
    expect(find.text('瀏覽看板'), findsNothing);
    conn.drop();
    await tester.pump();
    await tester.tap(find.text('瀏覽看板'));
    expect(browsed, 1);

    await tester.tap(find.text('繼續瀏覽'));
    await tester.pump();
    await tester.tap(find.text('瀏覽看板'));
    expect(browsed, 2);
    await disposePage(tester);
  });
```

在 `test/project_metadata_test.dart` 的關鍵字清單 `'Homebrew', 'Accounts', '引號', '自動登入', 'ios/',` 這一行之後加入一行：

```dart
      '不登入，直接瀏覽', '我的最愛', 'lib/core/favorites/favorites.dart',
```

- [ ] **Step 2: 執行測試確認失敗**

```bash
/c/dev/flutter/bin/flutter.bat test test/ui/login_page_test.dart test/ui/terminal_page_test.dart test/project_metadata_test.dart
```

Expected: FAIL。`LoginPage` 沒有 `favoritesStore`、`webClient` 參數；`TerminalPage` 沒有 `onBrowseBoards` 參數；建置說明缺少新的關鍵字。

- [ ] **Step 3: 修改終端機頁**

在 `lib/ui/terminal_page.dart` 做下列修改。

建構子與欄位：把

```dart
  const TerminalPage({super.key, required this.controller, this.openUrl});
```

換成

```dart
  const TerminalPage({
    super.key,
    required this.controller,
    this.openUrl,
    this.onBrowseBoards,
  });
```

並在 `openUrl` 欄位之後加入：

```dart

  /// Opens read-only board browsing. Offered once the connection is down;
  /// null hides the action.
  final VoidCallback? onBrowseBoards;
```

`build` 內的離線狀態列加上 `onBrowse: widget.onBrowseBoards,`，斷線畫面加上 `onBrowseBoards: widget.onBrowseBoards,`。

`_Banner` 新增欄位 `final VoidCallback? onBrowse;`（建構子同步加入 `this.onBrowse`），並在「返回登入頁」按鈕之前加入：

```dart
          if (onBrowse != null)
            TextButton(onPressed: onBrowse, child: const Text('瀏覽看板')),
```

`_DisconnectedOverlay` 新增欄位 `final VoidCallback? onBrowseBoards;`（建構子同步加入 `this.onBrowseBoards`），並在「返回登入頁」按鈕之前加入：

```dart
              if (onBrowseBoards != null)
                TextButton(onPressed: onBrowseBoards, child: const Text('瀏覽看板')),
```

- [ ] **Step 4: 修改登入頁**

在 `lib/ui/login_page.dart` 做下列修改。

import 區加入：

```dart
import '../core/favorites/favorites.dart';
import '../core/web/ptt_web_client.dart';
import 'web/board_list_page.dart';
```

建構子加入 `this.favoritesStore,` 與 `this.webClient,`，並在 `store` 欄位之後加入：

```dart

  /// Where favourites are recorded while logged in with "remember" on.
  final FavoritesStore? favoritesStore;

  /// Enables read-only browsing without logging in.
  final PttWebClient? webClient;
```

`_login` 中儲存帳密的區塊換成：

```dart
    final credentials = Credentials(userId, password);
    try {
      if (_remember) {
        await widget.store.save(credentials);
      } else {
        await widget.store.clear();
        // Favourites are only kept alongside a remembered account.
        await widget.favoritesStore?.clear();
      }
    } catch (_) {
      // Failing to remember must not stop the user from logging in.
    }
    if (!mounted) return;
    _openTerminal(credentials, recordFavorites: _remember);
```

`_openTerminal` 換成下列兩個方法：

```dart
  void _openTerminal(Credentials? credentials, {bool recordFavorites = false}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TerminalPage(
        controller: SessionController(
          TerminalSession(widget.connectionFactory(), widget.codec),
          credentials: credentials,
          favoritesStore: recordFavorites ? widget.favoritesStore : null,
        ),
        openUrl: widget.openUrl,
        onBrowseBoards: widget.webClient == null ? null : _openBoards,
      ),
    ));
  }

  void _openBoards() {
    final client = widget.webClient;
    if (client == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BoardListPage(
        client: client,
        favoritesStore: widget.favoritesStore,
        openUrl: widget.openUrl,
      ),
    ));
  }
```

在「不自動登入，直接連線」按鈕之後加入：

```dart
                  if (widget.webClient != null)
                    TextButton(
                      onPressed: _openBoards,
                      child: const Text('不登入，直接瀏覽'),
                    ),
```

- [ ] **Step 5: 接上啟動程式**

`lib/main.dart`（整個取代）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/encoding/big5_codec.dart';
import 'core/web/http_page_fetcher.dart';
import 'core/web/ptt_web_client.dart';
import 'platform/link_opener.dart';
import 'platform/prefs_favorites_store.dart';
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
      favoritesStore: const PrefsFavoritesStore(),
      webClient: PttWebClient(HttpPageFetcher()),
      openUrl: openExternalUrl,
    ),
  ));
}
```

- [ ] **Step 6: 更新說明文件**

在 `docs/ios-build.md` 的「### 字體與顯示」標題之前加入：

```markdown
### 網頁瀏覽與我的最愛

檔案：`lib/ui/web/`、`lib/core/web/http_page_fetcher.dart`、`lib/core/favorites/favorites.dart`

- [ ] 在登入頁按「不登入，直接瀏覽」：出現熱門看板，點入後看得到文章列表與文章內容。
- [ ] 文章內的網址可以點開；右上角的按鈕能以 Safari 開啟同一篇文章。
- [ ] 下拉可重新整理；「載入更早的文章」會把更舊的文章接在下面。
- [ ] 開啟飛航模式後重新整理：顯示「無法連線，請檢查網路」，關閉飛航模式後按「重試」可恢復。
- [ ] 勾選「記住帳號密碼」登入，進入「我的最愛」畫面並翻完每一頁，然後登出。回到登入頁按「不登入，直接瀏覽」：最上方出現「我的最愛」與剛才的看板。若沒有出現，代表畫面格式與假設不同，改 `lib/core/favorites/favorites.dart` 開頭的常數與規則。
- [ ] 取消勾選「記住帳號密碼」後登入一次：再進入瀏覽時「我的最愛」已消失。

```

在 `README.md` 的「- 帳號密碼存放在系統鑰匙圈。」之後加入一行：

```markdown
- 不登入也能以清單與閱讀頁瀏覽公開看板，並可顯示登入時記下的「我的最愛」。
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

啟動程式並擷取它自己的視窗，確認登入頁多了「不登入，直接瀏覽」。不要輸入任何真實帳密。

- [ ] **Step 9: Commit 並推送**

```bash
git add -A lib test docs/ios-build.md README.md
git commit -m "feat: add browse-without-login entry and favourites wiring"
git push -u origin feat/web-browsing
```

---

## 本計畫完成後的狀態

- 登入頁可選擇不登入直接瀏覽公開看板：前往指定看板、熱門看板、文章列表、文章閱讀（含顏色、連結、推文）。
- 勾選記住帳密並登入時，進入「我的最愛」畫面會被動記下看板；未登入瀏覽時顯示在最上方。
- 終端機斷線或離線時可切到看板瀏覽。
- 「我的最愛」畫面的辨識規則依假設撰寫，尚未以真實畫面驗證；規則集中在 `lib/core/favorites/favorites.dart`。
