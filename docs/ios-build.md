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
