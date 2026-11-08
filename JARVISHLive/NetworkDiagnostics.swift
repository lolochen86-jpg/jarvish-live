import Foundation
import Observation
import Network

struct DiscoveredService: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    var host: String
    var port: Int
    var addresses: [String]
    var status: String
}

@Observable
@MainActor
final class NetworkDiagnostics {
    private(set) var wifiStatus = "尚未檢查 Wi-Fi 路徑"
    private(set) var interfaces: [InterfaceAddress] = []
    private(set) var services: [DiscoveredService] = []
    private(set) var discoveryStatus = "尚未執行 Bonjour 探索"
    private(set) var isBrowsing = false
    private(set) var log = DiagnosticLog()

    /// Candidate DNS-SD types only. A result does not identify a JARVISH device
    /// or establish the actual helmet streaming protocol.
    static let candidateServiceTypes = ["_http._tcp.", "_https._tcp.", "_rtsp._tcp."]
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var monitorID: UUID?
    private let pathQueue = DispatchQueue(label: "live.jarvish.wifi-path")
    @ObservationIgnored private var discoveryID: UUID?
    @ObservationIgnored private var discoveryDelegate: BonjourDelegate?
    @ObservationIgnored private var browsers: [ObjectIdentifier: NetServiceBrowser] = [:]
    @ObservationIgnored private var browserTypes: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var resolving: [String: NetService] = [:]
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    func clearLog() {
        log.clear()
    }

    func recordExportError(_ error: Error) {
        log.append(level: .error, category: "Export", message: "日誌匯出失敗：\(error.localizedDescription)")
    }

    func startMonitoring() {
        guard pathMonitor == nil else {
            refreshInterfaces()
            return
        }
        refreshInterfaces()
        let id = UUID()
        monitorID = id
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied:
                status = "Wi-Fi 路徑可用；尚未驗證網際網路或安全帽連線。"
            case .unsatisfied:
                status = "目前沒有可用的 Wi-Fi 路徑；請一併查看本機 IP。"
            case .requiresConnection:
                status = "Wi-Fi 路徑需要建立連線；請查看 iPhone 的 Wi-Fi 設定。"
            @unknown default:
                status = "Wi-Fi 路徑狀態未知。"
            }
            Task { @MainActor [weak self] in
                guard let self, self.monitorID == id else { return }
                if self.wifiStatus != status {
                    self.wifiStatus = status
                    self.log.append(level: .info, category: "Wi-Fi", message: status)
                }
                self.refreshInterfaces()
            }
        }
        pathMonitor = monitor
        monitor.start(queue: pathQueue)
    }

    func refreshInterfaces() {
        do {
            let values = try NetworkInterfaces.current()
            let changed = values != interfaces
            interfaces = values
            if values.isEmpty {
                log.append(level: .warning, category: "IP", message: "未找到已啟用且非 loopback 的 IPv4／IPv6 位址；這不表示安全帽不存在。")
            } else if changed {
                let summary = values.map { "\($0.name): \($0.address)，遮罩 \($0.netmask)" }.joined(separator: "；")
                log.append(level: .info, category: "IP", message: summary)
            }
        } catch {
            interfaces = []
            log.append(level: .error, category: "IP", message: error.localizedDescription)
        }
    }

    func startDiscovery() {
        if isBrowsing { finishDiscovery(reason: "已重新開始探索", timedOut: false) }
        refreshInterfaces()
        services = []
        let id = UUID()
        discoveryID = id
        isBrowsing = true
        discoveryStatus = "探索中（最多 15 秒）；首次使用請允許「區域網路」。"
        log.append(level: .info, category: "Bonjour", message: "開始探索候選服務：\(Self.candidateServiceTypes.joined(separator: ", "))。這些類型不是已確認的安全帽協定。")
        let delegate = BonjourDelegate(owner: self, sessionID: id)
        discoveryDelegate = delegate
        for type in Self.candidateServiceTypes {
            let browser = NetServiceBrowser()
            let browserID = ObjectIdentifier(browser)
            browsers[browserID] = browser
            browserTypes[browserID] = type
            browser.delegate = delegate
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.discoveryID == id else { return }
            self.finishDiscovery(reason: "15 秒探索時間結束", timedOut: true)
        }
    }

    func stopDiscovery() {
        guard isBrowsing else { return }
        finishDiscovery(reason: "使用者已停止探索", timedOut: false)
    }

    /// Call when the scene goes into the background. A fresh monitor is created
    /// on the next startMonitoring() call because cancelled monitors cannot restart.
    func stop() {
        if isBrowsing { finishDiscovery(reason: "App 離開前景，已停止探索", timedOut: false) }
        monitorID = nil
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        wifiStatus = "Wi-Fi 監測已暫停；返回前景時重新檢查。"
    }

    private func finishDiscovery(reason: String, timedOut: Bool) {
        // Invalidate before stop() can deliver any final delegate callbacks.
        discoveryID = nil
        isBrowsing = false
        timeoutTask?.cancel()
        timeoutTask = nil
        for browser in browsers.values {
            browser.delegate = nil
            browser.stop()
        }
        for (key, service) in resolving {
            service.delegate = nil
            service.stop()
            if let index = services.firstIndex(where: { $0.id == key }) {
                services[index].status = "未完成解析（探索已結束）"
            }
            log.append(level: .warning, category: "Bonjour", message: "\(service.name) 的解析尚未完成，已取消；不能判斷服務是否可用。")
        }
        browsers.removeAll()
        browserTypes.removeAll()
        resolving.removeAll()
        discoveryDelegate = nil
        if services.isEmpty {
            discoveryStatus = "\(reason)。未發現候選服務；不能據此判定設備離線或不支援串流。"
            log.append(level: .warning, category: "Bonjour", message: discoveryStatus + " 可能原因包含未廣播這些類型、區域網路權限、網路隔離或設備狀態；本次未確認原因。")
        } else {
            discoveryStatus = "\(reason)。保留 \(services.count) 個探索結果；尚未確認是否屬於安全帽。"
            log.append(level: timedOut ? .info : .warning, category: "Bonjour", message: discoveryStatus)
        }
    }

    fileprivate func found(_ service: NetService, browser: NetServiceBrowser, sessionID: UUID) {
        guard accepts(browser: browser, sessionID: sessionID) else { return }
        let key = Self.key(service)
        let discovered = DiscoveredService(id: key, name: service.name, type: service.type,
                                          host: "", port: 0, addresses: [], status: "解析中（最多 5 秒）")
        if let index = services.firstIndex(where: { $0.id == key }) {
            guard services[index].status == "探索期間服務已離開" else { return }
            services[index] = discovered
        } else {
            services.append(discovered)
        }
        resolving[key] = service
        service.delegate = discoveryDelegate
        service.resolve(withTimeout: 5)
        log.append(level: .info, category: "Bonjour", message: "發現 \(service.name)（\(service.type)）；開始解析，尚未確認設備身分。")
    }

    fileprivate func removed(_ service: NetService, browser: NetServiceBrowser, sessionID: UUID) {
        guard accepts(browser: browser, sessionID: sessionID) else { return }
        let key = Self.key(service)
        if let pending = resolving.removeValue(forKey: key) {
            pending.delegate = nil
            pending.stop()
        }
        if let index = services.firstIndex(where: { $0.id == key }) {
            services[index].status = "探索期間服務已離開"
        }
        log.append(level: .warning, category: "Bonjour", message: "服務已移除：\(service.name)（\(service.type)）。保留先前結果供診斷。")
    }

    fileprivate func searchFailed(_ browser: NetServiceBrowser, error: [String: NSNumber], sessionID: UUID) {
        guard accepts(browser: browser, sessionID: sessionID) else { return }
        let browserID = ObjectIdentifier(browser)
        let type = browserTypes.removeValue(forKey: browserID) ?? "未知類型"
        browsers.removeValue(forKey: browserID)
        browser.delegate = nil
        browser.stop()
        log.append(level: .error, category: "Bonjour", message: "\(type) 探索失敗：\(Self.describe(error))。請檢查區域網路權限及 Wi-Fi；錯誤本身不能證明安全帽離線。")
        if browsers.isEmpty {
            finishDiscovery(reason: "所有候選服務探索均已失敗", timedOut: false)
        }
    }

    fileprivate func resolved(_ service: NetService, sessionID: UUID) {
        let key = Self.key(service)
        guard discoveryID == sessionID, isBrowsing,
              let pending = resolving[key], pending === service,
              let index = services.firstIndex(where: { $0.id == key }) else { return }
        let addresses = Array(Set((service.addresses ?? []).compactMap { NetworkInterfaces.numericAddress(from: $0) })).sorted()
        services[index].host = service.hostName ?? ""
        services[index].port = service.port
        services[index].addresses = addresses
        services[index].status = addresses.isEmpty ? "已解析服務，尚無可解碼 IP" : "已解析；尚未驗證連線或設備身分"
        resolving.removeValue(forKey: key)
        service.delegate = nil
        service.stop()
        log.append(level: .info, category: "Bonjour", message: "\(service.name)：host=\(services[index].host)，port=\(services[index].port)，IP=\(addresses.joined(separator: ", "))。未測試 HTTP、RTSP 或串流。")
    }

    fileprivate func resolveFailed(_ service: NetService, error: [String: NSNumber], sessionID: UUID) {
        let key = Self.key(service)
        guard discoveryID == sessionID, isBrowsing,
              let pending = resolving[key], pending === service else { return }
        resolving.removeValue(forKey: key)
        service.delegate = nil
        service.stop()
        if let index = services.firstIndex(where: { $0.id == key }) {
            services[index].status = "解析失敗：\(Self.describe(error))"
        }
        log.append(level: .error, category: "Bonjour", message: "\(service.name) 解析失敗（最長等待 5 秒）：\(Self.describe(error))。")
    }

    private func accepts(browser: NetServiceBrowser, sessionID: UUID) -> Bool {
        discoveryID == sessionID && isBrowsing && browsers[ObjectIdentifier(browser)] != nil
    }

    private static func key(_ service: NetService) -> String {
        "\(service.domain)|\(service.type)|\(service.name)"
    }

    private static func describe(_ error: [String: NSNumber]) -> String {
        let domain = error[NetService.errorDomain]?.stringValue ?? "未提供"
        let code = error[NetService.errorCode]?.stringValue ?? "未提供"
        return "domain=\(domain)，code=\(code)"
    }
}

/// Foundation delegate callbacks hop onto the main actor before touching any
/// observable state. Every callback carries the original exploration session.
private final class BonjourDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private weak var owner: NetworkDiagnostics?
    private let sessionID: UUID

    init(owner: NetworkDiagnostics, sessionID: UUID) {
        self.owner = owner
        self.sessionID = sessionID
        super.init()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let id = sessionID
        Task { @MainActor [weak owner] in owner?.found(service, browser: browser, sessionID: id) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = sessionID
        Task { @MainActor [weak owner] in owner?.removed(service, browser: browser, sessionID: id) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        let id = sessionID
        Task { @MainActor [weak owner] in owner?.searchFailed(browser, error: errorDict, sessionID: id) }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let id = sessionID
        Task { @MainActor [weak owner] in owner?.resolved(sender, sessionID: id) }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let id = sessionID
        Task { @MainActor [weak owner] in owner?.resolveFailed(sender, error: errorDict, sessionID: id) }
    }
}
