import MoneybookCore
import SwiftUI

enum TransMode: String, CaseIterable {
    case daily, calendar, weekly, monthly, summary
    var label: String { rawValue.capitalized }
}

/// Trans. tab: Daily / Calendar / Weekly / Monthly / Summary (web/js/views/trans.js).
struct TransactionsTab: View {
    @Environment(AppModel.self) private var model
    @State private var mode = TransMode(rawValue: UserDefaults.standard.string(forKey: "transMode") ?? "") ?? .daily
    @State private var year = Periods.yearMonth(containing: Periods.today()).year
    @State private var daySheet: String?
    @State private var showSearch = false
    @State private var scrollTop = 0
    @State private var listHeight: CGFloat = 600

    var body: some View {
        let s = model.snapshot
        let yearMode = mode == .monthly
        let range = yearMode
            ? Period(from: Periods.month(YearMonth(year: year, month: 1), startDay: s.monthStartDay).from,
                     to: Periods.month(YearMonth(year: year, month: 12), startDay: s.monthStartDay).to)
            : model.period
        let list = Ledger.transactions(in: range, s)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HeaderBar(left: {
                    IconButton(icon: "search", label: "Search") { showSearch = true }
                }, center: { HeaderTitle("Transaction") }, right: {
                    IconButton(icon: "filter", label: "Filter") { showSearch = true }
                })
                MonthSwitcher(label: yearMode ? String(year) : Fmt.monthLabel(model.month), onStep: step, onToday: {
                    model.goToToday()
                    year = model.month.year
                })
                SubTabs(items: TransMode.allCases.map { ($0, $0.label) }, selection: $mode)
                Strip(items: Strip.incExpTotal(Ledger.totals(list)))
            }
            .background(MM.chrome)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        content(list: list, range: range)
                    }
                    .padding(.bottom, mode == .calendar ? 0 : 90)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                .background(mode == .summary ? MM.bg2 : MM.bg)
                .onChange(of: scrollTop) { proxy.scrollTo("top") }
                .refreshable { await model.sync() }
            }
            .simultaneousGesture(swipe)
        }
        .overlay(alignment: .bottomTrailing) { Fab { model.newTransaction(day: newEntryDay) } }
        .onChange(of: mode) { old, new in
            UserDefaults.standard.set(new.rawValue, forKey: "transMode")
            if new == .monthly { year = model.month.year }
            scrollTop += 1
        }
        .sheet(item: Binding(get: { daySheet.map(DayKey.init) }, set: { daySheet = $0?.id })) { DaySheet(day: $0.id) }
        .navigationDestination(isPresented: $showSearch) { SearchPage() }
        .navigationDestination(for: WeekRoute.self) { WeekPage(start: $0.start) }
    }

    @ViewBuilder private func content(list: [Transaction], range: Period) -> some View {
        switch mode {
        case .daily: DayList(txs: list, emptyText: "No transactions in \(Fmt.monthLabel(model.month))")
        case .calendar: CalendarGrid(period: range, txs: list, height: listHeight) { daySheet = $0 }
        case .weekly: WeeklyList(period: range, txs: list)
        case .monthly: MonthlyList(year: year) { ym in
            model.month = ym
            mode = .daily
        }
        case .summary: SummaryView(month: model.month, txs: list)
        }
    }

    private func step(_ d: Int) {
        if mode == .monthly { year += d } else { model.step(d) }
        scrollTop += 1
    }

    /// Horizontal swipe on the list switches months, like the native app.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            let dx = v.translation.width, dy = v.translation.height
            if abs(dx) > 70 && abs(dx) > abs(dy) * 1.8 { step(dx < 0 ? 1 : -1) }
        }
    }

    /// New entries land on today, or the first day of the month being viewed.
    private var newEntryDay: String? {
        model.period.contains(Periods.today()) ? nil : model.period.from
    }
}

private struct DayKey: Identifiable { var id: String }
struct WeekRoute: Hashable { var start: String }

// MARK: - Calendar

struct CalendarGrid: View {
    @Environment(AppModel.self) private var model
    var period: Period
    var txs: [Transaction]
    /// Height available below the strip; the weeks share it (at least 64 pt each).
    var height: CGFloat
    var onDay: (String) -> Void
    @State private var cellHeight: CGFloat = 64

    var body: some View {
        let s = model.snapshot
        let ws = s.firstWeekday - 1 // 0 = Sunday
        let byDay = Ledger.totalsByDay(txs)
        var start = period.from
        while Fmt.weekday(start) != ws { start = Periods.addDays(start, -1) }
        var end = period.to
        while Fmt.weekday(end) != (ws + 6) % 7 { end = Periods.addDays(end, 1) }
        let days = Periods.days(from: start, to: end)
        let today = Periods.today()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let rows = CGFloat(days.count / 7)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let d = (ws + i) % 7
                    Text(Fmt.dow[d]).font(.system(size: 12.5))
                        .foregroundStyle(d == 0 ? MM.sun : d == 6 ? MM.sat : MM.fg2)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
            }
            .background(MM.bg2)
            .overlay(alignment: .bottom) { Line() }
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { i, d in
                    cell(d, col: i % 7, totals: byDay[d], out: d < period.from || d > period.to, today: d == today)
                }
            }
        }
        .onChange(of: height, initial: true) { cellHeight = max(64, floor((height - 22) / rows)) }
        .onChange(of: rows) { cellHeight = max(64, floor((height - 22) / rows)) }
    }

    private func cell(_ d: String, col: Int, totals t: Totals?, out: Bool, today: Bool) -> some View {
        let p = Fmt.ymd(d)
        let w = Fmt.weekday(d)
        let label = p.d == 1 ? String(format: "%02d/01", p.m) : "\(p.d)"
        let c = model.currency
        return Button { onDay(d) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(today ? .white : out ? MM.fg3 : w == 0 ? MM.sun : w == 6 ? MM.sat : MM.fg)
                    .padding(.leading, 5)
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                    .background(today ? MM.today : Color.clear)
                Spacer(minLength: 0)
                Group {
                    if let t, t.income > 0 { Text(Fmt.compact(t.income, c)).foregroundStyle(MM.inc) }
                    if let t, t.expense > 0 { Text(Fmt.compact(t.expense, c)).foregroundStyle(MM.exp) }
                    if let t, t.income > 0, t.expense > 0 { Text(Fmt.compact(t.income - t.expense, c)).foregroundStyle(MM.fg) }
                }
                .font(.system(size: 10).monospacedDigit())
                .tracking(-0.2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 5)
            }
            .padding(.top, today ? 0 : 5)
            .padding(.bottom, 3)
            .frame(height: cellHeight, alignment: .top)
            .background(out ? MM.bg2 : MM.bg)
            .overlay(alignment: .trailing) { if col < 6 { MM.line.frame(width: 1) } }
            .overlay(alignment: .bottom) { Line() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Tapping a calendar day: that day's transactions in a sheet, with + to add one there.
struct DaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var day: String

    var body: some View {
        let list = Ledger.transactions(in: Period(from: day, to: day), model.snapshot)
        let t = Ledger.totals(list)
        VStack(spacing: 0) {
            SheetHeader(title: Fmt.longDay(day)) {
                Button {
                    dismiss()
                    model.newTransaction(day: day)
                } label: { Icon("plus").frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(MM.accent)
            }
            HStack {
                Spacer(); Text(Fmt.money(t.income, model.currency)).foregroundStyle(MM.inc)
                Spacer(); Text(Fmt.money(t.expense, model.currency)).foregroundStyle(MM.exp)
                Spacer(); Text(Fmt.money(t.total, model.currency))
                Spacer()
            }
            .font(.system(size: 14).monospacedDigit())
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Line() }
            ScrollView {
                if list.isEmpty {
                    Text("Nothing on this day").foregroundStyle(MM.fg3).padding(36)
                } else {
                    VStack(spacing: 0) {
                        ForEach(list) { tx in
                            TxRow(tx: tx).simultaneousGesture(TapGesture().onEnded { dismiss() })
                            Line()
                        }
                    }
                }
            }
        }
        .background(MM.bg)
        .presentationDetents(list.count > 4 ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Weekly

struct WeeklyList: View {
    @Environment(AppModel.self) private var model
    var period: Period
    var txs: [Transaction]

    var body: some View {
        let ws = model.snapshot.firstWeekday - 1
        var start = period.from
        while Fmt.weekday(start) != ws { start = Periods.addDays(start, -1) }
        var weeks: [String] = []
        var w = start
        while w <= period.to { weeks.append(w); w = Periods.addDays(w, 7) }
        let today = Periods.today()
        let c = model.currency
        return LazyVStack(spacing: 0) {
            ForEach(weeks.reversed(), id: \.self) { w in
                let we = Periods.addDays(w, 6)
                let t = Ledger.totals(txs.filter { $0.day >= w && $0.day <= we })
                NavigationLink(value: WeekRoute(start: w)) {
                    HStack(alignment: .center, spacing: 14) {
                        Text("\(Fmt.md(w)) ~ \(Fmt.md(we))").font(.system(size: 15).monospacedDigit()).foregroundStyle(MM.fgNote)
                            .lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.money(t.income, c)).foregroundStyle(MM.inc)
                            Text(" ").font(.system(size: 13))
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.money(t.expense, c)).foregroundStyle(MM.exp)
                            Text(Fmt.money(t.total, c)).font(.system(size: 13)).foregroundStyle(MM.fg3)
                        }
                    }
                    .font(.system(size: 15).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 9)
                    .frame(minHeight: 58)
                    .background(today >= w && today <= we ? MM.accent.opacity(0.07) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                Line()
            }
        }
    }
}

struct WeekPage: View {
    @Environment(AppModel.self) private var model
    var start: String

    var body: some View {
        let end = Periods.addDays(start, 6)
        let list = Ledger.transactions(in: Period(from: start, to: end), model.snapshot)
        VStack(spacing: 0) {
            PageHeader(title: Fmt.shortRange(start, end))
            ScrollView {
                VStack(spacing: 0) {
                    Strip(items: Strip.incExpTotal(Ledger.totals(list)))
                    DayList(txs: list, emptyText: "Nothing this week").padding(.bottom, 24)
                }
            }
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Monthly

struct MonthlyList: View {
    @Environment(AppModel.self) private var model
    var year: Int
    var onMonth: (YearMonth) -> Void

    var body: some View {
        let s = model.snapshot
        let cur = model.currentMonth
        let c = model.currency
        let rows: [(YearMonth, Period, Totals)] = (1...12).reversed().compactMap { m in
            let ym = YearMonth(year: year, month: m)
            let p = Periods.month(ym, startDay: s.monthStartDay)
            let t = Ledger.totals(Ledger.transactions(in: p, s))
            if ym > cur && t.income == 0 && t.expense == 0 { return nil }
            return (ym, p, t)
        }
        if rows.isEmpty {
            EmptyText(text: "No data for \(String(year))")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.0) { ym, p, t in
                    Button { onMonth(ym) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.months[ym.month - 1]).font(.system(size: 17, weight: .semibold)).foregroundStyle(MM.fg)
                                Text(Fmt.shortRange(p.from, p.to)).font(.system(size: 12)).foregroundStyle(MM.fg2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Fmt.money(t.income, c)).foregroundStyle(MM.inc)
                                Text(Fmt.money(t.expense, c)).foregroundStyle(MM.exp)
                                Text(Fmt.money(t.total, c)).font(.system(size: 12.5)).foregroundStyle(MM.fg2)
                            }
                            .font(.system(size: 14).monospacedDigit())
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(minHeight: 60)
                        .background(ym == cur ? MM.accent.opacity(0.06) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    Line()
                }
            }
        }
    }
}

// MARK: - Summary

struct SummaryView: View {
    @Environment(AppModel.self) private var model
    var month: YearMonth
    var txs: [Transaction]
    @State private var showBudgets = false

    var body: some View {
        let s = model.snapshot
        let c = model.currency
        let t = Ledger.totals(txs)
        let p = Periods.month(month, startDay: s.monthStartDay)
        let days = Set(txs.map(\.day)).count
        let today = Periods.today()
        let last = today < p.to ? (today < p.from ? p.from : today) : p.to
        let span = max(1, min(Periods.days(from: p.from, to: last).count, 31))
        let buds = Ledger.budgetStatus(s, month: month)
        var byAcc: [String: Double] = [:]
        for x in txs where x.type == .expense { byAcc[x.accountId, default: 0] += x.amount }
        let accRows = byAcc.sorted { $0.value > $1.value }
        let topCats = Ledger.byCategory(txs, type: .expense, s).prefix(3)
        return VStack(spacing: 12) {
            Card {
                CardHeader(title: Fmt.monthLabel(month)) {
                    Text(Fmt.shortRange(p.from, p.to)).font(.system(size: 13)).foregroundStyle(MM.fg2)
                }
                SettingRow(label: "Transactions", value: "\(txs.count) on \(days) day\(days == 1 ? "" : "s")")
                Line()
                SettingRow(label: "Savings rate", value: t.income > 0 ? "\(Int((t.total / t.income * 100).rounded()))%" : "—")
                Line()
                SettingRow(label: "Avg. spending / day", value: Fmt.money(t.expense / Double(span), c))
            }
            Card {
                CardHeader(title: "Budget") {
                    Button("Budget setting") { showBudgets = true }.font(.system(size: 14, weight: .medium)).foregroundStyle(MM.accent)
                }
                if buds.isEmpty {
                    SettingRow(label: "No budgets yet. Tap “Budget setting”.", value: "", muted: true)
                }
                ForEach(Array(buds.enumerated()), id: \.element.id) { i, b in
                    if i > 0 { Line() }
                    BudgetBar(line: b)
                }
            }
            if !accRows.isEmpty {
                Card {
                    CardHeader(title: "Exp. by account") { EmptyView() }
                    ForEach(Array(accRows.enumerated()), id: \.element.key) { i, r in
                        if i > 0 { Line() }
                        SettingRow(label: s.accounts[r.key]?.name ?? "?", value: Fmt.money(r.value, c), valueColor: MM.exp)
                    }
                }
            }
            if !topCats.isEmpty {
                Card {
                    CardHeader(title: "Top categories") { EmptyView() }
                    ForEach(Array(topCats.enumerated()), id: \.element.id) { i, cat in
                        if i > 0 { Line() }
                        SettingRow(emoji: cat.icon, label: cat.name, value: Fmt.money(cat.total, c))
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .navigationDestination(isPresented: $showBudgets) { BudgetSettings() }
    }
}

// MARK: - Search

struct SearchPage: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let s = model.snapshot
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let res: [Transaction] = q.isEmpty ? [] : Array(s.transactions.values.filter { t in
            let root = s.rootCategory(t.categoryId)?.name ?? ""
            let cat = s.categories[t.categoryId ?? ""]?.name ?? ""
            return "\(t.note) \(t.memo) \(root) \(cat) \(Fmt.num(t.amount, model.currency)) \(t.amount)".lowercased().contains(q)
        }.sorted(by: Ledger.sortDescending).prefix(300))
        VStack(spacing: 0) {
            PageHeader(title: "Search")
            InputField(placeholder: "Note, description, category, amount", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .background(MM.chrome)
            ScrollView {
                if q.isEmpty {
                    EmptyText(emoji: "🔎", text: "Search all transactions")
                } else {
                    VStack(spacing: 0) {
                        if !res.isEmpty { Strip(items: Strip.incExpTotal(Ledger.totals(res))) }
                        DayList(txs: res, emptyText: "No matches").padding(.bottom, 24)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task { try? await Task.sleep(for: .milliseconds(350)); focused = true }
    }
}

// MARK: - Grouped cards (Summary, Settings pages)

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(MM.bg, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
    }
}

struct CardHeader<R: View>: View {
    var title: String
    @ViewBuilder var right: R
    var body: some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            right
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

struct SettingRow: View {
    var emoji: String = ""
    var label: String
    var value: String
    var valueColor: Color = MM.fg2
    var muted = false
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            if !emoji.isEmpty { Text(emoji).font(.system(size: 20)).frame(width: 28) }
            Text(label).foregroundStyle(muted ? MM.fg2 : MM.fg).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(valueColor).monospacedDigit().lineLimit(1)
            if chevron { Icon("chev", size: 14).foregroundStyle(MM.fg3) }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
