import Foundation
import MoneybookClient
import Observation
import UIKit

enum ConnectionState: Equatable {
    case signedOut
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
    /// "Copy": a new entry for today prefilled from this transaction.
    var copyOf: String?
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

/// App state: the synced snapshot, the sign-in, and every write. Online-first with a JSON cache,
/// so the app opens instantly and stays readable offline. Same sync model as the Mac app.
@Observable
final class AppModel {
    // MARK: Data
    private(set) var snapshot = Snapshot()
    private(set) var connection: ConnectionState = .signedOut
    private(set) var lastSync: Date?
    private(set) var isSyncing = false

    // MARK: Navigation
    var month: YearMonth
    var editor: EditorRequest?
    var errorMessage: String?
    /// Short confirmation shown at the top of the screen ("Saved").
    private(set) var toastMessage: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // MARK: Sign-in
    private(set) var serverURL: String
    private(set) var token: String
    /// The email of the password login, when signed in with one.
    private(set) var email: String

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var resyncRequested = false
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var receiptCache: [String: UIImage] = [:]

    private static let serverKey = "serverURL"
    private static let emailKey = "email"
    private static let tokenAccount = "token"

    init() {
        let url = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
        serverURL = url
        token = Keychain.read(Self.tokenAccount) ?? ""
        #if DEBUG
        // Simulator runs: `-apiToken <token> -serverURL <url>` as launch arguments.
        if let t = UserDefaults.standard.string(forKey: "apiToken") { token = t }
        #endif
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        month = Periods.yearMonth(containing: Periods.today(), startDay: 1)
        if let cached = Self.loadCache(), cached.serverURL == url {
            snapshot = cached
            month = Periods.yearMonth(containing: Periods.today(), startDay: cached.monthStartDay)
        } else {
            snapshot = Snapshot(serverURL: url)
        }
        connection = token.isEmpty ? .signedOut : .connecting
    }

    var client: APIClient? { token.isEmpty ? nil : APIClient(server: serverURL, token: token) }
    var isSignedIn: Bool { !token.isEmpty }
    /// Signed in with the master API token rather than a password session.
    var usesAPIToken: Bool { isSignedIn && !token.hasPrefix("s_") }
    var currency: String { snapshot.currency }
    func money(_ amount: Double, symbol: Bool = true) -> String { Money.format(amount, currency: currency, symbol: symbol) }

    // MARK: Lifecycle

    /// Syncs now, then every 10 s while the app is in front. Nothing runs in the background.
    func setActive(_ active: Bool) {
        isActive = active
        pollTask?.cancel()
        guard active, isSignedIn else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: Sign-in

    /// Server URL as typed → normalised, or nil when it isn't a URL.
    static func normalizedServer(_ s: String) -> String? {
        APIClient(server: s, token: "")?.baseURL.absoluteString
    }

    func authStatus(server: String) async throws -> APIClient.AuthStatus {
        guard let c = APIClient(server: server, token: "") else { throw APIError(status: 0, message: "Enter a valid server address") }
        return try await c.authStatus()
    }

    func signIn(server: String, email: String, password: String) async throws {
        guard let c = APIClient(server: server, token: "") else { throw APIError(status: 0, message: "Enter a valid server address") }
        let session = try await c.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        adopt(server: c.baseURL.absoluteString, token: session, email: email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The API token is the master key; it works for everything, including AI access.
    func signIn(server: String, apiToken: String) async throws {
        guard let c = APIClient(server: server, token: apiToken) else { throw APIError(status: 0, message: "Enter a valid server address and token") }
        _ = try await c.sync(since: Int64.max - 1)
        adopt(server: c.baseURL.absoluteString, token: c.token, email: "")
    }

    private func adopt(server: String, token newToken: String, email newEmail: String) {
        if server != serverURL {
            snapshot = Snapshot(serverURL: server)
            receiptCache = [:]
            month = Periods.yearMonth(containing: Periods.today(), startDay: 1)
        }
        serverURL = server
        token = newToken
        email = newEmail
        UserDefaults.standard.set(server, forKey: Self.serverKey)
        UserDefaults.standard.set(newEmail, forKey: Self.emailKey)
        Keychain.write(Self.tokenAccount, newToken)
        connection = .connecting
        scheduleCacheSave()
        setActive(isActive)
    }

    /// Ends the device session on the server (best effort) and forgets it here, along with the cache.
    func signOut(message: String? = nil) {
        let old = client
        if let old, old.token.hasPrefix("s_") { Task { try? await old.logout() } }
        pollTask?.cancel()
        token = ""
        Keychain.write(Self.tokenAccount, "")
        snapshot = Snapshot(serverURL: serverURL)
        receiptCache = [:]
        connection = .signedOut
        errorMessage = message
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    /// Sets or changes the password login. Other devices are signed out; this one stays signed in.
    func setPassword(email newEmail: String, password: String, current: String?) async throws {
        guard let client else { throw APIError(status: 0, message: "You're signed out.") }
        let e = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
        try await client.setPassword(email: e, password: password, current: current)
        if !usesAPIToken {
            email = e
            UserDefaults.standard.set(e, forKey: Self.emailKey)
        }
    }

    /// Signs out every password session, including this one if it is one.
    func logoutAll() async throws {
        guard let client else { throw APIError(status: 0, message: "You're signed out.") }
        try await client.logoutAll()
        if !usesAPIToken { signOut() }
    }

    /// Writes a JSON export to a temporary file for the share sheet.
    func exportBackup() async throws -> URL {
        guard let client else { throw APIError(status: 0, message: "You're signed out.") }
        let raw = try await client.exportAll()
        let pretty = (try? JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: raw), options: [.prettyPrinted, .sortedKeys])) ?? raw
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moneybook-\(Periods.today()).json")
        try pretty.write(to: url, options: .atomic)
        return url
    }

    // MARK: Sync

    func sync() async {
        guard let client else { return }
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
                // Signed out or switched servers while we were waiting.
                guard client.token == token, client.baseURL == self.client?.baseURL else { return }
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
            } catch let e as APIError where e.status == 401 {
                if client.token == token { signOut(message: "You were signed out. Sign in again.") }
                return
            } catch {
                connection = .offline(error.localizedDescription)
                return
            }
        } while resyncRequested
    }

    /// New servers default to UTC; adopt the phone's zone once so "today" and AI-added dates are right.
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

    /// Runs a write, applies its result locally, then pulls the server's view of the world.
    @discardableResult
    private func write<T>(_ op: (APIClient) async throws -> T, apply: ((T) -> Void)? = nil) async throws -> T {
        guard let client else { throw APIError(status: 0, message: "You're signed out.") }
        let result = try await op(client)
        apply?(result)
        scheduleCacheSave()
        Task { await self.sync() }
        return result
    }

    // MARK: Cache

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Periods

    var period: Period { Periods.month(month, startDay: snapshot.monthStartDay) }
    var currentMonth: YearMonth { Periods.yearMonth(containing: Periods.today(), startDay: snapshot.monthStartDay) }
    var isCurrentMonth: Bool { month == currentMonth }
    func step(_ delta: Int) { month = month.adding(months: delta) }
    func goToToday() { month = currentMonth }

    func toast(_ message: String, seconds: Double = 1.8) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { toastMessage = nil }
        }
    }

    func newTransaction(type: TxType = .expense, day: String? = nil) {
        editor = EditorRequest(transactionId: nil, type: type, day: day)
    }
    func edit(_ id: String) {
        editor = EditorRequest(transactionId: id)
    }
    func copy(_ id: String) {
        editor = EditorRequest(type: snapshot.transactions[id]?.type ?? .expense, copyOf: id)
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

    func delete(transactionId id: String) async {
        do {
            try await write({ try await $0.deleteTransaction(id) }, apply: { _ in self.snapshot.transactions.removeValue(forKey: id) })
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
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

    func receiptImage(_ key: String) async -> UIImage? {
        if let img = receiptCache[key] { return img }
        guard let client, let data = try? await client.receiptData(key), let img = UIImage(data: data) else { return nil }
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
