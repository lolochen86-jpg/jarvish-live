# JARVISH LIVE — native iPhone diagnostics

繁體中文原生 SwiftUI App，iOS 17 起。**獨立診斷工具，非 JARVISH 官方產品；尚未驗證安全帽相容性或即時影像。**

這是 2026-11-08 新建立的可檢查專案，不是先前對話所稱 `JARVISH-LIVE-v0.1.zip` 的已驗證延續版。該 ZIP 未能取得，且當時沒有可存取的 JARVISH 儲存庫。沒有複製其他舊專案或上傳私人附件／設備紀錄。

## 本版功能

- 分別顯示 Wi-Fi 路徑與本機 IPv4／IPv6、遮罩和 IPv4 子網路；不從手機 IP 猜測 router 或安全帽位址。
- 手動 Wi-Fi 名稱註記；不要求位置、Access Wi-Fi Information 或 Hotspot Configuration entitlement。
- 主動按下後，最多 15 秒探索 `_http._tcp`、`_https._tcp`、`_rtsp._tcp` 三種 **候選** Bonjour 類型，解析 host／port／IP，允許取消，退到背景即停止。
- 錯誤、時間、探索結果保留最新 300 筆於記憶體，使用者可明確匯出 JSON。常見敏感欄位會遮蔽；日誌仍可能包含 IP／設備名稱，分享前請檢查。
- XCTest 檢查 IP 邊界、遮罩、日誌保留／遮蔽、sockaddr 解碼及權限宣告；UI test 實際啟動 app、切換三個分頁和清除日誌。

**沒有 router 不代表本機網路不通；HTTP 無回應或沒有 Bonjour 結果，也不能確定安全帽 IP、協定或是否離線。** 本版沒有串流播放器、整網段掃描、猜測位址、帳密或雲端上傳。

## 開啟與修改

直接以 Xcode 開啟 `JARVISHLive.xcodeproj`，選 `JARVISHLive` scheme。原始碼沒有第三方套件。

| 檔案 | 用途 |
|---|---|
| `JARVISHLive/ContentView.swift` | 三個繁體中文分頁、日誌匯出 |
| `JARVISHLive/JARVISHLiveApp.swift` | App 入口、前背景生命週期 |
| `JARVISHLive/NetworkDiagnostics.swift` | Wi-Fi 監測、Bonjour、取消與錯誤 |
| `JARVISHLive/NetworkInterfaces.swift` | 實際本機 IP／遮罩、sockaddr 解析 |
| `JARVISHLive/DiagnosticCore.swift` | IPv4 子網路、日誌與遮蔽 |
| `JARVISHLive/Info.plist` | 區域網路用途與 Bonjour 類型宣告 |
| `JARVISHLiveTests/`、`JARVISHLiveUITests/` | 可執行測試 |
| `.github/workflows/ios.yml` | macOS／iPhone simulator 建置與測試 |

新增／刪除 Swift 檔案後，以 `python3 scripts/generate_project.py` 重新產生專案（確定性產出、Python 標準函式庫，不需 XcodeGen）。`python3 scripts/validate_project.py` 只做靜態檢查，不能取代 Xcode。

## GitHub Actions

公開 repository 使用標準 `macos-15` runner，選定 Xcode 16.4；輸出實際 OS／Xcode／SDK，從已安裝且符合 SDK 的 iPhone simulators 選擇，不假定某台機型一定存在。

工作流程依序：原始碼檢查 → iPhone 架構 unsigned build → simulator unit／UI test → 啟動與截圖 → 保存 log、`.xcresult`、測試摘要。每次上限 25 分鐘；同分支新 run 取消舊 run；artifact 保留 3 天。UI test 不觸發真實安全帽探索。

Actions 頁面可手動執行 **iOS build and tests**。請看實際 run 狀態與 log，不能只憑這份 README 宣稱通過。產物 `JARVISHLive-UNSIGNED-NOT-INSTALLABLE.app.zip` 只是編譯證據，**不是可安裝 IPA**。

私人 fork 預設略過 job，需先確認帳號額度／預算，再設 repository variable `ALLOW_PRIVATE_ACTIONS=true`。沒有設定付款方式、預算或提升 runner 等級。

## iPhone 安裝與設備驗收

參閱 [免費與簽署條件](docs/SIGNING.zh-TW.md) 及 [實機驗收](docs/DEVICE_TESTS.zh-TW.md)。CI 通過不代表已在 iPhone 安裝、區域網路權限已驗證、安全帽已發現或影像可播放。

## 官方依據

- [Apple：區域網路隱私 TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple：Wi-Fi 名稱讀取條件](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent%28completionhandler%3A%29)
- [Apple：免費開發者帳號與 Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [GitHub：Actions 計費](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

最後更新：2026-11-08（Asia/Taipei）。
