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
