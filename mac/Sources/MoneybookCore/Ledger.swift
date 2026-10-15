import Foundation

public struct Totals: Equatable, Sendable {
    public var income: Double = 0
    public var expense: Double = 0
    public init(income: Double = 0, expense: Double = 0) { self.income = income; self.expense = expense }
    public var total: Double { income - expense }
    public static func + (a: Totals, b: Totals) -> Totals { Totals(income: a.income + b.income, expense: a.expense + b.expense) }
}

public struct DayGroup: Identifiable, Equatable, Sendable {
    public var day: String
    public var transactions: [Transaction]
    public var totals: Totals
    public var id: String { day }
}

public struct CategorySlice: Identifiable, Equatable, Sendable {
    /// Category id, or "" for uncategorized.
    public var id: String
    public var name: String
    public var icon: String
    public var total: Double
    public var count: Int
    /// 0…100
    public var percent: Double
}

public struct BudgetLine: Identifiable, Equatable, Sendable {
    /// Category id, or nil for the Total budget.
    public var categoryId: String?
    public var name: String
    public var icon: String
    public var budget: Double
    public var spent: Double
    /// The budget row that applies (nil when the category has no budget).
    public var budgetRow: Budget?
    public var id: String { categoryId ?? "__total__" }
    public var remaining: Double { budget - spent }
    /// spent / budget, 0…∞
    public var ratio: Double { budget > 0 ? spent / budget : 0 }
    /// True when the applicable budget is a this-month override.
    public var isMonthOverride: Bool { budgetRow?.month != nil }
    /// Total line with no total budget of its own: Money Manager shows the sum of category budgets.
    public var isSynthetic: Bool { categoryId == nil && budgetRow == nil && budget > 0 }
}

public struct BalanceSummary: Equatable, Sendable {
    public var assets: Double
    public var liabilities: Double
    public var total: Double { assets - liabilities }
}

public enum Ledger {
    /// Newest first; ties broken by creation time like the server.
    public static func sortDescending(_ a: Transaction, _ b: Transaction) -> Bool {
        a.date != b.date ? a.date > b.date : a.createdAt > b.createdAt
    }

    public static func transactions(in period: Period, _ s: Snapshot) -> [Transaction] {
        s.transactions.values.filter { period.contains($0.date) }.sorted(by: sortDescending)
    }

    public static func totals<S: Sequence>(_ txs: S) -> Totals where S.Element == Transaction {
        var t = Totals()
        for tx in txs {
            switch tx.type {
            case .income: t.income += tx.amount
            case .expense: t.expense += tx.amount
            case .transfer: break
            }
        }
        return t
    }

    /// Groups transactions by day, newest day first.
    public static func groupByDay(_ txs: [Transaction]) -> [DayGroup] {
        Dictionary(grouping: txs, by: \.day)
            .map { DayGroup(day: $0.key, transactions: $0.value.sorted(by: sortDescending), totals: totals($0.value)) }
            .sorted { $0.day > $1.day }
    }

    public static func totalsByDay(_ txs: [Transaction]) -> [String: Totals] {
        Dictionary(grouping: txs, by: \.day).mapValues { totals($0) }
    }

    /// Spending (or income) per top-level category, largest first.
    public static func byCategory(_ txs: [Transaction], type: CategoryType, _ s: Snapshot) -> [CategorySlice] {
        let relevant = txs.filter { $0.type.rawValue == type.rawValue }
        let grand = relevant.reduce(0) { $0 + $1.amount }
        var sums: [String: (Double, Int)] = [:]
        for tx in relevant {
            let key = s.rootCategory(tx.categoryId)?.id ?? ""
            sums[key, default: (0, 0)].0 += tx.amount
            sums[key, default: (0, 0)].1 += 1
        }
        return sums.map { id, v in
            let c = s.categories[id]
            return CategorySlice(id: id, name: c?.name ?? "Uncategorized", icon: c?.icon ?? "", total: v.0, count: v.1,
                                 percent: grand > 0 ? v.0 / grand * 100 : 0)
        }.sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
    }

    /// Breakdown of one top-level category into its subcategories. Transactions filed directly
    /// under the parent appear as a slice with the parent's own id.
    public static func bySubcategory(_ txs: [Transaction], parentId: String, _ s: Snapshot) -> [CategorySlice] {
        let relevant = txs.filter { tx in tx.type != .transfer && s.rootCategory(tx.categoryId)?.id == parentId }
        let grand = relevant.reduce(0) { $0 + $1.amount }
        let parent = s.categories[parentId]
        var sums: [String: (Double, Int)] = [:]
        for tx in relevant {
            let key = tx.categoryId ?? parentId
            sums[key, default: (0, 0)].0 += tx.amount
            sums[key, default: (0, 0)].1 += 1
        }
        return sums.map { id, v in
            let c = s.categories[id]
            let name = id == parentId ? "\(parent?.name ?? "Other") (general)" : (c?.name ?? "Other")
            let icon = (c?.icon).flatMap { $0.isEmpty ? nil : $0 } ?? parent?.icon ?? ""
            return CategorySlice(id: id, name: name, icon: icon, total: v.0, count: v.1, percent: grand > 0 ? v.0 / grand * 100 : 0)
        }.sorted { $0.total > $1.total }
    }

    /// Transactions whose category is `categoryId` or one of its subcategories.
    public static func transactions(_ txs: [Transaction], inCategory categoryId: String, _ s: Snapshot) -> [Transaction] {
        txs.filter { $0.categoryId == categoryId || s.categories[$0.categoryId ?? ""]?.parentId == categoryId }
    }

    /// How a transaction changes an account's balance.
    public static func delta(_ tx: Transaction, for accountId: String) -> Double {
        switch tx.type {
        case .income: tx.accountId == accountId ? tx.amount : 0
        case .expense: tx.accountId == accountId ? -tx.amount : 0
        case .transfer: (tx.toAccountId == accountId ? tx.amount : 0) - (tx.accountId == accountId ? tx.amount : 0)
        }
    }

    /// Current balance of every account (initial balance + all transactions).
    public static func balances(_ s: Snapshot) -> [String: Double] {
        var out = s.accounts.mapValues(\.initialBalance)
        for tx in s.transactions.values {
            switch tx.type {
            case .income: out[tx.accountId, default: 0] += tx.amount
            case .expense: out[tx.accountId, default: 0] -= tx.amount
            case .transfer:
                out[tx.accountId, default: 0] -= tx.amount
                if let to = tx.toAccountId { out[to, default: 0] += tx.amount }
            }
        }
        return out
    }

    public static func balanceSummary(_ s: Snapshot, balances: [String: Double]) -> BalanceSummary {
        var assets = 0.0, liabilities = 0.0
        for a in s.accounts.values where a.includeInTotals {
            let b = balances[a.id] ?? 0
            if b > 0 { assets += b } else { liabilities -= b }
        }
        return BalanceSummary(assets: assets, liabilities: liabilities)
    }

    /// The account's balance right after each of its transactions (by transaction id).
    public static func runningBalances(accountId: String, _ s: Snapshot) -> [String: Double] {
        var balance = s.accounts[accountId]?.initialBalance ?? 0
        var out: [String: Double] = [:]
        let txs = s.transactions.values
            .filter { $0.accountId == accountId || $0.toAccountId == accountId }
            .sorted { sortDescending($1, $0) } // oldest first
        for tx in txs {
            balance += delta(tx, for: accountId)
            out[tx.id] = balance
        }
        return out
    }

    /// Budgets in effect for a month, keyed by category id ("" = Total). A month override wins over the default.
    public static func effectiveBudgets(_ s: Snapshot, month: YearMonth) -> [String: Budget] {
        var out: [String: Budget] = [:]
        for b in s.budgets.values {
            if let m = b.month, m != month.key { continue }
            let key = b.categoryId ?? ""
            if let prev = out[key], prev.month != nil || b.month == nil { continue }
            out[key] = b
        }
        return out
    }

    /// Budget progress for a month: the Total line first, then every top-level expense category
    /// (those without a budget have `budget == 0`).
    public static func budgetLines(_ s: Snapshot, month: YearMonth) -> [BudgetLine] {
        let period = Periods.month(month, startDay: s.monthStartDay)
        let txs = transactions(in: period, s)
        let spentByCat = Dictionary(uniqueKeysWithValues: byCategory(txs, type: .expense, s).map { ($0.id, $0.total) })
        let eff = effectiveBudgets(s, month: month)
        let categoryLines = s.topCategories(.expense).map { c in
            BudgetLine(categoryId: c.id, name: c.name, icon: c.icon, budget: eff[c.id]?.amount ?? 0,
                       spent: spentByCat[c.id] ?? 0, budgetRow: eff[c.id])
        }
        let totalBudget = eff[""]?.amount ?? categoryLines.reduce(0) { $0 + $1.budget }
        return [BudgetLine(categoryId: nil, name: "Total", icon: "", budget: totalBudget, spent: totals(txs).expense, budgetRow: eff[""])]
            + categoryLines
    }

    /// Case-insensitive match on note and description (and category/account names as a convenience).
    public static func matches(_ tx: Transaction, query: String, _ s: Snapshot) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let fields = [tx.note, tx.memo, s.categories[tx.categoryId ?? ""]?.name ?? "", s.rootCategory(tx.categoryId)?.name ?? "",
                      s.accounts[tx.accountId]?.name ?? ""]
        return fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Income/expense totals for each of the `count` months ending at `end` (oldest first).
    public static func monthlyTrend(_ s: Snapshot, endingAt end: YearMonth, count: Int, categoryId: String? = nil) -> [(YearMonth, Totals)] {
        let months = (0..<count).map { end.adding(months: $0 - count + 1) }
        let periods = months.map { Periods.month($0, startDay: s.monthStartDay) }
        var sums = Array(repeating: Totals(), count: count)
        guard let first = periods.first, let last = periods.last else { return [] }
        for tx in s.transactions.values where tx.type != .transfer && tx.day >= first.from && tx.day <= last.to {
            if let categoryId, tx.categoryId != categoryId && s.categories[tx.categoryId ?? ""]?.parentId != categoryId { continue }
            guard let i = periods.firstIndex(where: { $0.contains(tx.date) }) else { continue }
            if tx.type == .income { sums[i].income += tx.amount } else { sums[i].expense += tx.amount }
        }
        return Array(zip(months, sums))
    }
}
