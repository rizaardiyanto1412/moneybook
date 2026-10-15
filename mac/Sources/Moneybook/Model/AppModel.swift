import AppKit
import Foundation
import MoneybookClient
import MoneybookCore
import Observation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case transactions, stats, accounts, budget, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .transactions: "list.bullet.rectangle"
        case .stats: "chart.pie"
        case .accounts: "creditcard"
        case .budget: "gauge.with.dots.needle.33percent"
        case .settings: "gearshape"
        }
    }
}

enum TransactionsMode: String, CaseIterable, Identifiable {
    case daily = "Daily", calendar = "Calendar", monthly = "Monthly", summary = "Summary"
    var id: String { rawValue }
}

enum ConnectionState: Equatable {
    case unconfigured
    case connecting
    case online
    case offline(String)
}

/// Opens the transaction editor for a new or an existing transaction.
struct EditorRequest: Identifiable {
    let id = UUID()
    var transactionId: String?
    var type: TxType = .expense
    var day: String?
}

/// What the editor sends to the server.
struct TransactionDraft {
    var id: String?
    var type: TxType = .expense
    var date = Date()
    var amount: Double = 0
    var accountId: String?
    var toAccountId: String?
    var categoryId: String?
    var note = ""
    var memo = ""
}

@Observable
final class AppModel {
    // MARK: Data
    private(set) var snapshot = Snapshot()
    private(set) var connection: ConnectionState = .unconfigured
    private(set) var lastSync: Date?
    private(set) var isSyncing = false

    // MARK: Navigation
    var section: SidebarSection = .transactions
    var month: YearMonth
    var transactionsMode: TransactionsMode = .daily
    var searchText = ""
    /// Drill-down stacks (category ids / account ids), kept here so they survive section switches.
    var statsPath: [String] = []
    var accountsPath: [String] = []
    var editor: EditorRequest?
    var errorMessage: String?

    // MARK: Configuration
    private(set) var serverURL: String
    private(set) var token: String

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var resyncRequested = false
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var receiptCache: [String: NSImage] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var keychainPending = true

    static let serverDefaultsKey = "serverURL"
    static let tokenKeychainAccount = "apiToken"

    init() {
        var url = UserDefaults.standard.string(forKey: Self.serverDefaultsKey) ?? ""
        // `-apiToken <token>` on the command line or `defaults write app.moneybook.mac apiToken <token>`
        // override the Keychain (the persistent one is migrated into the Keychain in `start()`).
        var tok = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        #if DEBUG
        if url.isEmpty { url = "http://localhost:8787" }
        if tok.isEmpty { tok = "dev" }
        #endif
        serverURL = url
        token = tok
        month = Periods.yearMonth(containing: Periods.today(), startDay: 1)
        if let cached = Self.loadCache(), cached.serverURL == url {
            snapshot = cached
            month = Periods.yearMonth(containing: Periods.today(), startDay: cached.monthStartDay)
        } else {
            snapshot = Snapshot(serverURL: url)
        }
        if !url.isEmpty { connection = .connecting }
    }

    /// Reads the token from the Keychain off the main thread: the read can wait on an access prompt
    /// (e.g. after the app was rebuilt), and that must never block the UI or the cached data.
    private func loadTokenFromKeychain() async {
        defer { keychainPending = false }
        let account = Self.tokenKeychainAccount
        if !token.isEmpty {
            // A token from `defaults write` is moved into the Keychain once.
            if UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["apiToken"] != nil {
                let value = token
                let stored = await Task.detached { Keychain.write(account, value) }.value
                if stored { UserDefaults.standard.removeObject(forKey: "apiToken") }
            }
            return
        }
        let stored = await Task.detached { Keychain.read(account) }.value
        if let stored, !stored.isEmpty, token.isEmpty {
            token = stored
            restartPolling()
        } else if token.isEmpty {
            connection = .unconfigured
        }
    }

    var client: APIClient? { token.isEmpty ? nil : APIClient(server: serverURL, token: token) }
    var isConfigured: Bool { client != nil }
    var currency: String { snapshot.currency }
    func money(_ amount: Double, symbol: Bool = true) -> String { Money.format(amount, currency: currency, symbol: symbol) }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(true) }
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(false) }
        }
        restartPolling()
        Task { await loadTokenFromKeychain() }
    }

    private func setActive(_ active: Bool) {
        isActive = active
        restartPolling()
    }

    /// Syncs immediately, then every 10 s while the app is active (every 60 s in the background,
    /// which keeps the menu bar extra reasonably fresh).
    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                let interval: Duration = (self?.isActive ?? false) ? .seconds(10) : .seconds(60)
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: Sync

    func sync() async {
        guard let client else {
            if !keychainPending { connection = .unconfigured }
            return
        }
        if isSyncing {
            resyncRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            resyncRequested = false
            do {
                let wasEmpty = snapshot.cursor == 0
                let delta = try await client.sync(since: snapshot.cursor)
                // The config may have changed while we were waiting.
                guard client.baseURL == self.client?.baseURL else { return }
                let monthStart = snapshot.monthStartDay
                if snapshot.merge(delta) {
                    scheduleCacheSave()
                    if wasEmpty || monthStart != snapshot.monthStartDay {
                        month = Periods.yearMonth(containing: Periods.today(), startDay: snapshot.monthStartDay)
                    }
                }
                if connection != .online {
                    connection = .online
                    await adoptLocalTimezoneIfNeeded()
                }
                lastSync = Date()
            } catch {
                connection = .offline(error.localizedDescription)
                return
            }
        } while resyncRequested
    }

    /// New servers default to UTC; adopt the Mac's zone once so "today" and AI-added dates are right.
    private func adoptLocalTimezoneIfNeeded() async {
        let key = "timezoneChecked:\(serverURL)"
        guard !UserDefaults.standard.bool(forKey: key), let client else { return }
        let local = TimeZone.current.identifier
        if snapshot.timezone == "UTC" && local != "UTC" && local != "GMT" {
            if let settings = try? await client.patchSettings(["timezone": local]) {
                snapshot.settings = settings
                scheduleCacheSave()
            } else { return }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Saves new connection settings; a different server starts from an empty cache.
    func configure(server: String, token newToken: String) {
        let server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedServer = server != serverURL
        serverURL = server
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(server, forKey: Self.serverDefaultsKey)
        let account = Self.tokenKeychainAccount, value = token
        Task.detached { Keychain.write(account, value) }
        if changedServer {
            snapshot = Snapshot(serverURL: server)
            receiptCache = [:]
            scheduleCacheSave()
        }
        connection = isConfigured ? .connecting : .unconfigured
        restartPolling()
    }

    /// Checks a server/token pair without saving it.
    func testConnection(server: String, token: String) async -> Result<String, Error> {
        guard let c = APIClient(server: server, token: token) else { return .failure(APIError(status: 0, message: "Enter a valid server URL and token")) }
        do {
            try await c.health()
            let r = try await c.sync(since: Int64.max - 1)
            return .success("Connected. Currency \(r.settings["currency"] ?? "USD"), timezone \(r.settings["timezone"] ?? "UTC").")
        } catch {
            return .failure(error)
        }
    }

    /// Runs a write, applies its result locally, then pulls the server's view of the world.
    @discardableResult
    private func write<T>(_ op: (APIClient) async throws -> T, apply: ((T) -> Void)? = nil) async throws -> T {
        guard let client else { throw APIError(status: 0, message: "Not connected. Set the server in Settings.") }
        if case .offline = connection { /* still try: the server may be back */ }
        let result = try await op(client)
        apply?(result)
        scheduleCacheSave()
        Task { await self.sync() }
        return result
    }

    // MARK: Cache

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Moneybook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    private static func loadCache() -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data),
              s.version == Snapshot.formatVersion else { return nil }
        return s
    }

    private func scheduleCacheSave() {
        saveTask?.cancel()
        let snap = snapshot
        let url = Self.cacheURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Navigation helpers

    var period: Period { Periods.month(month, startDay: snapshot.monthStartDay) }
    /// The month containing today (for the menu bar).
    var currentMonth: YearMonth { Periods.yearMonth(containing: Periods.today(), startDay: snapshot.monthStartDay) }
    var currentPeriod: Period { Periods.month(currentMonth, startDay: snapshot.monthStartDay) }
    var yearPeriod: Period { Periods.year(month.year, startDay: snapshot.monthStartDay) }
    /// The Monthly tab navigates by year.
    var navigatesByYear: Bool { section == .transactions && transactionsMode == .monthly }

    func step(_ delta: Int) {
        month = month.adding(months: navigatesByYear ? delta * 12 : delta)
    }
    func goToToday() { month = currentMonth }
    var isCurrentMonth: Bool { navigatesByYear ? month.year == currentMonth.year : month == currentMonth }

    func newTransaction(type: TxType = .expense, day: String? = nil) {
        editor = EditorRequest(transactionId: nil, type: type, day: day)
    }
    func edit(_ id: String) {
        editor = EditorRequest(transactionId: id)
    }

    // MARK: Transactions

    @discardableResult
    func save(_ d: TransactionDraft) async throws -> Transaction {
        var body: [String: Any] = [
            "type": d.type.rawValue,
            "amount": d.amount,
            "date": Periods.localStamp(d.date),
            "note": d.note,
            "description": d.memo,
        ]
        if let a = d.accountId { body["account_id"] = a }
        if d.type == .transfer {
            if let t = d.toAccountId { body["to_account_id"] = t }
        } else if let c = d.categoryId {
            body["category_id"] = c
        }
        if let id = d.id {
            return try await write({ try await $0.updateTransaction(id, body) }, apply: { self.snapshot.upsert($0) })
        }
        body["id"] = UUID().uuidString.lowercased()
        body["source"] = "app"
        return try await write({ try await $0.createTransaction(body) }, apply: { self.snapshot.upsert($0) })
    }

    func delete(transactionIds ids: [String]) async {
        for id in ids {
            do {
                try await write({ try await $0.deleteTransaction(id) }, apply: { _ in self.snapshot.transactions.removeValue(forKey: id) })
            } catch {
                errorMessage = "Couldn't delete: \(error.localizedDescription)"
            }
        }
    }

    func uploadReceipt(transactionId: String, data: Data, mimeType: String) async throws {
        try await write({ try await $0.uploadReceipt(transactionId, data: data, mimeType: mimeType) }, apply: { self.snapshot.upsert($0) })
    }

    func removeReceipt(transactionId: String) async throws {
        try await write({ try await $0.deleteReceipt(transactionId) }, apply: { _ in
            if var t = self.snapshot.transactions[transactionId] { t.receipt = nil; self.snapshot.transactions[transactionId] = t }
        })
    }

    func receiptImage(_ key: String) async -> NSImage? {
        if let img = receiptCache[key] { return img }
        guard let client, let data = try? await client.receiptData(key), let img = NSImage(data: data) else { return nil }
        receiptCache[key] = img
        return img
    }

    // MARK: Accounts, groups, categories, budgets, settings

    func saveAccount(id: String?, groupId: String, name: String, initialBalance: Double, includeInTotals: Bool, hidden: Bool, note: String) async throws {
        let body: [String: Any] = ["group_id": groupId, "name": name, "initial_balance": initialBalance,
                                   "include_in_totals": includeInTotals, "hidden": hidden, "note": note]
        if let id {
            try await write({ try await $0.updateAccount(id, body) }, apply: { self.snapshot.upsert($0) })
        } else {
            try await write({ try await $0.createAccount(body) }, apply: { self.snapshot.upsert($0) })
        }
    }
    func deleteAccount(_ id: String) async throws {
        try await write({ try await $0.deleteAccount(id) }, apply: { _ in self.snapshot.accounts.removeValue(forKey: id) })
    }

    func saveGroup(id: String?, name: String, kind: String) async throws {
        let body: [String: Any] = ["name": name, "kind": kind]
        if let id {
            try await write({ try await $0.updateGroup(id, body) }, apply: { self.snapshot.upsert($0) })
        } else {
            try await write({ try await $0.createGroup(body) }, apply: { self.snapshot.upsert($0) })
        }
    }
    func deleteGroup(_ id: String) async throws {
        try await write({ try await $0.deleteGroup(id) }, apply: { _ in self.snapshot.groups.removeValue(forKey: id) })
    }

    func saveCategory(id: String?, type: CategoryType, name: String, icon: String, parentId: String?) async throws {
        if let id {
            let body: [String: Any] = ["name": name, "icon": icon]
            try await write({ try await $0.updateCategory(id, body) }, apply: { self.snapshot.upsert($0) })
        } else {
            var body: [String: Any] = ["type": type.rawValue, "name": name, "icon": icon]
            if let parentId { body["parent_id"] = parentId }
            try await write({ try await $0.createCategory(body) }, apply: { self.snapshot.upsert($0) })
        }
    }
    func deleteCategory(_ id: String) async throws {
        try await write({ try await $0.deleteCategory(id) }, apply: { _ in self.snapshot.categories.removeValue(forKey: id) })
    }

    /// `month == nil` sets the default for every month. Amount 0 removes that budget.
    func setBudget(categoryId: String?, month: YearMonth?, amount: Double) async throws {
        try await write({ try await $0.putBudget(categoryId: categoryId, month: month?.key, amount: amount) }, apply: { self.snapshot.upsert($0) })
    }

    func updateSettings(_ patch: [String: String]) async throws {
        try await write({ try await $0.patchSettings(patch) }, apply: { self.snapshot.settings = $0 })
    }
}
