import MoneybookCore
import SwiftUI

/// One transaction like Money Manager: category column (name over subcategory), note over account, amount.
struct TxRow: View {
    @Environment(AppModel.self) private var model
    var tx: Transaction
    /// In an account's ledger, transfers are coloured as money in or out of that account.
    var accountId: String?
    /// The account's balance right after this transaction, shown under the amount in an account's ledger.
    var balance: Double?

    var body: some View {
        let s = model.snapshot
        let cat = s.categories[tx.categoryId ?? ""]
        let root = s.rootCategory(tx.categoryId)
        let sub = root != nil && cat != nil && root!.id != cat!.id ? cat!.name : nil
        let acc = s.accounts[tx.accountId]?.name ?? "?"
        let accLine = tx.type == .transfer ? "\(acc) → \(s.accounts[tx.toAccountId ?? ""]?.name ?? "?")" : acc
        let catName = tx.type == .transfer ? "Transfer" : (root?.name ?? cat?.name ?? "")
        let title = !tx.note.isEmpty ? tx.note : tx.type == .transfer ? accLine : ""
        let second = !tx.note.isEmpty || tx.type != .transfer ? accLine : ""
        Button { model.edit(tx.id) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(catName).lineLimit(1)
                    if let sub, tx.type != .transfer { Text(sub).lineLimit(1) }
                }
                .font(.system(size: 13))
                .foregroundStyle(MM.fg3)
                .frame(width: 74, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    if !title.isEmpty {
                        HStack(spacing: 0) {
                            Text(title).lineLimit(1)
                            if tx.isAI { Text(" ✦").font(.system(size: 11)).foregroundStyle(MM.ai) }
                            if tx.receipt != nil { Text(" 📎").font(.system(size: 12)).opacity(0.7) }
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(MM.fgNote)
                    }
                    if !second.isEmpty {
                        Text(second).font(.system(size: 13)).foregroundStyle(MM.fg3).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.money(tx.amount, model.currency))
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(amountColor)
                    if let balance {
                        Text(Fmt.num(balance, model.currency))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(MM.fg3)
                    }
                }
                .lineLimit(1)
                .layoutPriority(1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private var amountColor: Color {
        if tx.type == .transfer, let accountId { return tx.toAccountId == accountId ? MM.inc : MM.exp }
        return MM.color(tx.type)
    }
}

/// Day header: "13", "2026/10" over a weekday chip, then the day's income and expenses.
struct DayHeader: View {
    @Environment(AppModel.self) private var model
    var day: String
    var income: Double
    var expense: Double

    var body: some View {
        let p = Fmt.ymd(day)
        let w = Fmt.weekday(day)
        HStack(spacing: 7) {
            Text("\(p.d)").font(.system(size: 26, weight: .semibold).monospacedDigit()).tracking(-0.3).frame(minWidth: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%d/%02d", p.y, p.m)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(MM.fg2)
                Text(Fmt.dow[w])
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(w == 0 ? MM.sun : w == 6 ? MM.sat : MM.chip, in: RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            amount(income, MM.inc)
            amount(expense, MM.exp)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { Line() }
    }

    private func amount(_ v: Double, _ c: Color) -> some View {
        Text(Fmt.money(v, model.currency)).font(.system(size: 15).monospacedDigit()).foregroundStyle(c)
            .lineLimit(1).minimumScaleFactor(0.7).frame(minWidth: 84, alignment: .trailing)
    }
}

/// Day-grouped list with grey bands between days (web `dayList`).
struct DayList: View {
    @Environment(AppModel.self) private var model
    var txs: [Transaction]
    var accountId: String?
    var emptyText = "No transactions"

    var body: some View {
        if txs.isEmpty {
            EmptyText(emoji: "🧾", text: emptyText)
        } else {
            let balances = accountId.map { Ledger.runningBalances(accountId: $0, model.snapshot) }
            LazyVStack(spacing: 0) {
                ForEach(Array(Ledger.groupByDay(txs).enumerated()), id: \.element.id) { i, g in
                    if i > 0 { MM.bg2.frame(height: 10) }
                    let t = totals(g.transactions)
                    VStack(spacing: 0) {
                        DayHeader(day: g.day, income: t.income, expense: t.expense)
                        ForEach(Array(g.transactions.enumerated()), id: \.element.id) { j, tx in
                            TxRow(tx: tx, accountId: accountId, balance: balances?[tx.id])
                            if j < g.transactions.count - 1 { Line() }
                        }
                    }
                    .background(MM.bg)
                    .overlay(alignment: .bottom) { Line() }
                }
            }
        }
    }

    /// In an account's ledger, transfers count as money in / out.
    private func totals(_ rows: [Transaction]) -> Totals {
        var t = Ledger.totals(rows)
        if let accountId {
            for tx in rows where tx.type == .transfer {
                if tx.toAccountId == accountId { t.income += tx.amount } else { t.expense += tx.amount }
            }
        }
        return t
    }
}

/// One budget line: name, spent / budget, bar, % and what's left (web `budgetBar`).
struct BudgetBar: View {
    @Environment(AppModel.self) private var model
    var line: BudgetLine
    var title: String?
    var compactBar = false

    var body: some View {
        let pct = line.ratio * 100
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title ?? (line.categoryId == nil ? "Total budget" : line.name)).font(.system(size: 14)).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Fmt.money(line.spent, model.currency)) / \(Fmt.money(line.budget, model.currency))")
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(MM.fg2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.bottom, 6)
            BarView(percent: pct)
            HStack {
                Text(verbatim: "\(Int(pct.rounded()))%")
                Spacer()
                Text(line.remaining < 0 ? "Over by \(Fmt.money(-line.remaining, model.currency))" : "\(Fmt.money(line.remaining, model.currency)) left")
                    .foregroundStyle(line.remaining < 0 ? MM.exp : MM.fg2)
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(MM.fg2)
            .padding(.top, 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

struct BarView: View {
    var percent: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MM.fg3.opacity(0.25))
                Capsule().fill(percent > 100 ? MM.exp : percent > 85 ? MM.warn : MM.sat)
                    .frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 8)
    }
}

extension Ledger {
    /// Budgets that are set for the month, like the web's `budgetStatus`: the Total (if set) first.
    static func budgetStatus(_ s: Snapshot, month: YearMonth) -> [BudgetLine] {
        let lines = budgetLines(s, month: month)
        guard let total = lines.first else { return [] }
        return (total.budgetRow != nil ? [total] : []) + lines.dropFirst().filter { $0.budget > 0 }
    }
}
