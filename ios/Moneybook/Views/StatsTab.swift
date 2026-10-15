import MoneybookCore
import SwiftUI

/// Stats tab: Stats (pie by category) / Budget / Note, like Money Manager (web/js/views/stats.js).
struct StatsTab: View {
    @Environment(AppModel.self) private var model
    enum View3: String { case stats, budget, note }
    @State private var view: View3 = .stats
    @State private var yearly = false
    @State private var ym = Periods.yearMonth(containing: Periods.today())
    @State private var type = CategoryType.expense
    @State private var showBudgets = false

    var body: some View {
        let s = model.snapshot
        let r = range(s)
        let list = Ledger.transactions(in: r.period, s)
        let t = Ledger.totals(list)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HeaderBar(sideWidth: 64, left: { EmptyView() }, center: { seg3 }, right: {
                    Button { if view != .budget { yearly.toggle() } } label: {
                        HStack(spacing: 4) {
                            Text(yearly ? "Y" : "M").font(.system(size: 14))
                            Text("▾").font(.system(size: 10)).foregroundStyle(MM.fg3)
                        }
                        .padding(.horizontal, 8)
                        .frame(minWidth: 46, minHeight: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(dyn(0xa2a2a2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 9)
                    .accessibilityLabel(yearly ? "Yearly" : "Monthly")
                })
                MonthSwitcher(label: r.label, onStep: { ym = ym.adding(months: $0 * (yearly ? 12 : 1)) }, onToday: { ym = model.currentMonth })
                if view != .budget {
                    SubTabs(items: [(CategoryType.income, "Income \(Fmt.money(t.income, model.currency))"),
                                    (CategoryType.expense, "Expenses \(Fmt.money(t.expense, model.currency))")],
                            selection: $type, fontSize: 13.5, height: 42, idle: dyn(0xa2a2a2), boldSelected: false)
                }
            }
            .background(MM.chrome)
            ScrollView {
                Group {
                    switch view {
                    case .stats: statsView(list, r)
                    case .budget: budgetView(s)
                    case .note: NoteList(txs: list, type: type, period: r.period)
                    }
                }
                .padding(.bottom, 90)
            }
            .background(MM.bg)
            .refreshable { await model.sync() }
        }
        .onAppear { if ym.year < 2000 { ym = model.currentMonth } }
        .navigationDestination(for: CategoryRoute.self) { CategoryPage(route: $0) }
        .navigationDestination(for: NoteRoute.self) { NotePage(route: $0) }
        .navigationDestination(isPresented: $showBudgets) { BudgetSettings() }
    }

    private func dyn(_ hex: UInt32) -> Color { MM.dyn(hex, hex) }

    private var seg3: some View {
        HStack(spacing: 0) {
            ForEach([(View3.stats, "Stats"), (.budget, "Budget"), (.note, "Note")], id: \.0) { k, l in
                Button {
                    view = k
                    if k == .budget { yearly = false }
                } label: {
                    Text(l).font(.system(size: 14))
                        .foregroundStyle(view == k ? .white : MM.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(view == k ? MM.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if k != .note { MM.accent.frame(width: 1) }
            }
        }
        .frame(maxWidth: 240, minHeight: 30, maxHeight: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MM.accent, lineWidth: 1))
    }

    private func range(_ s: Snapshot) -> (period: Period, label: String) {
        if yearly {
            let from = Periods.month(YearMonth(year: ym.year, month: 1), startDay: s.monthStartDay).from
            let to = Periods.month(YearMonth(year: ym.year, month: 12), startDay: s.monthStartDay).to
            return (Period(from: from, to: to), String(ym.year))
        }
        return (Periods.month(ym, startDay: s.monthStartDay), Fmt.monthLabel(ym))
    }

    @ViewBuilder private func statsView(_ list: [Transaction], _ r: (period: Period, label: String)) -> some View {
        let rows = Ledger.byCategory(list, type: type, model.snapshot)
        if rows.isEmpty {
            EmptyText(text: "No data available.")
        } else {
            VStack(spacing: 0) {
                PieChart(rows: rows).frame(height: 300).padding(.top, 4)
                Hairline()
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    NavigationLink(value: CategoryRoute(categoryId: row.id, type: type, period: r.period, label: r.label)) {
                        HStack(spacing: 10) {
                            Text(verbatim: "\(Int(row.percent.rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4.5).padding(.vertical, 3)
                                .frame(minWidth: 40)
                                .background(MM.chartColor(i), in: RoundedRectangle(cornerRadius: 4))
                            Text(row.name).font(.system(size: 14.5)).foregroundStyle(MM.fgNote).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.money(row.total, model.currency)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(MM.fgNote)
                        }
                        .padding(.leading, 15).padding(.trailing, 20)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    Hairline()
                }
            }
        }
    }

    @ViewBuilder private func budgetView(_ s: Snapshot) -> some View {
        let buds = Ledger.budgetStatus(s, month: ym)
        VStack(spacing: 0) {
            HStack {
                Text("Budget")
                Spacer()
                Button("Budget Setting ›") { showBudgets = true }.foregroundStyle(MM.accent)
            }
            .font(.system(size: 14))
            .foregroundStyle(MM.fg2)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            .background(MM.bg2)
            .overlay(alignment: .bottom) { Hairline() }
            if buds.isEmpty {
                EmptyText(text: "No budgets yet. Tap “Budget Setting”.")
            }
            ForEach(buds) { b in
                BudgetBar(line: b)
                Line()
            }
        }
    }
}

struct CategoryRoute: Hashable {
    var categoryId: String
    var type: CategoryType
    var period: Period
    var label: String
}

struct NoteRoute: Hashable {
    var note: String
    var type: CategoryType
    var period: Period
}

/// Totals per note text, like Money Manager's Note tab.
struct NoteList: View {
    @Environment(AppModel.self) private var model
    var txs: [Transaction]
    var type: CategoryType
    var period: Period

    var body: some View {
        var m: [String: (n: Int, v: Double)] = [:]
        for t in txs where t.type.rawValue == type.rawValue {
            let k = t.note.trimmingCharacters(in: .whitespaces)
            m[k, default: (0, 0)].n += 1
            m[k, default: (0, 0)].v += t.amount
        }
        let rows = m.sorted { $0.value.v > $1.value.v }
        return Group {
            if rows.isEmpty {
                EmptyText(text: "No data available.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.key) { k, e in
                        NavigationLink(value: NoteRoute(note: k, type: type, period: period)) {
                            HStack(spacing: 14) {
                                Text(k.isEmpty ? "(No note)" : k).font(.system(size: 14.5))
                                    .foregroundStyle(k.isEmpty ? MM.fg2 : MM.fgNote).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(verbatim: "\(e.n)").font(.system(size: 13)).foregroundStyle(MM.fg3)
                                Text(Fmt.money(e.v, model.currency)).font(.system(size: 14.5).monospacedDigit())
                                    .foregroundStyle(type == .income ? MM.inc : MM.exp)
                            }
                            .padding(.leading, 16).padding(.trailing, 20)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        Hairline()
                    }
                }
            }
        }
    }
}

struct NotePage: View {
    @Environment(AppModel.self) private var model
    var route: NoteRoute

    var body: some View {
        let list = Ledger.transactions(in: route.period, model.snapshot)
            .filter { $0.type.rawValue == route.type.rawValue && $0.note.trimmingCharacters(in: .whitespaces) == route.note }
        VStack(spacing: 0) {
            PageHeader(title: route.note.isEmpty ? "(No note)" : route.note)
            ScrollView { DayList(txs: list).padding(.bottom, 24) }
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One top-level category's transactions in a range, with its subcategory split.
struct CategoryPage: View {
    @Environment(AppModel.self) private var model
    var route: CategoryRoute

    var body: some View {
        let s = model.snapshot
        let id = route.categoryId
        let list = Ledger.transactions(in: route.period, s).filter {
            $0.type.rawValue == route.type.rawValue && (s.rootCategory($0.categoryId)?.id ?? "") == id
        }
        let sum = list.reduce(0) { $0 + $1.amount }
        var subs: [String: Double] = [:]
        for t in list {
            let c = s.categories[t.categoryId ?? ""]
            let name = c != nil && c!.parentId != nil ? c!.name : "(no subcategory)"
            subs[name, default: 0] += t.amount
        }
        return VStack(spacing: 0) {
            PageHeader(title: s.categories[id]?.name ?? "Uncategorized")
            HStack(spacing: 0) {
                VStack(spacing: 1) {
                    Text(route.label).font(.system(size: 13)).foregroundStyle(MM.fgNote)
                    Text(Fmt.money(sum, model.currency)).font(.system(size: 15.5).monospacedDigit())
                        .foregroundStyle(route.type == .income ? MM.inc : MM.exp)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 1) {
                    Text("Transactions").font(.system(size: 13)).foregroundStyle(MM.fgNote)
                    Text("\(list.count)").font(.system(size: 15.5).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 6).padding(.bottom, 8)
            .background(MM.chrome)
            .overlay(alignment: .bottom) { Line() }
            ScrollView {
                VStack(spacing: 0) {
                if subs.count > 1 {
                    Card {
                        ForEach(Array(subs.sorted { $0.value > $1.value }.enumerated()), id: \.element.key) { i, e in
                            if i > 0 { Line() }
                            SettingRow(label: e.key, value: "\(Fmt.money(e.value, model.currency)) · \(Int((e.value / sum * 100).rounded()))%")
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(MM.bg2)
                }
                DayList(txs: list).padding(.bottom, 24)
                }
            }
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Pie with outside labels and leader lines (Money Manager draws it with Highcharts).
/// Same geometry as the web app's SVG: a 440×300 canvas scaled to the width.
struct PieChart: View {
    var rows: [CategorySlice]
    @Environment(\.colorScheme) private var scheme

    private struct Slice { var i: Int; var row: CategorySlice; var a0: Double; var a1: Double; var mid: Double { (a0 + a1) / 2 } }
    private struct Label { var s: Slice; var y: Double; var right: Bool }

    var body: some View {
        Canvas { ctx, size in
            let W = 440.0, H = 300.0
            let k = min(size.width / W, size.height / H)
            ctx.translateBy(x: (size.width - W * k) / 2, y: (size.height - H * k) / 2)
            ctx.scaleBy(x: k, y: k)
            let cx = W / 2, cy = H / 2 + 4, R = 88.0
            let total = rows.reduce(0) { $0 + $1.total }
            guard total > 0 else { return }
            // Slices run clockwise largest-first; rotate so the small tail is centred at 9 o'clock.
            let tail = rows.filter { $0.percent < 10 }.reduce(0) { $0 + $1.total / total * .pi * 2 }
            var a0 = tail > 0 ? Double.pi + tail / 2 : -Double.pi / 2
            var slices: [Slice] = []
            for (i, r) in rows.enumerated() {
                let a1 = a0 + r.total / total * .pi * 2
                slices.append(Slice(i: i, row: r, a0: a0, a1: a1))
                a0 = a1
            }
            func pt(_ rad: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a)) }
            let center = CGPoint(x: cx, y: cy)
            for s in slices {
                var p = Path()
                if slices.count == 1 {
                    p.addEllipse(in: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
                } else {
                    p.move(to: center)
                    p.addArc(center: center, radius: R, startAngle: .radians(s.a0), endAngle: .radians(s.a1), clockwise: false)
                    p.closeSubpath()
                }
                ctx.fill(p, with: .color(MM.chartColor(s.i)))
                if slices.count > 1 { ctx.stroke(p, with: .color(scheme == .dark ? Color(white: 0.11) : .white), style: StrokeStyle(lineWidth: 1, lineJoin: .round)) }
            }
            // Labels: one column per side, pushed apart so they never overlap.
            let labeled = slices.filter { $0.row.percent >= 0.5 }.prefix(14)
            let gap = 32.0, top = 16.0, bottom = H - 16
            var left: [Label] = [], right: [Label] = []
            for s in labeled {
                let isRight = cos(s.mid) >= 0
                let l = Label(s: s, y: pt(R + 22, s.mid).y, right: isRight)
                if isRight { right.append(l) } else { left.append(l) }
            }
            for var col in [left, right] {
                col.sort { $0.y < $1.y }
                for i in col.indices { col[i].y = max(col[i].y, i > 0 ? col[i - 1].y + gap : top) }
                for i in col.indices.reversed() { col[i].y = min(col[i].y, i < col.count - 1 ? col[i + 1].y - gap : bottom - 10) }
                for l in col {
                    let s = l.s
                    let e = pt(R, s.mid), kn = pt(R + 10, s.mid)
                    let lx = l.right ? cx + R + 26 : cx - R - 26
                    var line = Path()
                    line.move(to: e); line.addLine(to: kn); line.addLine(to: CGPoint(x: lx, y: l.y + 4))
                    ctx.stroke(line, with: .color(MM.chartColor(s.i)), lineWidth: 1)
                    let name = s.row.name.count > 12 ? String(s.row.name.prefix(11)).trimmingCharacters(in: .whitespaces) + "…" : s.row.name
                    let tx = lx + (l.right ? 4 : -4)
                    let anchor: UnitPoint = l.right ? .leading : .trailing
                    // SVG text sits on its baseline; nudge up by roughly the cap height.
                    ctx.draw(Text(name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(MM.fg), at: CGPoint(x: tx, y: l.y - 4.5), anchor: anchor)
                    ctx.draw(Text(String(format: "%.1f %%", s.row.percent)).font(.system(size: 12)).foregroundStyle(MM.fgNote),
                             at: CGPoint(x: tx, y: l.y + 10.5), anchor: anchor)
                }
            }
        }
        .accessibilityLabel("Category breakdown")
    }
}
