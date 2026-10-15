import AppKit
import MoneybookCore
import SwiftUI

// Building blocks that mirror the web app's desktop layout (web/styles.css), so both look the same.

/// `.hdr-bar`: centred title with icon buttons on either side.
struct MBHeader<Left: View, Right: View>: View {
    var title: String
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1).padding(.horizontal, 150)
            HStack(spacing: 0) {
                left
                Spacer(minLength: 0)
                right
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 54)
        .foregroundStyle(MB.fg)
    }
}

extension MBHeader where Left == EmptyView, Right == EmptyView {
    init(title: String) { self.init(title: title, left: { EmptyView() }, right: { EmptyView() }) }
}

/// Header for a side panel: back chevron (with an optional label), title, optional right side.
struct DrawerHeader<Right: View>: View {
    @Environment(AppModel.self) private var model
    var title: String
    var back: String = ""
    var onBack: (() -> Void)?
    @ViewBuilder var right: Right

    var body: some View {
        MBHeader(title: title) {
            Button { (onBack ?? { model.closeDrawer() })() } label: {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .regular))
                    if !back.isEmpty { Text(back).font(.system(size: 16)) }
                }
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back (Esc)")
        } right: {
            right
        }
    }
}

extension DrawerHeader where Right == EmptyView {
    init(title: String, back: String = "", onBack: (() -> Void)? = nil) {
        self.init(title: title, back: back, onBack: onBack, right: { EmptyView() })
    }
}

/// `.icon-btn`: a round hover target around an SF Symbol.
struct IconButton: View {
    var symbol: String
    var help: String
    var size: CGFloat = 18
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(MB.fg)
                .frame(width: 40, height: 40)
                .background(hover ? MB.bg2 : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Text button in a header (accent coloured), e.g. "Edit".
struct HeaderTextButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(MB.accent)
                .padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `.month-sw`: ‹ Oct 2026 › across the full width.
struct MonthSwitcher: View {
    var label: String
    var onPrev: () -> Void
    var onNext: () -> Void
    var onLabel: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", help: "Previous (⌘[)", size: 17, action: onPrev)
            Spacer()
            Text(label)
                .font(.system(size: 16.5))
                .monospacedDigit()
                .foregroundStyle(MB.fg)
                .contentShape(Rectangle())
                .onTapGesture { onLabel?() }
                .help(onLabel == nil ? "" : "Back to today")
            Spacer()
            IconButton(symbol: "chevron.right", help: "Next (⌘])", size: 17, action: onNext)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}

/// `.subtabs`: equal-width text tabs with a coral underline.
struct SubTabs<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { value, label in
                let on = value == selection
                Button { withAnimation(.easeOut(duration: 0.25)) { selection = value } } label: {
                    Text(label)
                        .font(.system(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? MB.fg : MB.fg3)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(MB.accent).frame(height: 3).scaleEffect(x: on ? 1 : 0, anchor: .center)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { MB.line.frame(height: 1) }
    }
}

/// `.strip`: three centred label / number columns.
struct Strip: View {
    @Environment(AppModel.self) private var model
    var items: [(String, Double, Color)]
    /// Columns that hold counts rather than amounts.
    var counts: Set<Int> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(spacing: 1) {
                    Text(item.0).font(.system(size: 14)).foregroundStyle(MB.fgNote)
                    Text(counts.contains(i) ? String(Int(item.1)) : model.money(item.1, symbol: false))
                        .font(.system(size: 16.5).monospacedDigit())
                        .foregroundStyle(item.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(MB.chrome)
        .overlay(alignment: .bottom) { MB.line.frame(height: 1) }
    }

    /// Income / Exp. / Total for a list of transactions.
    static func incExpTotal(_ txs: [Transaction]) -> Strip {
        let t = Ledger.totals(txs)
        return Strip(items: [("Income", t.income, MB.inc), ("Exp.", t.expense, MB.exp), ("Total", t.total, MB.fg)])
    }
}

/// Grey background on hover plus a pointer cursor, for clickable rows.
struct RowHover: ViewModifier {
    @UIState private var hover = false
    func body(content: Content) -> some View {
        content
            .background(hover ? MB.bg2 : .clear)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

extension View {
    func rowHover() -> some View { modifier(RowHover()) }
    /// Hairline under a row.
    func bottomLine() -> some View { overlay(alignment: .bottom) { MB.line.frame(height: 1) } }
}

/// `.empty`: centred grey message with a big emoji.
struct MBEmpty: View {
    var text: String
    var emoji = "🧾"
    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 40))
            Text(text).font(.system(size: 15)).foregroundStyle(MB.fg3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
    }
}

/// `.btn`: full-height rounded button, solid (primary) or outlined (ghost).
struct MBButton: View {
    var title: String
    var symbol: String?
    var primary = false
    var tint: Color = MB.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15)) }
                Text(title).font(.system(size: primary ? 15 : 14, weight: primary ? .medium : .regular))
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .foregroundStyle(primary ? Color.white : MB.fg)
            .background(primary ? tint : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay { if !primary { RoundedRectangle(cornerRadius: 8).strokeBorder(MB.fg3, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day-grouped transaction list (components.js dayList / txRow)

struct DayList: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    /// In an account's ledger transfers count as money in or out of that account.
    var accountId: String?
    /// Clicking a day header starts a new entry on that day.
    var addable = false
    var emptyText = "No transactions"
    /// Width of the category column (150 on the main list, 96 in side panels).
    var categoryWidth: CGFloat = 150
    @UIState private var pendingDelete: [String] = []

    var body: some View {
        let groups = Ledger.groupByDay(transactions)
        if groups.isEmpty {
            MBEmpty(text: emptyText)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { MB.bg2.frame(height: 8).bottomLine() }
                    DayHeaderRow(day: g.day, totals: dayTotals(g), addable: addable, accountId: accountId)
                    ForEach(g.transactions) { tx in
                        TxRow(tx: tx, accountId: accountId, categoryWidth: categoryWidth, pendingDelete: $pendingDelete)
                    }
                    MB.line.frame(height: 1)
                }
            }
            .confirmationDialog(pendingDelete.count == 1 ? "Delete this transaction?" : "Delete \(pendingDelete.count) transactions?",
                                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
                Button("Delete", role: .destructive) {
                    let ids = pendingDelete
                    pendingDelete = []
                    Task { await model.delete(transactionIds: ids) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = [] }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func dayTotals(_ g: DayGroup) -> Totals {
        guard let accountId else { return g.totals }
        var t = g.totals
        for tx in g.transactions where tx.type == .transfer {
            if tx.toAccountId == accountId { t.income += tx.amount } else { t.expense += tx.amount }
        }
        return t
    }
}

/// `.day-h`: big day number, weekday chip, day's income and expense.
struct DayHeaderRow: View {
    @Environment(AppModel.self) private var model
    var day: String
    var totals: Totals
    var addable = false
    var accountId: String?
    @UIState private var hover = false

    var body: some View {
        let w = Periods.weekday(day)
        HStack(spacing: 8) {
            Text(Fmt.dayNumber(day))
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .frame(minWidth: 26, alignment: .leading)
            Text(Fmt.weekday(day))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(w == 1 ? MB.sun : w == 7 ? MB.sat : MB.chip, in: RoundedRectangle(cornerRadius: 3))
            Spacer()
            Text(model.money(totals.income)).foregroundStyle(MB.inc).frame(minWidth: 84, alignment: .trailing)
            Text(model.money(totals.expense)).foregroundStyle(MB.exp).frame(minWidth: 100, alignment: .trailing)
        }
        .font(.system(size: 15).monospacedDigit())
        .foregroundStyle(MB.fg)
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
        .frame(minHeight: 36)
        .background(addable && hover ? MB.bg2 : .clear)
        .bottomLine()
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if addable { model.newTransaction(day: day, accountId: accountId) } }
        .help(addable ? "Add a transaction on this day" : "")
    }
}

/// `.tx`: category column, note over account, amount.
struct TxRow: View {
    @Environment(AppModel.self) private var model
    var tx: Transaction
    var accountId: String?
    var categoryWidth: CGFloat = 150
    @Binding var pendingDelete: [String]

    var body: some View {
        let s = model.snapshot
        let cat = s.categories[tx.categoryId ?? ""]
        let root = s.rootCategory(tx.categoryId)
        let acc = s.accounts[tx.accountId]?.name ?? "?"
        let accLine = tx.type == .transfer ? "\(acc) → \(s.accounts[tx.toAccountId ?? ""]?.name ?? "?")" : acc
        let title = !tx.note.isEmpty ? tx.note : tx.type == .transfer ? accLine : ""
        let second = !tx.note.isEmpty || tx.type != .transfer ? accLine : ""
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tx.type == .transfer ? "Transfer" : (root ?? cat)?.name ?? "Uncategorized").lineLimit(1)
                if tx.type != .transfer, let cat, let root, cat.id != root.id { Text(cat.name).lineLimit(1) }
            }
            .font(.system(size: 13.5))
            .foregroundStyle(MB.fg3)
            .frame(width: categoryWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if !title.isEmpty {
                    HStack(spacing: 4) {
                        Text(title).font(.system(size: 16)).foregroundStyle(MB.fgNote).lineLimit(1)
                        if tx.isAI { Text("✦").font(.system(size: 11)).foregroundStyle(Palette.ai).help("Added by AI") }
                        if tx.receipt != nil { Text("📎").font(.system(size: 12)).opacity(0.7).help("Has a receipt") }
                    }
                }
                if !second.isEmpty { Text(second).font(.system(size: 13.5)).foregroundStyle(MB.fg3).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text(model.money(tx.amount))
                .font(.system(size: 15.5).monospacedDigit())
                .foregroundStyle(amountColor)
                .lineLimit(1)
        }
        .padding(.horizontal, categoryWidth < 120 ? 18 : 24)
        .padding(.vertical, categoryWidth < 120 ? 9 : 10)
        .frame(minHeight: 47)
        .rowHover()
        .onTapGesture { model.edit(tx.id) }
        .contextMenu {
            Button("Edit…") { model.edit(tx.id) }
            Button("Duplicate") { model.duplicate(tx.id) }
            Divider()
            Button("Delete…", role: .destructive) { pendingDelete = [tx.id] }
        }
    }

    private var amountColor: Color {
        switch tx.type {
        case .income: MB.inc
        case .expense: MB.exp
        case .transfer:
            if let accountId { tx.toAccountId == accountId ? MB.inc : MB.exp } else { MB.xfer }
        }
    }
}

extension AppModel {
    func duplicate(_ id: String) {
        guard let t = snapshot.transactions[id] else { return }
        var d = TransactionDraft()
        d.type = t.type; d.amount = t.amount; d.accountId = t.accountId; d.toAccountId = t.toAccountId
        d.categoryId = t.categoryId; d.note = t.note; d.memo = t.memo
        d.date = Periods.parseStamp(t.date) ?? Date()
        Task {
            do { try await save(d) } catch { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Grouped cards (.grouped / .card / .row)

struct MBCard<Content: View>: View {
    var title: String?
    var link: (String, () -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let link {
                        Button(link.0, action: link.1).buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(MB.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
            content
        }
        .background(MB.bg, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// `.row`: label, value, optional chevron; hairline between rows.
struct MBRow: View {
    var label: String
    var value: String = ""
    var valueColor: Color = MB.fg2
    var sub: String?
    var emoji: String?
    var chevron = false
    var last = false

    var body: some View {
        HStack(spacing: 12) {
            if let emoji { Text(emoji).font(.system(size: 20)).frame(width: 28) }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).lineLimit(1)
                if let sub { Text(sub).font(.system(size: 12)).foregroundStyle(MB.fg2).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text(value).foregroundStyle(valueColor).monospacedDigit().lineLimit(1)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(MB.fg3) }
        }
        .font(.system(size: 15))
        .foregroundStyle(MB.fg)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { if !last { MB.line.frame(height: 1) } }
    }
}

/// One budget line (components.js budgetBar).
struct BudgetBar: View {
    @Environment(AppModel.self) private var model
    var line: BudgetLine
    var last = false

    var body: some View {
        let pct = line.ratio * 100
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(line.categoryId == nil ? "Total budget" : line.name).font(.system(size: 14))
                Spacer()
                Text("\(model.money(line.spent)) / \(model.money(line.budget))").font(.system(size: 13).monospacedDigit()).foregroundStyle(MB.fg2)
            }
            .padding(.bottom, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MB.fg3.opacity(0.25))
                    Capsule().fill(pct > 100 ? MB.exp : pct > 85 ? Color(red: 0.96, green: 0.65, blue: 0.14) : MB.sat)
                        .frame(width: geo.size.width * min(max(line.ratio, 0), 1))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(Int(pct.rounded()))%")
                Spacer()
                Text(line.remaining < 0 ? "Over by \(model.money(-line.remaining))" : "\(model.money(line.remaining)) left")
                    .foregroundStyle(line.remaining < 0 ? MB.exp : MB.fg2)
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(MB.fg2)
            .padding(.top, 5)
        }
        .foregroundStyle(MB.fg)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { if !last { MB.line.frame(height: 1) } }
    }
}
