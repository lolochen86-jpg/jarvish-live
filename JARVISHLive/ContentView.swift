import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable { case network, discovery, logs }

struct ContentView: View {
    let diagnostics: NetworkDiagnostics
    @State private var selectedTab: AppTab = .network

    var body: some View {
        TabView(selection: $selectedTab) {
            NetworkView(diagnostics: diagnostics)
                .tabItem { Label("連線診斷", systemImage: "wifi") }.tag(AppTab.network)
            DiscoveryView(diagnostics: diagnostics)
                .tabItem { Label("服務探索", systemImage: "dot.radiowaves.left.and.right") }.tag(AppTab.discovery)
            LogView(diagnostics: diagnostics)
                .tabItem { Label("錯誤日誌", systemImage: "list.bullet.rectangle") }.tag(AppTab.logs)
        }
    }
}

private struct NetworkView: View {
    let diagnostics: NetworkDiagnostics
    @State private var wifiName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("先確認連線，再探索服務", systemImage: "sensor.tag.radiowaves.forward")
                        .font(.headline)
                    Text("這是獨立診斷工具，非 JARVISH 官方 App。尚未驗證安全帽 IP、串流協定或相機相容性。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("diagnosticBoundary")
                }
                Section("Wi-Fi 狀態") {
                    Text(diagnostics.wifiStatus).accessibilityIdentifier("wifiStatus")
                    TextField("手動註記 Wi-Fi 名稱（選填）", text: $wifiName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("wifiNote")
                    Text("名稱由你手動填寫，未經系統驗證，也不會自動加入 Wi-Fi。請先在 iPhone 設定中連上安全帽網路。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重新讀取 IP", systemImage: "arrow.clockwise") { diagnostics.refreshInterfaces() }
                        .accessibilityIdentifier("refreshInterfaces")
                }
                Section("這台 iPhone 的網路位址") {
                    if diagnostics.interfaces.isEmpty {
                        Text("尚無可顯示的位址；請確認 Wi-Fi 已連線，再重新讀取。")
                    }
                    ForEach(diagnostics.interfaces) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.name) · \(item.family)").font(.caption).foregroundStyle(.secondary)
                            Text(item.address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Text("遮罩：\(item.netmask)").font(.caption)
                            if let subnet = try? IPv4Subnet(address: item.address, mask: item.netmask) {
                                Text("子網路：\(subnet.networkAddress)/\(subnet.prefixLength)").font(.caption)
                            }
                        }.padding(.vertical, 3)
                    }
                    Text("顯示所有啟用介面；可能包含 Wi-Fi、行動網路或 VPN。這些是手機位址，不是安全帽位址。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("如何解讀") {
                    Text("沒有 router 或網際網路，不代表同一子網路的設備無法互通。")
                    Text("Safari 沒收到 HTTP 回應，不能確定設備 IP、連接埠或串流協定。下一步請執行服務探索。")
                    Text("本版不掃描整個網段、不猜測串流網址，也尚未提供即時影像。")
                }
            }.navigationTitle("JARVISH LIVE")
        }
    }
}

private struct DiscoveryView: View {
    let diagnostics: NetworkDiagnostics

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("探索安全帽可能廣播的 Bonjour 服務").font(.headline)
                    Text("候選類型：HTTP、HTTPS、RTSP。這不是已確認的安全帽協定；未廣播這些類型的設備不會出現在結果中。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if diagnostics.isBrowsing {
                        ProgressView("探索中，最多 15 秒")
                        Button("停止探索", role: .cancel) { diagnostics.stopDiscovery() }
                            .accessibilityIdentifier("stopDiscovery")
                    } else {
                        Button("開始探索", systemImage: "magnifyingglass") { diagnostics.startDiscovery() }
                            .accessibilityIdentifier("startDiscovery")
                    }
                    Text(diagnostics.discoveryStatus).accessibilityIdentifier("discoveryStatus")
                }
                Section("探索結果") {
                    if diagnostics.services.isEmpty {
                        Text("尚無結果。未發現服務不能證明設備不存在。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(diagnostics.services) { service in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(service.name).font(.headline)
                            Text(service.type).font(.caption.monospaced())
                            Text(service.status).font(.footnote)
                            if !service.host.isEmpty { Text("主機：\(service.host)").textSelection(.enabled) }
                            if service.port > 0 { Text("連接埠：\(service.port)") }
                            ForEach(service.addresses, id: \.self) { address in
                                Text(address).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("區域網路權限") {
                    Text("首次探索時請允許區域網路存取。若權限提示期間已逾時，允許後再按一次開始探索。若拒絕，請至 iPhone 設定 → 隱私權與安全性 → 區域網路重新開啟。")
                    Text("探索只在前景進行。錯誤與解析結果會保留在日誌；沒有結果的原因可能是權限、設備未廣播服務或網路隔離，不能只憑逾時判定。")
                }
            }.navigationTitle("服務探索")
        }
    }
}

private struct LogView: View {
    let diagnostics: NetworkDiagnostics
    @State private var exportDocument = LogDocument(text: "{}")
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("保留本次開啟期間最新 300 筆；關閉 App 後不保證保留。日誌含本機 IP、服務名稱及錯誤，分享前請先檢查內容。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("匯出 JSON 日誌", systemImage: "square.and.arrow.up") {
                        do {
                            exportDocument = LogDocument(text: try diagnostics.log.exportJSON())
                            exporting = true
                        } catch { report(error) }
                    }.accessibilityIdentifier("exportLog")
                    Button("清除日誌", role: .destructive) { diagnostics.clearLog() }
                        .accessibilityIdentifier("clearLog")
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                }
                Section("\(diagnostics.log.entries.count) 筆紀錄") {
                    if diagnostics.log.entries.isEmpty { Text("目前沒有日誌。").accessibilityIdentifier("emptyLog") }
                    ForEach(diagnostics.log.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.level.rawValue.uppercased()).font(.caption.bold())
                                    .foregroundStyle(entry.level == .error ? Color.red : Color.secondary)
                                Text(entry.category).font(.caption)
                                Spacer()
                                Text(entry.timestamp, style: .time).font(.caption)
                            }
                            Text(entry.message).font(.footnote).textSelection(.enabled)
                        }.padding(.vertical, 3)
                    }
                }
            }.navigationTitle("錯誤日誌")
                .fileExporter(isPresented: $exporting, document: exportDocument,
                              contentType: .json, defaultFilename: "JARVISH-LIVE-diagnostics") { result in
                    switch result {
                    case .success: exportError = nil
                    case .failure(let error): report(error)
                    }
                }
        }
    }

    private func report(_ error: Error) {
        exportError = "匯出未完成：\(error.localizedDescription)"
        diagnostics.recordExportError(error)
    }
}

struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
