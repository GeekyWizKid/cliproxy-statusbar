import AppKit
import Charts
import Foundation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case zhHans
    case en

    var id: String { rawValue }

    static func fromEnvironment(_ value: String?) -> AppLanguage {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return .auto
        }

        switch value {
        case "zh", "zh-cn", "zh-hans", "cn", "chinese":
            return .zhHans
        case "en", "en-us", "english":
            return .en
        default:
            return .auto
        }
    }
}

struct AppConfig: Codable, Sendable {
    var baseURL: String
    var managementKey: String
    var refreshIntervalSeconds: Double
    var language: AppLanguage

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case managementKey
        case refreshIntervalSeconds
        case language
    }

    init(baseURL: String, managementKey: String, refreshIntervalSeconds: Double, language: AppLanguage = .auto) {
        self.baseURL = baseURL
        self.managementKey = managementKey
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.language = language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://127.0.0.1:8317"
        managementKey = try container.decodeIfPresent(String.self, forKey: .managementKey) ?? ""
        refreshIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? 10
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .auto
    }

    static func defaults() -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        let url = env["CLIPROXY_BASE_URL"] ?? "http://127.0.0.1:8317"
        let key = env["CLIPROXY_MANAGEMENT_KEY"] ?? env["MANAGEMENT_PASSWORD"] ?? ""
        let interval = Double(env["CLIPROXY_REFRESH_SECONDS"] ?? "") ?? 10
        let language = AppLanguage.fromEnvironment(env["CLIPROXY_LANGUAGE"])

        var config = AppConfig(baseURL: url, managementKey: key, refreshIntervalSeconds: interval, language: language)
        config.normalize()
        return config
    }

    mutating func normalize() {
        baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }
        managementKey = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if refreshIntervalSeconds < 3 {
            refreshIntervalSeconds = 3
        }
        if refreshIntervalSeconds > 300 {
            refreshIntervalSeconds = 300
        }
    }
}

final class ConfigStore {
    private let configURL: URL

    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        configURL = baseDir
            .appendingPathComponent("CliproxyStatusBar", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    func load() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            var config = decoded
            config.normalize()
            return config
        }
        return AppConfig.defaults()
    }

    func save(_ config: AppConfig) throws {
        var normalized = config
        normalized.normalize()

        let dirURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: configURL, options: .atomic)
    }
}

struct UsageEnvelope: Decodable, Sendable {
    let usage: UsageSnapshot
    let failedRequests: Int64?
}

enum UsageTimeRange: String, CaseIterable, Identifiable, Sendable {
    case last24Hours
    case last7Days
    case allTime

    var id: String { rawValue }

    func cutoffDate(from now: Date) -> Date? {
        switch self {
        case .last24Hours:
            return now.addingTimeInterval(-24 * 60 * 60)
        case .last7Days:
            return now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .allTime:
            return nil
        }
    }
}

struct UsageSnapshot: Decodable, Sendable {
    let totalRequests: Int64
    let successCount: Int64
    let failureCount: Int64
    let totalTokens: Int64
    let apis: [String: APISnapshot]
    let requestsByDay: [String: Int64]
    let requestsByHour: [String: Int64]
    let tokensByDay: [String: Int64]
    let tokensByHour: [String: Int64]

    private enum CodingKeys: String, CodingKey {
        case totalRequests
        case successCount
        case failureCount
        case totalTokens
        case apis
        case requestsByDay
        case requestsByHour
        case tokensByDay
        case tokensByHour
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decodeIfPresent(Int64.self, forKey: .totalRequests) ?? 0
        successCount = try container.decodeIfPresent(Int64.self, forKey: .successCount) ?? 0
        failureCount = try container.decodeIfPresent(Int64.self, forKey: .failureCount) ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        apis = try container.decodeIfPresent([String: APISnapshot].self, forKey: .apis) ?? [:]
        requestsByDay = try container.decodeIfPresent([String: Int64].self, forKey: .requestsByDay) ?? [:]
        requestsByHour = try container.decodeIfPresent([String: Int64].self, forKey: .requestsByHour) ?? [:]
        tokensByDay = try container.decodeIfPresent([String: Int64].self, forKey: .tokensByDay) ?? [:]
        tokensByHour = try container.decodeIfPresent([String: Int64].self, forKey: .tokensByHour) ?? [:]
    }
}

struct APISnapshot: Decodable, Sendable {
    let totalRequests: Int64
    let totalTokens: Int64
    let models: [String: ModelSnapshot]

    private enum CodingKeys: String, CodingKey {
        case totalRequests
        case totalTokens
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decodeIfPresent(Int64.self, forKey: .totalRequests) ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        models = try container.decodeIfPresent([String: ModelSnapshot].self, forKey: .models) ?? [:]
    }
}

struct ModelSnapshot: Decodable, Sendable {
    let totalRequests: Int64
    let totalTokens: Int64
    let details: [RequestDetailSnapshot]

    private enum CodingKeys: String, CodingKey {
        case totalRequests
        case totalTokens
        case details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decodeIfPresent(Int64.self, forKey: .totalRequests) ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        details = try container.decodeIfPresent([RequestDetailSnapshot].self, forKey: .details) ?? []
    }
}

struct RequestDetailSnapshot: Decodable, Sendable {
    let timestamp: String
    let tokens: TokenStatsSnapshot
    let failed: Bool

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case tokens
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        tokens = try container.decodeIfPresent(TokenStatsSnapshot.self, forKey: .tokens) ?? TokenStatsSnapshot(totalTokens: 0)
        failed = try container.decodeIfPresent(Bool.self, forKey: .failed) ?? false
    }
}

struct TokenStatsSnapshot: Decodable, Sendable {
    let totalTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case totalTokens
    }

    init(totalTokens: Int64) {
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
    }
}

struct RankedUsage: Identifiable, Sendable {
    let name: String
    let requests: Int64
    let tokens: Int64

    var id: String { name }
}

struct UsageSummary: Sendable {
    let totalRequests: Int64
    let successCount: Int64
    let failureCount: Int64
    let totalTokens: Int64

    let topAPIs: [RankedUsage]
    let topModels: [RankedUsage]

    let requestsByHour: [Int64]
    let tokensByHour: [Int64]

    init(snapshot: UsageSnapshot, range: UsageTimeRange = .allTime, now: Date = Date()) {
        let data = UsageSummary.makeSummaryData(from: snapshot, range: range, now: now)
        totalRequests = data.totalRequests
        successCount = data.successCount
        failureCount = data.failureCount
        totalTokens = data.totalTokens
        topAPIs = UsageSummary.makeRankedUsage(from: data.apiStats, limit: 4)
        topModels = UsageSummary.makeRankedUsage(from: data.modelStats, limit: 6)
        requestsByHour = data.requestsByHour
        tokensByHour = data.tokensByHour
    }

    var failureRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(failureCount) / Double(totalRequests)
    }

    var requestPeak: Int64 { requestsByHour.max() ?? 0 }
    var tokenPeak: Int64 { tokensByHour.max() ?? 0 }

    private static func makeHourlySeries(from source: [String: Int64]) -> [Int64] {
        var series = Array(repeating: Int64(0), count: 24)
        for (key, value) in source {
            guard let hour = parseHour(key), hour >= 0, hour < 24 else {
                continue
            }
            series[hour] = value
        }
        return series
    }

    private static func parseHour(_ key: String) -> Int? {
        let pieces = key.split(separator: ":", omittingEmptySubsequences: true)
        guard let first = pieces.first else {
            return nil
        }
        return Int(first)
    }

    private typealias UsageCounter = (requests: Int64, tokens: Int64)

    private struct SummaryData {
        var totalRequests: Int64
        var successCount: Int64
        var failureCount: Int64
        var totalTokens: Int64
        var apiStats: [String: UsageCounter]
        var modelStats: [String: UsageCounter]
        var requestsByHour: [Int64]
        var tokensByHour: [Int64]
    }

    private struct TimestampParser {
        private let withFractionalSeconds: ISO8601DateFormatter
        private let internetDateTime: ISO8601DateFormatter

        init() {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            withFractionalSeconds = fractional

            let internet = ISO8601DateFormatter()
            internet.formatOptions = [.withInternetDateTime]
            internetDateTime = internet
        }

        func parse(_ rawValue: String) -> Date? {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                return nil
            }
            if let parsed = withFractionalSeconds.date(from: value) {
                return parsed
            }
            return internetDateTime.date(from: value)
        }
    }

    private static func makeSummaryData(from snapshot: UsageSnapshot, range: UsageTimeRange, now: Date) -> SummaryData {
        if range == .allTime {
            return makeAllTimeSummaryData(from: snapshot)
        }

        if let scoped = makeScopedSummaryData(from: snapshot, range: range, now: now) {
            return scoped
        }

        return makeAllTimeSummaryData(from: snapshot)
    }

    private static func makeAllTimeSummaryData(from snapshot: UsageSnapshot) -> SummaryData {
        var mergedByModel: [String: UsageCounter] = [:]
        let mergedByAPI: [String: UsageCounter] = snapshot.apis.reduce(into: [:]) { result, entry in
            result[entry.key] = (entry.value.totalRequests, entry.value.totalTokens)
            for (modelName, modelSnapshot) in entry.value.models {
                let current = mergedByModel[modelName] ?? (0, 0)
                mergedByModel[modelName] = (
                    current.requests + modelSnapshot.totalRequests,
                    current.tokens + modelSnapshot.totalTokens
                )
            }
        }

        return SummaryData(
            totalRequests: snapshot.totalRequests,
            successCount: snapshot.successCount,
            failureCount: snapshot.failureCount,
            totalTokens: snapshot.totalTokens,
            apiStats: mergedByAPI,
            modelStats: mergedByModel,
            requestsByHour: makeHourlySeries(from: snapshot.requestsByHour),
            tokensByHour: makeHourlySeries(from: snapshot.tokensByHour)
        )
    }

    private static func makeScopedSummaryData(from snapshot: UsageSnapshot, range: UsageTimeRange, now: Date) -> SummaryData? {
        guard let cutoff = range.cutoffDate(from: now) else {
            return makeAllTimeSummaryData(from: snapshot)
        }

        var totalRequests: Int64 = 0
        var successCount: Int64 = 0
        var failureCount: Int64 = 0
        var totalTokens: Int64 = 0
        var apiStats: [String: UsageCounter] = [:]
        var modelStats: [String: UsageCounter] = [:]
        var requestsByHour = Array(repeating: Int64(0), count: 24)
        var tokensByHour = Array(repeating: Int64(0), count: 24)
        var hasDetails = false

        let calendar = Calendar.autoupdatingCurrent
        let parser = TimestampParser()

        for (apiName, apiSnapshot) in snapshot.apis {
            for (modelName, modelSnapshot) in apiSnapshot.models {
                for detail in modelSnapshot.details {
                    hasDetails = true

                    guard let timestamp = parser.parse(detail.timestamp), timestamp >= cutoff, timestamp <= now else {
                        continue
                    }

                    let tokens = max(detail.tokens.totalTokens, 0)
                    totalRequests += 1
                    totalTokens += tokens

                    if detail.failed {
                        failureCount += 1
                    } else {
                        successCount += 1
                    }

                    let apiCurrent = apiStats[apiName] ?? (0, 0)
                    apiStats[apiName] = (apiCurrent.requests + 1, apiCurrent.tokens + tokens)

                    let modelCurrent = modelStats[modelName] ?? (0, 0)
                    modelStats[modelName] = (modelCurrent.requests + 1, modelCurrent.tokens + tokens)

                    let hour = calendar.component(.hour, from: timestamp)
                    if hour >= 0, hour < 24 {
                        requestsByHour[hour] += 1
                        tokensByHour[hour] += tokens
                    }
                }
            }
        }

        guard hasDetails else {
            return nil
        }

        return SummaryData(
            totalRequests: totalRequests,
            successCount: successCount,
            failureCount: failureCount,
            totalTokens: totalTokens,
            apiStats: apiStats,
            modelStats: modelStats,
            requestsByHour: requestsByHour,
            tokensByHour: tokensByHour
        )
    }

    private static func makeRankedUsage(from source: [String: UsageCounter], limit: Int) -> [RankedUsage] {
        source
            .map { name, values in
                RankedUsage(name: name, requests: values.requests, tokens: values.tokens)
            }
            .sorted {
                if $0.requests == $1.requests {
                    return $0.tokens > $1.tokens
                }
                return $0.requests > $1.requests
            }
            .prefix(limit)
            .map { $0 }
    }
}

enum UsageClientError: Error, Sendable {
    case invalidURL(String)
    case httpError(status: Int, body: String)
    case emptyData
    case decodeFailed(String)
}

extension UsageClientError {
    func message(_ t: (_ zh: String, _ en: String) -> String) -> String {
        switch self {
        case .invalidURL(let value):
            return "\(t("无效地址", "Invalid URL")): \(value)"
        case .httpError(let status, let body):
            if body.isEmpty {
                return "\(t("管理接口返回 HTTP", "Management API returned HTTP")) \(status)"
            }
            return "\(t("管理接口返回 HTTP", "Management API returned HTTP")) \(status): \(body)"
        case .emptyData:
            return t("管理接口返回空数据", "Management API returned empty data")
        case .decodeFailed(let reason):
            return "\(t("解析数据失败", "Failed to decode response")): \(reason)"
        }
    }
}

actor UsageClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func fetchUsage(config: AppConfig) async throws -> UsageSnapshot {
        guard let url = usageURL(baseURL: config.baseURL) else {
            throw UsageClientError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !config.managementKey.isEmpty {
            request.setValue("Bearer \(config.managementKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.decodeFailed("Invalid response format")
        }

        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw UsageClientError.httpError(status: http.statusCode, body: body)
        }

        guard !data.isEmpty else {
            throw UsageClientError.emptyData
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let envelope = try decoder.decode(UsageEnvelope.self, from: data)
            return envelope.usage
        } catch {
            throw UsageClientError.decodeFailed(error.localizedDescription)
        }
    }

    private func usageURL(baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: "\(normalized)/v0/management/usage")
    }
}

@MainActor
final class DashboardModel: NSObject, ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var allTimeSummary: UsageSummary?
    @Published private(set) var summary: UsageSummary?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published var selectedTimeRange: UsageTimeRange = .allTime {
        didSet {
            rebuildSelectedSummary()
        }
    }

    var onStateChange: (() -> Void)?

    private let configStore = ConfigStore()
    private let usageClient = UsageClient()
    private var timer: Timer?
    private var inFlight = false
    private var latestSnapshot: UsageSnapshot?

    override init() {
        config = configStore.load()
        super.init()
    }

    func start() {
        scheduleTimer()
        refreshNow(force: true)
    }

    @objc private func handleTimer() {
        refreshNow()
    }

    func refreshNow(force: Bool = false) {
        if inFlight && !force {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshTask(force: force)
        }
    }

    func applySettings(baseURL: String, managementKey: String, refreshSeconds: String, language: AppLanguage) -> String? {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            return t("Base URL 不能为空", "Base URL cannot be empty")
        }

        guard let interval = Double(refreshSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return t("刷新秒数必须是数字", "Refresh interval must be a number")
        }

        var next = AppConfig(
            baseURL: trimmedURL,
            managementKey: managementKey,
            refreshIntervalSeconds: interval,
            language: language
        )
        next.normalize()

        do {
            try configStore.save(next)
            config = next
            scheduleTimer()
            refreshNow(force: true)
            onStateChange?()
            return nil
        } catch {
            return "\(t("保存失败", "Save failed")): \(error.localizedDescription)"
        }
    }

    func maskedKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 8 {
            return trimmed
        }
        return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
    }

    func compact(_ value: Int64) -> String {
        let absValue = Double(abs(value))
        let sign = value < 0 ? "-" : ""

        switch absValue {
        case 1_000_000_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000))K"
        default:
            return "\(value)"
        }
    }

    var effectiveLanguage: AppLanguage {
        switch config.language {
        case .auto:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            if preferred.hasPrefix("zh") {
                return .zhHans
            }
            return .en
        case .zhHans, .en:
            return config.language
        }
    }

    func t(_ zh: String, _ en: String) -> String {
        effectiveLanguage == .zhHans ? zh : en
    }

    func languageLabel(_ language: AppLanguage) -> String {
        switch language {
        case .auto:
            return t("自动", "Auto")
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }

    func timeRangeLabel(_ range: UsageTimeRange) -> String {
        switch range {
        case .last24Hours:
            return t("最近24小时", "Last 24 Hours")
        case .last7Days:
            return t("最近7天", "Last 7 Days")
        case .allTime:
            return t("全部时间", "All Time")
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: config.refreshIntervalSeconds, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: true)
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshTask(force: Bool) async {
        if inFlight && !force {
            return
        }

        inFlight = true
        isLoading = true
        onStateChange?()

        defer {
            inFlight = false
            isLoading = false
            onStateChange?()
        }

        async let usageResult: Result<UsageSnapshot, Error> = {
            do {
                return .success(try await usageClient.fetchUsage(config: config))
            } catch {
                return .failure(error)
            }
        }()

        switch await usageResult {
        case .success(let nextSnapshot):
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                latestSnapshot = nextSnapshot
                allTimeSummary = UsageSummary(snapshot: nextSnapshot, range: .allTime)
                summary = UsageSummary(snapshot: nextSnapshot, range: selectedTimeRange)
            }
            errorMessage = nil
            lastUpdatedAt = Date()
        case .failure(let error):
            if let usageError = error as? UsageClientError {
                errorMessage = usageError.message(t)
            } else {
                errorMessage = error.localizedDescription
            }
            lastUpdatedAt = Date()
        }
    }

    private func rebuildSelectedSummary() {
        guard let latestSnapshot else {
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            summary = UsageSummary(snapshot: latestSnapshot, range: selectedTimeRange)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model = DashboardModel()
    private var settingsWindow: NSWindow?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var appDeactivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureObservers()

        model.onStateChange = { [weak self] in
            self?.updateStatusItem()
        }

        updateStatusItem()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPopoverMonitors()
        removeObservers()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "CLIProxyAPI") {
            image.isTemplate = true
            button.image = image
        }
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.title = " --"
        button.toolTip = model.t("CLIProxyAPI 使用监控", "CLIProxyAPI Usage Monitor")
    }

    private func configurePopover() {
        popover.animates = true
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
    }

    private func configureObservers() {
        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover(nil)
            }
        }
    }

    private func removeObservers() {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let error = model.errorMessage {
            button.title = " !"
            button.toolTip = error
            return
        }

        if let summary = model.allTimeSummary {
            button.title = " \(model.compact(summary.totalRequests))R"
            button.toolTip = "\(model.t("请求", "Requests")): \(summary.totalRequests) \(model.t("失败", "Failed")): \(summary.failureCount) \(model.t("令牌", "Tokens")): \(summary.totalTokens)"
            return
        }

        button.title = " --"
        button.toolTip = model.t("等待数据", "Waiting for data")
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(relativeTo: button)
            return
        }

        togglePopover(sender)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
            return
        }

        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startPopoverMonitors()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            closePopover(nil)
        }

        let menu = NSMenu()
        let refresh = NSMenuItem(
            title: model.t("刷新", "Refresh"),
            action: #selector(handleRefreshMenuItem(_:)),
            keyEquivalent: "r"
        )
        refresh.target = self

        let settings = NSMenuItem(
            title: model.t("设置", "Settings"),
            action: #selector(handleSettingsMenuItem(_:)),
            keyEquivalent: ","
        )
        settings.target = self

        let quit = NSMenuItem(
            title: model.t("退出", "Quit"),
            action: #selector(handleQuitMenuItem(_:)),
            keyEquivalent: "q"
        )
        quit.target = self

        menu.addItem(refresh)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func handleRefreshMenuItem(_ sender: Any?) {
        model.refreshNow(force: true)
    }

    @objc private func handleSettingsMenuItem(_ sender: Any?) {
        showSettingsWindow()
    }

    @objc private func handleQuitMenuItem(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func closePopover(_ sender: Any?) {
        guard popover.isShown else {
            stopPopoverMonitors()
            return
        }
        popover.performClose(sender)
    }

    private func startPopoverMonitors() {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.closePopover(nil)
                }
            }
        }

        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self {
                    let eventWindow = event.window
                    Task { @MainActor [weak self] in
                        guard let self, self.popover.isShown else {
                            return
                        }

                        let popoverWindow = self.popover.contentViewController?.view.window
                        let statusButtonWindow = self.statusItem.button?.window
                        if eventWindow !== popoverWindow, eventWindow !== statusButtonWindow {
                            self.closePopover(nil)
                        }
                    }
                }
                return event
            }
        }
    }

    private func stopPopoverMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverMonitors()
    }

    private func showSettingsWindow() {
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.isReleasedWhenClosed = false
            created.center()
            settingsWindow = created
            window = created
        }

        window.title = model.t("偏好设置", "Preferences")
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                model: model,
                onClose: { [weak window] in
                    window?.close()
                }
            )
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                headerCard
                metricsCard
                TrendChartCard(
                    title: model.t("每小时请求", "Requests / Hour"),
                    symbol: "chart.line.uptrend.xyaxis",
                    values: model.summary?.requestsByHour ?? [],
                    tint: .accentColor
                )
                TrendChartCard(
                    title: model.t("每小时令牌", "Tokens / Hour"),
                    symbol: "bolt.horizontal.fill",
                    values: model.summary?.tokensByHour ?? [],
                    tint: .green
                )

                HStack(alignment: .top, spacing: 10) {
                    RankedSectionCard(
                        title: model.t("模型排行", "Top Models"),
                        symbol: "cpu",
                        rows: model.summary?.topModels ?? [],
                        compact: model.compact,
                        displayName: { $0 },
                        emptyMessage: model.t("暂无数据", "No data")
                    )
                    RankedSectionCard(
                        title: model.t("凭证排行", "Top Credentials"),
                        symbol: "key.horizontal",
                        rows: model.summary?.topAPIs ?? [],
                        compact: model.compact,
                        displayName: model.maskedKey,
                        emptyMessage: model.t("暂无数据", "No data")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 420, height: 620)
        .background(.regularMaterial)
    }

    private var headerCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("CLIProxyAPI", systemImage: "waveform.path.ecg")
                        .font(.headline)

                    Spacer()

                    Circle()
                        .fill(model.errorMessage == nil ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(model.errorMessage == nil ? model.t("在线", "Online") : model.t("错误", "Error"))
                }

                Text(model.config.baseURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Text(model.isLoading ? model.t("刷新中", "Refreshing") : (model.errorMessage == nil ? model.t("实时", "Live") : model.t("异常", "Error")))
                    if let date = model.lastUpdatedAt {
                        Text(date, format: .dateTime.hour().minute().second())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .frame(minHeight: 96)
    }

    private var metricsCard: some View {
        let summary = model.summary

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(model.t("概览", "Overview"), systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker(model.t("时间范围", "Time Range"), selection: $model.selectedTimeRange) {
                        ForEach(UsageTimeRange.allCases) { range in
                            Text(model.timeRangeLabel(range)).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: model.t("请求", "Requests"), value: model.compact(summary?.totalRequests ?? 0), symbol: "paperplane")
                    StatTile(title: model.t("令牌", "Tokens"), value: model.compact(summary?.totalTokens ?? 0), symbol: "bolt")
                    StatTile(title: model.t("成功", "Success"), value: "\(summary?.successCount ?? 0)", symbol: "checkmark.circle")
                    StatTile(title: model.t("失败", "Failure"), value: String(format: "%.2f%%", (summary?.failureRate ?? 0) * 100), symbol: "exclamationmark.triangle")
                }
            }
        }
    }

}

private struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TrendPoint: Identifiable {
    let hour: Int
    let value: Double

    var id: Int { hour }
}

private struct TrendChartCard: View {
    let title: String
    let symbol: String
    let values: [Int64]
    let tint: Color

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Chart(points) { point in
                    AreaMark(
                        x: .value("Hour", point.hour),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                }
                .chartXScale(domain: 0...23)
                .chartYScale(domain: 0...(maxYValue * 1.1))
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.quaternary)
                        AxisTick()
                            .foregroundStyle(.secondary)
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(String(format: "%02d", hour))
                            }
                        }
                        .font(.caption2)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 90)
            }
        }
    }

    private var points: [TrendPoint] {
        Array(values.enumerated()).map { index, value in
            TrendPoint(hour: index, value: Double(max(value, 0)))
        }
    }

    private var maxYValue: Double {
        max(points.map(\.value).max() ?? 1, 1)
    }
}

private struct RankedSectionCard: View {
    let title: String
    let symbol: String
    let rows: [RankedUsage]
    let compact: (Int64) -> String
    let displayName: (String) -> String
    let emptyMessage: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if rows.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let peak = max(rows.map(\.requests).max() ?? 1, 1)
                    ForEach(rows) { row in
                        RankedRow(
                            name: displayName(row.name),
                            detail: "\(row.requests)R / \(compact(row.tokens))T",
                            ratio: Double(row.requests) / Double(peak)
                        )
                    }
                }
            }
        }
    }
}

private struct RankedRow: View {
    let name: String
    let detail: String
    let ratio: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: ratio)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: DashboardModel
    let onClose: () -> Void

    @State private var baseURL: String
    @State private var managementKey: String
    @State private var refreshSeconds: String
    @State private var language: AppLanguage
    @State private var error: String?

    init(model: DashboardModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _baseURL = State(initialValue: model.config.baseURL)
        _managementKey = State(initialValue: model.config.managementKey)
        _refreshSeconds = State(initialValue: String(Int(model.config.refreshIntervalSeconds)))
        _language = State(initialValue: model.config.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("偏好设置", "Preferences"))
                .font(.title3.weight(.semibold))

            Form {
                Section(model.t("连接", "Connection")) {
                    TextField(model.t("Base URL", "Base URL"), text: $baseURL)
                    SecureField(model.t("管理密钥", "Management Key"), text: $managementKey)
                }
                Section(model.t("刷新", "Refresh")) {
                    TextField(model.t("刷新秒数 (3-300)", "Refresh Seconds (3-300)"), text: $refreshSeconds)
                        .frame(maxWidth: 160, alignment: .leading)
                }
                Section(model.t("语言", "Language")) {
                    Picker(model.t("界面语言", "UI Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(model.languageLabel(item)).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button(model.t("取消", "Cancel")) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button(model.t("保存", "Save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420, height: 340)
        .background(.regularMaterial)
        .onAppear {
            syncFromModel()
        }
    }

    private func save() {
        if let message = model.applySettings(baseURL: baseURL, managementKey: managementKey, refreshSeconds: refreshSeconds, language: language) {
            error = message
            return
        }
        onClose()
    }

    private func syncFromModel() {
        baseURL = model.config.baseURL
        managementKey = model.config.managementKey
        refreshSeconds = String(Int(model.config.refreshIntervalSeconds))
        language = model.config.language
        error = nil
    }
}

@main
struct CliproxyStatusBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
