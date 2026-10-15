import Foundation

// Rows mirror the server tables (docs/API.md). Decoding is lenient about number/bool
// representations because SQLite drivers differ (0/1 vs true/false, Int vs Double).

public enum TxType: String, Codable, CaseIterable, Sendable, Identifiable {
    case income, expense, transfer
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        case .transfer: "Transfer"
        }
    }
}

public enum CategoryType: String, Codable, CaseIterable, Sendable, Identifiable {
    case expense, income
    public var id: String { rawValue }
    public var label: String { self == .expense ? "Expense" : "Income" }
}

public protocol SyncRow: Codable, Identifiable, Hashable, Sendable where ID == String {
    var id: String { get }
    var updatedAt: Int64 { get }
    var deleted: Bool { get }
}

public struct AccountGroup: SyncRow, Hashable {
    public var id: String
    public var name: String
    public var kind: String // asset | liability | card
    public var sort: Int
    public var updatedAt: Int64
    public var deleted: Bool

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: String = "asset", sort: Int = 999, updatedAt: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.sort = sort; self.updatedAt = updatedAt; self.deleted = deleted
    }

    public var isLiability: Bool { kind == "liability" }

    enum CodingKeys: String, CodingKey { case id, name, kind, sort, updated_at, deleted }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "asset"
        sort = c.flexInt(.sort)
        updatedAt = c.flexInt64(.updated_at)
        deleted = c.flexBool(.deleted)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(kind, forKey: .kind)
        try c.encode(sort, forKey: .sort); try c.encode(updatedAt, forKey: .updated_at); try c.encode(deleted ? 1 : 0, forKey: .deleted)
    }
}

public struct Account: SyncRow, Hashable {
    public var id: String
    public var groupId: String
    public var name: String
    public var initialBalance: Double
    public var currency: String?
    public var includeInTotals: Bool
    public var hidden: Bool
    public var note: String
    public var sort: Int
    public var updatedAt: Int64
    public var deleted: Bool

    public init(id: String = UUID().uuidString.lowercased(), groupId: String, name: String, initialBalance: Double = 0, currency: String? = nil,
                includeInTotals: Bool = true, hidden: Bool = false, note: String = "", sort: Int = 999, updatedAt: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.groupId = groupId; self.name = name; self.initialBalance = initialBalance; self.currency = currency
        self.includeInTotals = includeInTotals; self.hidden = hidden; self.note = note; self.sort = sort; self.updatedAt = updatedAt; self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey { case id, group_id, name, initial_balance, currency, include_in_totals, hidden, note, sort, updated_at, deleted }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        groupId = try c.decodeIfPresent(String.self, forKey: .group_id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        initialBalance = c.flexDouble(.initial_balance)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        includeInTotals = c.contains(.include_in_totals) ? c.flexBool(.include_in_totals) : true
        hidden = c.flexBool(.hidden)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        sort = c.flexInt(.sort)
        updatedAt = c.flexInt64(.updated_at)
        deleted = c.flexBool(.deleted)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(groupId, forKey: .group_id); try c.encode(name, forKey: .name)
        try c.encode(initialBalance, forKey: .initial_balance); try c.encodeIfPresent(currency, forKey: .currency)
        try c.encode(includeInTotals ? 1 : 0, forKey: .include_in_totals); try c.encode(hidden ? 1 : 0, forKey: .hidden)
        try c.encode(note, forKey: .note); try c.encode(sort, forKey: .sort)
        try c.encode(updatedAt, forKey: .updated_at); try c.encode(deleted ? 1 : 0, forKey: .deleted)
    }
}

public struct Category: SyncRow, Hashable {
    public var id: String
    public var type: CategoryType
    public var name: String
    public var icon: String
    public var parentId: String?
    public var sort: Int
    public var updatedAt: Int64
    public var deleted: Bool

    public init(id: String = UUID().uuidString.lowercased(), type: CategoryType, name: String, icon: String = "", parentId: String? = nil,
                sort: Int = 999, updatedAt: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.type = type; self.name = name; self.icon = icon; self.parentId = parentId
        self.sort = sort; self.updatedAt = updatedAt; self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey { case id, type, name, icon, parent_id, sort, updated_at, deleted }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = CategoryType(rawValue: (try? c.decode(String.self, forKey: .type)) ?? "expense") ?? .expense
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        parentId = try c.decodeIfPresent(String.self, forKey: .parent_id)
        sort = c.flexInt(.sort)
        updatedAt = c.flexInt64(.updated_at)
        deleted = c.flexBool(.deleted)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(type.rawValue, forKey: .type); try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon); try c.encodeIfPresent(parentId, forKey: .parent_id); try c.encode(sort, forKey: .sort)
        try c.encode(updatedAt, forKey: .updated_at); try c.encode(deleted ? 1 : 0, forKey: .deleted)
    }
}

public struct Transaction: SyncRow, Hashable {
    public var id: String
    public var type: TxType
    /// 'YYYY-MM-DDTHH:MM' in the user's local time.
    public var date: String
    public var amount: Double
    public var accountId: String
    public var toAccountId: String?
    public var categoryId: String?
    public var note: String
    public var memo: String // `description` on the wire
    public var receipt: String?
    public var source: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deleted: Bool

    public init(id: String = UUID().uuidString.lowercased(), type: TxType, date: String, amount: Double, accountId: String, toAccountId: String? = nil,
                categoryId: String? = nil, note: String = "", memo: String = "", receipt: String? = nil, source: String = "app",
                createdAt: Int64 = 0, updatedAt: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.type = type; self.date = date; self.amount = amount; self.accountId = accountId; self.toAccountId = toAccountId
        self.categoryId = categoryId; self.note = note; self.memo = memo; self.receipt = receipt; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deleted = deleted
    }

    /// 'YYYY-MM-DD'
    public var day: String { String(date.prefix(10)) }
    /// 'HH:MM'
    public var time: String { date.count >= 16 ? String(date.dropFirst(11).prefix(5)) : "" }
    public var isAI: Bool { source == "ai" }

    enum CodingKeys: String, CodingKey {
        case id, type, date, amount, account_id, to_account_id, category_id, note, description, receipt, source, created_at, updated_at, deleted
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = TxType(rawValue: (try? c.decode(String.self, forKey: .type)) ?? "expense") ?? .expense
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        amount = c.flexDouble(.amount)
        accountId = try c.decodeIfPresent(String.self, forKey: .account_id) ?? ""
        toAccountId = try c.decodeIfPresent(String.self, forKey: .to_account_id)
        categoryId = try c.decodeIfPresent(String.self, forKey: .category_id)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        receipt = try c.decodeIfPresent(String.self, forKey: .receipt)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "app"
        createdAt = c.flexInt64(.created_at)
        updatedAt = c.flexInt64(.updated_at)
        deleted = c.flexBool(.deleted)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(type.rawValue, forKey: .type); try c.encode(date, forKey: .date)
        try c.encode(amount, forKey: .amount); try c.encode(accountId, forKey: .account_id)
        try c.encodeIfPresent(toAccountId, forKey: .to_account_id); try c.encodeIfPresent(categoryId, forKey: .category_id)
        try c.encode(note, forKey: .note); try c.encode(memo, forKey: .description); try c.encodeIfPresent(receipt, forKey: .receipt)
        try c.encode(source, forKey: .source); try c.encode(createdAt, forKey: .created_at)
        try c.encode(updatedAt, forKey: .updated_at); try c.encode(deleted ? 1 : 0, forKey: .deleted)
    }
}

public struct Budget: SyncRow, Hashable {
    public var id: String
    /// nil = the Total budget.
    public var categoryId: String?
    /// 'YYYY-MM', or nil for every month.
    public var month: String?
    public var amount: Double
    public var updatedAt: Int64
    public var deleted: Bool

    public init(id: String = UUID().uuidString.lowercased(), categoryId: String?, month: String?, amount: Double, updatedAt: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.categoryId = categoryId; self.month = month; self.amount = amount; self.updatedAt = updatedAt; self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey { case id, category_id, month, amount, updated_at, deleted }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        categoryId = try c.decodeIfPresent(String.self, forKey: .category_id)
        month = try c.decodeIfPresent(String.self, forKey: .month)
        amount = c.flexDouble(.amount)
        updatedAt = c.flexInt64(.updated_at)
        deleted = c.flexBool(.deleted)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(categoryId, forKey: .category_id); try c.encodeIfPresent(month, forKey: .month)
        try c.encode(amount, forKey: .amount); try c.encode(updatedAt, forKey: .updated_at); try c.encode(deleted ? 1 : 0, forKey: .deleted)
    }
}

/// `GET /api/sync` response.
public struct SyncResponse: Decodable, Sendable {
    public var cursor: Int64
    public var accountGroups: [AccountGroup]
    public var accounts: [Account]
    public var categories: [Category]
    public var transactions: [Transaction]
    public var budgets: [Budget]
    public var settings: [String: String]

    public init(cursor: Int64, accountGroups: [AccountGroup] = [], accounts: [Account] = [], categories: [Category] = [],
                transactions: [Transaction] = [], budgets: [Budget] = [], settings: [String: String] = [:]) {
        self.cursor = cursor; self.accountGroups = accountGroups; self.accounts = accounts; self.categories = categories
        self.transactions = transactions; self.budgets = budgets; self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case cursor, account_groups, accounts, categories, transactions, budgets, settings }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cursor = c.flexInt64(.cursor)
        accountGroups = try c.decodeIfPresent([AccountGroup].self, forKey: .account_groups) ?? []
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        transactions = try c.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        budgets = try c.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        settings = (try? c.decodeIfPresent([String: FlexString].self, forKey: .settings))?.mapValues(\.value) ?? [:]
    }
}

// MARK: - Lenient decoding helpers

struct FlexString: Decodable {
    let value: String
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int64.self) { value = String(i) }
        else if let n = try? c.decode(Double.self) { value = String(n) }
        else if let b = try? c.decode(Bool.self) { value = b ? "1" : "0" }
        else { value = "" }
    }
}

extension KeyedDecodingContainer {
    func flexDouble(_ key: Key) -> Double {
        if let v = try? decode(Double.self, forKey: key) { return v }
        if let s = try? decode(String.self, forKey: key) { return Double(s) ?? 0 }
        return 0
    }
    func flexInt64(_ key: Key) -> Int64 {
        if let v = try? decode(Int64.self, forKey: key) { return v }
        if let v = try? decode(Double.self, forKey: key) { return Int64(v) }
        if let s = try? decode(String.self, forKey: key) { return Int64(s) ?? 0 }
        return 0
    }
    func flexInt(_ key: Key) -> Int { Int(flexInt64(key)) }
    func flexBool(_ key: Key) -> Bool {
        if let b = try? decode(Bool.self, forKey: key) { return b }
        return flexInt64(key) != 0
    }
}
