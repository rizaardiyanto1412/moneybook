import AppKit
import MoneybookCore
import SwiftUI

struct TransactionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.snapshot
        let period = model.navigatesByYear ? model.yearPeriod : model.period
        let txs = Ledger.transactions(in: period, s).filter { Ledger.matches($0, query: model.searchText, s) }
        let wide = model.transactionsMode == .calendar

        VStack(spacing: 0) {
            TotalsStrip(totals: Ledger.totals(txs), currency: model.currency)
                .readableWidth(wide ? .infinity : Surface.contentWidth)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            Group {
                switch model.transactionsMode {
                case .daily: DailyList(transactions: txs)
                case .calendar: CalendarMonthView(transactions: txs, period: period)
                case .monthly: MonthlyView(transactions: txs)
                case .summary: SummaryView(transactions: txs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .pageBackground()
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.transactionsMode) {
                    ForEach(TransactionsMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Daily (⌘1) · Calendar (⌘2) · Monthly (⌘3) · Summary (⌘4)")
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search notes")
    }
}

// MARK: - Daily

struct DailyList: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    @UIState private var selection = Set<String>()
    @UIState private var pendingDelete: [String] = []

    var body: some View {
        let groups = Ledger.groupByDay(transactions)
        if groups.isEmpty {
            EmptyStateView(title: model.searchText.isEmpty ? "No transactions" : "No matches",
                           symbol: model.searchText.isEmpty ? "tray" : "magnifyingglass",
                           message: model.searchText.isEmpty ? "Press ⌘N to add one, or ask your AI assistant." : "Nothing matches \u{201C}\(model.searchText)\u{201D} in this period.")
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { g in
                        VStack(spacing: 0) {
                            DayHeader(day: g.day, totals: g.totals)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            Divider()
                            TransactionCardRows(transactions: g.transactions, selection: $selection, pendingDelete: $pendingDelete)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
                        .card(padding: 0)
                    }
                }
                .readableWidth()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .transactionKeyboard(selection: $selection, pendingDelete: $pendingDelete)
        }
    }
}

/// Rows separated by inset dividers, for use inside a card.
struct TransactionCardRows: View {
    var transactions: [Transaction]
    @Binding var selection: Set<String>
    @Binding var pendingDelete: [String]
    var trailingDetail: (Transaction) -> String? = { _ in nil }
    var showDate = false

    var body: some View {
        ForEach(Array(transactions.enumerated()), id: \.element.id) { i, tx in
            if i > 0 { Divider().padding(.leading, 62) }
            CardTransactionRow(tx: tx, selection: $selection, pendingDelete: $pendingDelete, trailingDetail: trailingDetail(tx), showDate: showDate)
        }
    }
}

/// A transaction row that highlights on hover; click selects (⌘-click toggles), double-click edits.
struct CardTransactionRow: View {
    @Environment(AppModel.self) private var model
    var tx: Transaction
    @Binding var selection: Set<String>
    @Binding var pendingDelete: [String]
    var trailingDetail: String?
    var showDate = false
    @UIState private var hovering = false

    var body: some View {
        let selected = selection.contains(tx.id)
        TransactionRow(tx: tx, trailingDetail: trailingDetail, showDate: showDate)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.14) : hovering ? Surface.hover : Color.clear)
            .onHover { hovering = $0 }
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2 {
                    model.edit(tx.id)
                } else if NSEvent.modifierFlags.contains(.command) {
                    selection.formSymmetricDifference([tx.id])
                } else {
                    selection = [tx.id]
                }
            }
            .contextMenu {
                let ids = selected && selection.count > 1 ? Array(selection) : [tx.id]
                if ids.count == 1 {
                    Button("Edit…") { model.edit(tx.id) }
                    Button("Duplicate") { model.duplicate(tx.id) }
                    Divider()
                }
                Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Transactions", role: .destructive) { pendingDelete = ids }
            }
    }
}

extension View {
    /// Double-click edits; context menu and Delete key delete (after confirmation). For `List`s.
    func transactionContextMenu(selection: Binding<Set<String>>, pendingDelete: Binding<[String]>) -> some View {
        modifier(TransactionActions(selection: selection, pendingDelete: pendingDelete))
    }

    /// Delete/Return/Escape handling for a container of `CardTransactionRow`s.
    func transactionKeyboard(selection: Binding<Set<String>>, pendingDelete: Binding<[String]>) -> some View {
        modifier(TransactionKeyboard(selection: selection, pendingDelete: pendingDelete))
    }

    fileprivate func deleteConfirmation(selection: Binding<Set<String>>, pendingDelete: Binding<[String]>) -> some View {
        modifier(DeleteConfirmation(selection: selection, pendingDelete: pendingDelete))
    }
}

private struct TransactionKeyboard: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<String>
    @Binding var pendingDelete: [String]
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .simultaneousGesture(TapGesture().onEnded { focused = true })
            .onDeleteCommand { if !selection.isEmpty { pendingDelete = Array(selection) } }
            .onKeyPress(.return) {
                guard selection.count == 1, let id = selection.first else { return .ignored }
                model.edit(id)
                return .handled
            }
            .onKeyPress(.escape) {
                guard !selection.isEmpty else { return .ignored }
                selection = []
                return .handled
            }
            .deleteConfirmation(selection: $selection, pendingDelete: $pendingDelete)
    }
}

private struct TransactionActions: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<String>
    @Binding var pendingDelete: [String]

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Edit…") { model.edit(id) }
                    Button("Duplicate") { model.duplicate(id) }
                    Divider()
                }
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Transactions", role: .destructive) { pendingDelete = Array(ids) }
                }
            } primaryAction: { ids in
                if let id = ids.first { model.edit(id) }
            }
            .onDeleteCommand { if !selection.isEmpty { pendingDelete = Array(selection) } }
            .onKeyPress(.return) {
                guard selection.count == 1, let id = selection.first else { return .ignored }
                model.edit(id)
                return .handled
            }
            .deleteConfirmation(selection: $selection, pendingDelete: $pendingDelete)
    }
}

private struct DeleteConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<String>
    @Binding var pendingDelete: [String]

    func body(content: Content) -> some View {
        content
            .confirmationDialog(pendingDelete.count == 1 ? "Delete this transaction?" : "Delete \(pendingDelete.count) transactions?",
                                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
                Button("Delete", role: .destructive) {
                    let ids = pendingDelete
                    pendingDelete = []
                    selection.subtract(ids)
                    Task { await model.delete(transactionIds: ids) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = [] }
            } message: {
                Text("This can't be undone.")
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

// MARK: - Calendar

struct CalendarMonthView: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    var period: Period
    @UIState private var selectedDay: String?
    @UIState private var selection = Set<String>()
    @UIState private var pendingDelete: [String] = []

    var body: some View {
        let s = model.snapshot
        let byDay = Ledger.totalsByDay(transactions)
        let cells = Periods.calendarGrid(period, firstWeekday: s.firstWeekday)
        let day = selectedDay.flatMap { period.contains($0) ? $0 : nil } ?? defaultDay
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(Periods.weekdaySymbols(firstWeekday: s.firstWeekday).enumerated()), id: \.offset) { _, sym in
                        Text(sym).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                let rows = cells.count / 7
                GeometryReader { geo in
                    let h = max((geo.size.height - CGFloat(rows - 1) * 4) / CGFloat(max(rows, 1)), 44)
                    VStack(spacing: 4) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { c in
                                    cell(cells[r * 7 + c], byDay: byDay, selected: day).frame(height: h)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(minWidth: 420)

            VStack(alignment: .leading, spacing: 0) {
                let dayTxs = transactions.filter { $0.day == day }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Fmt.longDate(day)).font(.title3.weight(.semibold))
                        let t = Ledger.totals(dayTxs)
                        HStack(spacing: 10) {
                            Text(model.money(t.income)).foregroundStyle(Palette.income)
                            Text(model.money(t.expense)).foregroundStyle(Palette.expense)
                        }
                        .font(.money(12, weight: .medium))
                    }
                    Spacer()
                    Button { model.newTransaction(day: day) } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .help("Add a transaction on this day")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                if dayTxs.isEmpty {
                    EmptyStateView(title: "No transactions", symbol: "calendar", message: "Nothing recorded on this day.")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            TransactionCardRows(transactions: dayTxs, selection: $selection, pendingDelete: $pendingDelete)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
                        .card(padding: 0)
                        .padding(12)
                    }
                    .transactionKeyboard(selection: $selection, pendingDelete: $pendingDelete)
                }
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Surface.card.opacity(0.5))
            .overlay(alignment: .leading) { Divider() }
        }
    }

    private var defaultDay: String {
        let today = Periods.today()
        return period.contains(today) ? today : period.from
    }

    @ViewBuilder
    private func cell(_ day: String?, byDay: [String: Totals], selected: String) -> some View {
        if let day {
            let t = byDay[day]
            let isToday = day == Periods.today()
            let isSelected = day == selected
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(Fmt.dayNumber(day))
                        .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isToday ? Color.white : dayColor(day))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(isToday ? Color.accentColor : .clear, in: Circle())
                    Spacer()
                }
                Spacer(minLength: 0)
                if let t, t.income > 0 {
                    Text(model.money(t.income, symbol: false)).foregroundStyle(Palette.income)
                }
                if let t, t.expense > 0 {
                    Text(model.money(t.expense, symbol: false)).foregroundStyle(Palette.expense)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Surface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.newTransaction(day: day) }
            .onTapGesture { selectedDay = day }
            .help(t.map { "Income \(model.money($0.income)) · Expenses \(model.money($0.expense))" } ?? "")
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    private func dayColor(_ day: String) -> Color {
        switch Periods.weekday(day) {
        case 1: Palette.expense.opacity(0.85)
        case 7: Palette.income.opacity(0.85)
        default: .primary
        }
    }
}

// MARK: - Monthly

struct MonthlyView: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    @UIState private var expanded = Set<String>()

    var body: some View {
        let s = model.snapshot
        let months = (1...12).map { YearMonth(year: model.month.year, month: $0) }.filter { $0 <= model.currentMonth }.reversed()
        if months.isEmpty {
            EmptyStateView(title: "Nothing yet", symbol: "calendar", message: "\(String(model.month.year)) hasn't started.")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        columnTitle("Income"); columnTitle("Expenses"); columnTitle("Total")
                    }
                    .padding(.horizontal, 44)
                    ForEach(Array(months)) { ym in
                        monthCard(ym, s: s)
                    }
                }
                .readableWidth()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onAppear { expanded.insert(model.currentMonth.key) }
        }
    }

    private func monthCard(_ ym: YearMonth, s: Snapshot) -> some View {
        let p = Periods.month(ym, startDay: s.monthStartDay)
        let monthTxs = transactions.filter { p.contains($0.date) }
        let isOpen = expanded.contains(ym.key)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 14)
                totalsRow(title: Text(Fmt.monthName(ym)).font(.headline), subtitle: Fmt.range(p),
                          totals: Ledger.totals(monthTxs), highlight: ym == model.currentMonth)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2 {
                    model.month = ym
                    model.transactionsMode = .daily
                } else {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isOpen { expanded.remove(ym.key) } else { expanded.insert(ym.key) }
                    }
                }
            }
            .help("Double-click to open \(Fmt.monthTitle(ym)) in Daily view")
            if isOpen {
                Divider()
                ForEach(Periods.weeks(in: p, firstWeekday: s.firstWeekday), id: \.from) { w in
                    let wt = Ledger.totals(monthTxs.filter { w.contains($0.date) })
                    totalsRow(title: Text(Fmt.range(w)).font(.callout), subtitle: nil, totals: wt, highlight: w.contains(Periods.today()))
                        .padding(.leading, 40)
                        .padding(.trailing, 16)
                        .padding(.vertical, 7)
                        .background(w.contains(Periods.today()) ? Color.accentColor.opacity(0.07) : .clear)
                }
                .padding(.vertical, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
        .card(padding: 0)
    }

    private func columnTitle(_ t: String) -> some View {
        Text(t).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
    }

    private func totalsRow(title: Text, subtitle: String?, totals: Totals, highlight: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                title.foregroundStyle(highlight ? Color.accentColor : .primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Group {
                Text(model.money(totals.income)).foregroundStyle(Palette.income).frame(width: 120, alignment: .trailing)
                Text(model.money(totals.expense)).foregroundStyle(Palette.expense).frame(width: 120, alignment: .trailing)
                Text(model.money(totals.total)).frame(width: 120, alignment: .trailing)
            }
            .font(.money(13, weight: .medium))
        }
    }
}

// MARK: - Summary

struct SummaryView: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]

    var body: some View {
        let s = model.snapshot
        let lines = Ledger.budgetLines(s, month: model.month)
        let budgeted = lines.filter { $0.budget > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    accountsCard(s)
                    topCategoriesCard(s)
                }
                budgetCard(budgeted)
            }
            .readableWidth()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func accountsCard(_ s: Snapshot) -> some View {
        let expense = Ledger.totals(transactions).expense
        let prevPeriod = Periods.month(model.month.adding(months: -1), startDay: s.monthStartDay)
        let prevExpense = Ledger.totals(Ledger.transactions(in: prevPeriod, s)).expense
        let byGroup = Dictionary(grouping: transactions.filter { $0.type == .expense }) { s.accounts[$0.accountId]?.groupId ?? "" }
            .map { (name: s.groups[$0.key]?.name ?? "Other", total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        let byAccount = Dictionary(grouping: transactions.filter { $0.type != .transfer }, by: \.accountId)
        let rows = byAccount.map { (id, txs) in (id: id, name: s.accounts[id]?.name ?? "Deleted account", totals: Ledger.totals(txs)) }
            .sorted { $0.totals.expense > $1.totals.expense }
        return VStack(alignment: .leading, spacing: 10) {
            Label("Accounts", systemImage: "creditcard").font(.headline)
            if model.searchText.isEmpty {
                HStack {
                    Text("Compared expenses")
                    Spacer()
                    if prevExpense > 0 {
                        let change = (expense - prevExpense) / prevExpense * 100
                        Text(String(format: "%@%.0f%%", change >= 0 ? "+" : "", change))
                            .foregroundStyle(change > 0 ? Palette.expense : Palette.income)
                        Text("vs \(Fmt.monthName(model.month.adding(months: -1), short: true)) \(model.money(prevExpense))").foregroundStyle(.secondary)
                    } else {
                        Text("No expenses last month").foregroundStyle(.secondary)
                    }
                }
                .font(.callout.monospacedDigit())
                ForEach(byGroup, id: \.name) { g in
                    HStack {
                        Text("\(g.name) expenses")
                        Spacer()
                        Text(model.money(g.total)).foregroundStyle(Palette.expense)
                    }
                    .font(.callout.monospacedDigit())
                }
                Divider()
            }
            if rows.isEmpty { Text("No activity").foregroundStyle(.secondary) }
            ForEach(rows, id: \.id) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    if r.totals.income > 0 { Text(model.money(r.totals.income)).foregroundStyle(Palette.income) }
                    Text(model.money(r.totals.expense)).foregroundStyle(Palette.expense).frame(minWidth: 90, alignment: .trailing)
                }
                .font(.callout.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func topCategoriesCard(_ s: Snapshot) -> some View {
        let slices = Array(Ledger.byCategory(transactions, type: .expense, s).prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            Label("Top spending", systemImage: "chart.bar").font(.headline)
            if slices.isEmpty { Text("No expenses").foregroundStyle(.secondary) }
            ForEach(Array(slices.enumerated()), id: \.element.id) { i, c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(c.icon) \(c.name)")
                        Spacer()
                        Text(model.money(c.total)).monospacedDigit()
                        Text(String(format: "%.0f%%", c.percent)).foregroundStyle(.secondary).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    .font(.callout)
                    ProgressBar(ratio: c.percent / 100, tint: Palette.chartColor(i), height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func budgetCard(_ lines: [BudgetLine]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Budget", systemImage: "gauge.with.dots.needle.33percent").font(.headline)
                Spacer()
                Button("Open Budget") { model.section = .budget }.buttonStyle(.link)
            }
            if lines.isEmpty {
                Text("No budgets set for \(Fmt.monthTitle(model.month)).").foregroundStyle(.secondary)
            }
            ForEach(lines) { BudgetRow(line: $0, compact: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
