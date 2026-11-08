# 已執行的建置結果

核對時間：2026-11-08（Asia/Taipei）。

- 已測原始碼 commit：`c08b2af95339f6b983ae9b9323f2d716016f2424`。
- [GitHub Actions run 42437204161](https://github.com/lolochen86-jpg/jarvish-live/actions/runs/42437204161)：**success**。
- 執行時間：台灣 10:08:02–10:14:37。
- 實際 runner：macOS 15.8.2、arm64、Xcode 16.4、iOS SDK 18.5。
- iPhone 架構 unsigned build：成功。
- 模擬器：iPhone SE（第 3 代）、iOS 18.5。
- XCTest：**32 通過、0 失敗、0 跳過**（19 個核心、12 個介面／設定、1 個 UI 測試）。
- UI 測試實際啟動 app，讀取診斷畫面、重新讀取 IP、切換服務探索／日誌分頁、清除日誌；模擬器啟動畫面另已保存並檢閱。

後續若只有文件更新，這個測試結果仍明確指向上述原始碼 commit；不把它宣稱為未來任意變更的驗證。

Workflow artifact 保存 `environment.txt`、`device-build.log`、`simulator-tests.log`、`test-summary.json`、`Tests.xcresult`、模擬器截圖及 unsigned app ZIP。GitHub artifact 保留 3 天，執行日誌／摘要仍可由 run 頁面查看；本次交付另保存本機證據。

尚未驗證：實體 iPhone 安裝／簽署、區域網路權限提示、安全帽 Wi-Fi 通訊、真實 Bonjour 廣播、相機 IP／串流協定、即時影像。模擬器顯示的 IP 屬於 runner 環境，並非使用者設備。
