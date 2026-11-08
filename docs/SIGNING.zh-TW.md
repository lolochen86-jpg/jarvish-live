# 免費建置與合法安裝

核對日期：2026-11-08（Asia/Taipei）。

**本專案 CI 不需 Apple Developer 付費帳號、憑證或 provisioning profile。** 它只編譯 unsigned iPhone app，並在模擬器執行測試。模擬器不能存取遠端使用者的安全帽，也不能替實體 iPhone 驗證區域網路權限。

## 優先免費方案

公開 GitHub repo 的標準 runner 免費；較大 runner 仍可能計費。本 workflow 只使用標準 `macos-15`，不升級／購買任何服務。私人 repo 會使用帳號額度，超過後可能計費，故本專案要求明確的私人執行 opt-in。

實機免費官方路徑：取得可使用的 Mac，在 Xcode 登入你自己的 Apple Account，選 Personal Team、設定唯一 bundle identifier，連接並信任自己的 iPhone，依系統提示開啟 Developer Mode，選該裝置 Run。免費 provisioning 有期限（通常 7 天）與 App／裝置數限制，需要定期重新簽署。不要把 Apple 密碼、私鑰或憑證貼到聊天／儲存庫。

Windows 加 GitHub runner 可以完成編譯與模擬器測試，**不會自動把 app 安裝到遠端 iPhone**。若目前沒有可用的 Mac，免費官方實機安裝這一步仍未解決；不應因 CI 成功宣稱已有可安裝 IPA。

## 沒有 Mac 的另一條免費路徑（尚未實機驗證）

第三方 AltStore Classic／AltServer 官方文件提供 Windows 安裝路徑，可用自己的免費 Apple Account 簽署側載 app。需要相容的 iTunes／iCloud、將 iPhone 接到電腦並信任、本人完成帳號登入，以及在 iOS 16 起啟用 Developer Mode；免費 app 7 天到期，並有同時 3 個側載 app 的限制。

這不等於 unsigned app 可直接安裝。仍需封裝自有 app、完成實際重新簽署及裝置 provisioning，才能驗證安裝。本次僅查證該路徑，未安裝 AltServer、未登入 Apple Account、未簽署或操作 iPhone，也未保證目前裝置與帳號一定成功。帳號驗證應由本人在該工具完成，不需提供給本專案或聊天。

- [AltStore：Windows 安裝條件](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore：免費帳號與重新整理限制](https://faq.altstore.io/altstore-classic/your-altstore)

## 若要 GitHub 產出已簽署版本

需要合法有效的簽署身分（含私鑰）及與 bundle ID、entitlements、目標裝置相符的 provisioning profile；由你掌握並使用 GitHub Secrets，不能 commit `.p12` 或 `.mobileprovision`。本次沒有這些材料，因此沒有建立虛假的簽署／發佈步驟。

TestFlight 需要 Apple Developer Program 及 App Store Connect 流程；官方方案年費 US$99 或當地價格，並非本次免費建置的必要條件。本次沒有購買或註冊付費方案。

官方來源：
- https://developer.apple.com/help/account/basics/about-your-developer-account
- https://developer.apple.com/help/account/membership/program-enrollment/
- https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
