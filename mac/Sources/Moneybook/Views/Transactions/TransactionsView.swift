import AppKit
import MoneybookCore
import SwiftUI

/// Trans. tab: Daily / Calendar / Weekly / Monthly / Summary (web/js/views/trans.js).
struct TransactionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.snapshot
        let yearMode = model.transactionsMode == .monthly
        let period = yearMode ? model.yearPeriod : model.period
        let txs = Ledger.transactions(in: period, s)

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                MBHeader(title: "Transaction") {
                    IconButton(symbol: "magnifyingglass", help: "Search (⌘F)") { model.open(.search) }
                        .keyboardShortcut("f")
                } right: {
                    IconButton(symbol: "slider.horizontal.3", help: "Search") { model.open(.search) }
                }
                MonthSwitcher(label: yearMode ? String(model.month.year) : Fmt.monthLabel(model.month),
                              onPrev: { model.step(-1) }, onNext: { model.step(1) }, onLabel: { model.goToToday() })
                SubTabs(items: TransactionsMode.allCases.map { ($0, $0.rawValue) }, selection: $model.transactionsMode)
                Strip.incExpTotal(txs)
            }
            .background(MB.chrome)

            Group {
                switch model.transactionsMode {
                case .daily:
                    ScrollView {
                        DayList(transactions: txs, addable: true, emptyText: "No transactions in \(Fmt.monthLabel(model.month))")
                            .padding(.bottom, 40)
                    }
                case .calendar: CalendarGrid(transactions: txs, period: period)
                case .weekly: ScrollView { WeeklyList(transactions: txs, period: period).padding(.bottom, 40) }
                case .monthly: ScrollView { MonthlyList().padding(.bottom, 40) }
                case .summary: ScrollView { SummaryCards(transactions: txs) }.background(MB.bg2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Calendar

struct CalendarGrid: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    var period: Period

    var body: some View {
        let s = model.snapshot
        let byDay = Ledger.totalsByDay(transactions)
        let days = gridDays(firstWeekday: s.firstWeekday)
        let rows = days.count / 7
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let w = (s.firstWeekday - 1 + i) % 7 + 1
                    Text(Periods.weekdaySymbols(firstWeekday: s.firstWeekday)[i])
                        .font(.system(size: 12.5))
                        .foregroundStyle(w == 1 ? MB.sun : w == 7 ? MB.sat : MB.fg2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
            }
            .background(MB.bg2)
            .bottomLine()
            GeometryReader { geo in
                let h = max(geo.size.height / CGFloat(max(rows, 1)), 64)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { c in
                                    cell(days[r * 7 + c], byDay: byDay, last: c == 6).frame(height: h)
                                }
                            }
                        }
                    }
                }
                .scrollDisabled(h * CGFloat(rows) <= geo.size.height + 1)
            }
        }
    }

    /// Whole weeks covering the period, padded with days from the neighbouring months.
    private func gridDays(firstWeekday: Int) -> [String] {
        var start = period.from
        while Periods.weekday(start) != firstWeekday { start = Periods.addDays(start, -1) }
        let lastWeekday = (firstWeekday + 5) % 7 + 1
        var end = period.to
        while Periods.weekday(end) != lastWeekday { end = Periods.addDays(end, 1) }
        return Periods.days(from: start, to: end)
    }

    private func cell(_ day: String, byDay: [String: Totals], last: Bool) -> some View {
        let out = !period.contains(day)
        let w = Periods.weekday(day)
        let isToday = day == Periods.today()
        let t = byDay[day]
        let dayColor: Color = out ? MB.fg3 : isToday ? .white : w == 1 ? MB.sun : w == 7 ? MB.sat : MB.fg
        let label = day.hasSuffix("-01") ? "\(day.dropFirst(5).prefix(2))/01" : Fmt.dayNumber(day)
        return VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(dayColor)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .padding(.leading, 5)
                .background(isToday ? MB.today : .clear)
            Spacer(minLength: 0)
            Group {
                if let t, t.income > 0 { Text(compact(t.income)).foregroundStyle(MB.inc) }
                if let t, t.expense > 0 { Text(compact(t.expense)).foregroundStyle(MB.exp) }
                if let t, t.income > 0, t.expense > 0 { Text(compact(t.total)).foregroundStyle(MB.fg) }
            }
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
        }
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(out ? MB.bg2 : .clear)
        .overlay(alignment: .trailing) { if !last { MB.line.frame(width: 1) } }
        .bottomLine()
        .rowHover()
        .onTapGesture { model.open(.day(day)) }
    }

    /// The web app's calendar figures: 1.2M above 100k, whole numbers above 1,000.
    private func compact(_ n: Double) -> String {
        let a = abs(n)
        if a >= 100_000 { return n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }
        if a >= 1000 { return n.formatted(.number.precision(.fractionLength(0))) }
        return model.money(n, symbol: false)
    }
}

// MARK: - Weekly

struct WeeklyList: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]
    var period: Period

    var body: some View {
        let s = model.snapshot
        var start = period.from
        while Periods.weekday(start) != s.firstWeekday { start = Periods.addDays(start, -1) }
        var weeks: [Period] = []
        var w = start
        while w <= period.to { weeks.append(Period(from: w, to: Periods.addDays(w, 6))); w = Periods.addDays(w, 7) }
        let today = Periods.today()
        return VStack(spacing: 0) {
            ForEach(weeks.reversed(), id: \.from) { wk in
                let t = Ledger.totals(transactions.filter { $0.day >= wk.from && $0.day <= wk.to })
                let cur = today >= wk.from && today <= wk.to
                HStack(alignment: .center, spacing: 14) {
                    Text(mdRange(wk)).font(.system(size: 15).monospacedDigit()).foregroundStyle(MB.fgNote)
                    Spacer()
                    Text(model.money(t.income)).foregroundStyle(MB.inc).frame(minWidth: 80, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(model.money(t.expense)).foregroundStyle(MB.exp)
                        Text(model.money(t.total)).font(.system(size: 13).monospacedDigit()).foregroundStyle(MB.fg3)
                    }
                    .frame(minWidth: 80, alignment: .trailing)
                }
                .font(.system(size: 15).monospacedDigit())
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .frame(minHeight: 58)
                .background(cur ? MB.accent.opacity(0.07) : .clear)
                .bottomLine()
                .rowHover()
                .onTapGesture { model.open(.week(wk)) }
            }
        }
    }

    private func mdRange(_ p: Period) -> String {
        func md(_ d: String) -> String { "\(d.dropFirst(5).prefix(2))/\(d.suffix(2))" }
        return "\(md(p.from)) ~ \(md(p.to))"
    }
}

struct WeekDetailView: View {
    @Environment(AppModel.self) private var model
    var period: Period

    var body: some View {
        let txs = Ledger.transactions(in: period, model.snapshot)
        VStack(spacing: 0) {
            DrawerHeader(title: Fmt.shortRange(period))
            Strip.incExpTotal(txs)
            ScrollView { DayList(transactions: txs, emptyText: "Nothing this week", categoryWidth: 96) }
        }
    }
}

// MARK: - Monthly

struct MonthlyList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.snapshot
        let cur = model.currentMonth
        let months = (1...12).reversed().map { YearMonth(year: model.month.year, month: $0) }.compactMap { ym -> (YearMonth, Period, Totals)? in
            let p = Periods.month(ym, startDay: s.monthStartDay)
            let t = Ledger.totals(Ledger.transactions(in: p, s))
            return ym > cur && t.income == 0 && t.expense == 0 ? nil : (ym, p, t)
        }
        if months.isEmpty {
            MBEmpty(text: "No data for \(String(model.month.year))")
        } else {
            VStack(spacing: 0) {
                ForEach(months, id: \.0) { ym, p, t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.monthName(ym, short: true)).font(.system(size: 17, weight: .semibold))
                            Text(Fmt.shortRange(p)).font(.system(size: 12)).foregroundStyle(MB.fg2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(model.money(t.income)).foregroundStyle(MB.inc)
                            Text(model.money(t.expense)).foregroundStyle(MB.exp)
                            Text(model.money(t.total)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(MB.fg2)
                        }
                        .font(.system(size: 14).monospacedDigit())
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(minHeight: 60)
                    .background(ym == cur ? MB.accent.opacity(0.06) : .clear)
                    .bottomLine()
                    .rowHover()
                    .onTapGesture {
                        model.month = ym
                        model.transactionsMode = .daily
                    }
                }
            }
        }
    }
}

// MARK: - Summary

struct SummaryCards: View {
    @Environment(AppModel.self) private var model
    var transactions: [Transaction]

    var body: some View {
        let s = model.snapshot
        let t = Ledger.totals(transactions)
        let p = model.period
        let days = Set(transactions.map(\.day)).count
        let today = Periods.today()
        let lastDay = today < p.from ? p.from : today > p.to ? p.to : today
        let span = max(1, min(Periods.days(from: p.from, to: lastDay).count, 31))
        let budgets = Ledger.budgetLines(s, month: model.month).filter { $0.budget > 0 }
        let byAccount = Dictionary(grouping: transactions.filter { $0.type == .expense }, by: \.accountId)
            .map { (name: s.accounts[$0.key]?.name ?? "?", total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        let topCats = Array(Ledger.byCategory(transactions, type: .expense, s).prefix(3))

        VStack(spacing: 0) {
            MBCard(title: Fmt.monthLabel(model.month)) {
                MBRow(label: "Transactions", value: "\(transactions.count) on \(days) day\(days == 1 ? "" : "s")")
                MBRow(label: "Savings rate", value: t.income > 0 ? "\(Int((t.total / t.income * 100).rounded()))%" : "—")
                MBRow(label: "Avg. spending / day", value: model.money(t.expense / Double(span)), last: true)
            }
            MBCard(title: "Budget", link: ("Budget setting", { model.open(.budgetSetting) })) {
                if budgets.isEmpty {
                    MBRow(label: "No budgets yet. Click \u{201C}Budget setting\u{201D}.", valueColor: MB.fg2, last: true)
                } else {
                    ForEach(Array(budgets.enumerated()), id: \.element.id) { i, line in BudgetBar(line: line, last: i == budgets.count - 1) }
                }
            }
            if !byAccount.isEmpty {
                MBCard(title: "Exp. by account") {
                    ForEach(Array(byAccount.enumerated()), id: \.offset) { i, r in
                        MBRow(label: r.name, value: model.money(r.total), valueColor: MB.exp, last: i == byAccount.count - 1)
                    }
                }
            }
            if !topCats.isEmpty {
                MBCard(title: "Top categories") {
                    ForEach(Array(topCats.enumerated()), id: \.element.id) { i, c in
                        MBRow(label: c.name, value: model.money(c.total), emoji: c.icon.isEmpty ? nil : c.icon, last: i == topCats.count - 1)
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Day panel and search

struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    var day: String

    var body: some View {
        let txs = Ledger.transactions(in: Period(from: day, to: day), model.snapshot)
        VStack(spacing: 0) {
            DrawerHeader(title: Fmt.longDate(day)) {
                IconButton(symbol: "plus", help: "Add on this day") { model.newTransaction(day: day) }
            }
            Strip.incExpTotal(txs)
            ScrollView { DayList(transactions: txs, emptyText: "Nothing on this day", categoryWidth: 96) }
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @UIState private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let s = model.snapshot
        let q = query.trimmingCharacters(in: .whitespaces)
        let results = q.isEmpty ? [] : Array(s.transactions.values.filter { tx in
            Ledger.matches(tx, query: q, s) || model.money(tx.amount, symbol: false).contains(q) || String(Int(tx.amount)).contains(q)
        }.sorted(by: Ledger.sortDescending).prefix(300))
        VStack(spacing: 0) {
            DrawerHeader(title: "Search")
            TextField("Note, description, category, amount", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(MB.bg2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? MB.accent : MB.line, lineWidth: 1.5))
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            ScrollView {
                if q.isEmpty {
                    MBEmpty(text: "Search all transactions", emoji: "🔎")
                } else {
                    if !results.isEmpty { Strip.incExpTotal(results) }
                    DayList(transactions: results, emptyText: "No matches", categoryWidth: 96)
                }
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
