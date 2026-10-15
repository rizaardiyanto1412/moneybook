import Foundation

/// Every live row the app knows about, plus the sync cursor. Persisted as the JSON cache.
public struct Snapshot: Codable, Sendable, Equatable {
    public static let formatVersion = 1

    public var version: Int = Snapshot.formatVersion
    /// Which server this cache belongs to; a different URL starts from scratch.
    public var serverURL: String = ""
    public var cursor: Int64 = 0
    public var groups: [String: AccountGroup] = [:]
    public var accounts: [String: Account] = [:]
    public var categories: [String: Category] = [:]
    public var transactions: [String: Transaction] = [:]
    public var budgets: [String: Budget] = [:]
    public var settings: [String: String] = [:]

    public init(serverURL: String = "") { self.serverURL = serverURL }

    public var isEmpty: Bool { cursor == 0 && transactions.isEmpty && accounts.isEmpty }

    /// Applies a `/api/sync` delta: upserts rows by id, drops tombstones, advances the cursor.
    /// Returns whether anything visible changed.
    @discardableResult
    public mutating func merge(_ r: SyncResponse) -> Bool {
        var changed = false
        changed = Self.apply(r.accountGroups, into: &groups) || changed
        changed = Self.apply(r.accounts, into: &accounts) || changed
        changed = Self.apply(r.categories, into: &categories) || changed
        changed = Self.apply(r.transactions, into: &transactions) || changed
        changed = Self.apply(r.budgets, into: &budgets) || changed
        if !r.settings.isEmpty && r.settings != settings {
            settings = r.settings
            changed = true
        }
        cursor = max(cursor, r.cursor)
        return changed
    }

    /// Upserts one row (e.g. the response of a REST write) so the UI updates before the next sync.
    /// A row older than what we already have is ignored.
    @discardableResult
    static func apply<Row: SyncRow>(_ rows: [Row], into dict: inout [String: Row]) -> Bool {
        var changed = false
        for row in rows {
            if let existing = dict[row.id], existing.updatedAt > row.updatedAt { continue }
            if row.deleted {
                if dict.removeValue(forKey: row.id) != nil { changed = true }
            } else if dict[row.id] != row {
                dict[row.id] = row
                changed = true
            }
        }
        return changed
    }

    public mutating func upsert(_ t: Transaction) { Self.apply([t], into: &transactions) }
    public mutating func upsert(_ a: Account) { Self.apply([a], into: &accounts) }
    public mutating func upsert(_ g: AccountGroup) { Self.apply([g], into: &groups) }
    public mutating func upsert(_ c: Category) { Self.apply([c], into: &categories) }
    public mutating func upsert(_ b: Budget) { Self.apply([b], into: &budgets) }

    // MARK: Sorted views

    public var sortedGroups: [AccountGroup] { groups.values.sorted { ($0.sort, $0.name) < ($1.sort, $1.name) } }
    public var sortedAccounts: [Account] { accounts.values.sorted { ($0.sort, $0.name.lowercased()) < ($1.sort, $1.name.lowercased()) } }

    /// Top-level categories of a type, in display order.
    public func topCategories(_ type: CategoryType) -> [Category] {
        categories.values.filter { $0.type == type && $0.parentId == nil }.sorted { ($0.sort, $0.name) < ($1.sort, $1.name) }
    }
    public func subcategories(of parentId: String) -> [Category] {
        categories.values.filter { $0.parentId == parentId }.sorted { ($0.sort, $0.name) < ($1.sort, $1.name) }
    }
    /// The top-level category a (sub)category rolls up into.
    public func rootCategory(_ id: String?) -> Category? {
        guard let id, let c = categories[id] else { return nil }
        if let p = c.parentId, let parent = categories[p] { return parent }
        return c
    }

    // MARK: Settings

    public var currency: String { settings["currency"].flatMap { $0.isEmpty ? nil : $0 } ?? "USD" }
    public var monthStartDay: Int { min(max(Int(settings["month_start_day"] ?? "1") ?? 1, 1), 28) }
    /// 1 = Sunday, 2 = Monday (Calendar.firstWeekday convention).
    public var firstWeekday: Int { settings["week_start"] == "1" ? 2 : 1 }
    public var timezone: String { settings["timezone"] ?? "UTC" }
    public var defaultAccountId: String? { settings["default_account_id"].flatMap { $0.isEmpty ? nil : $0 } }
}
