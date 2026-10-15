import AppKit
import MoneybookCore
import SwiftUI

/// Stats tab: Stats (pie by category) / Budget / Note (web/js/views/stats.js).
struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.snapshot
        let yearMode = model.statsYear && model.statsMode != .budget
        let period = yearMode ? model.yearPeriod : model.period
        let label = yearMode ? String(model.month.year) : Fmt.monthLabel(model.month)
        let txs = Ledger.transactions(in: period, s)
        let t = Ledger.totals(txs)

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    Seg3(selection: $model.statsMode)
                    HStack {
                        Spacer()
                        Button { if model.statsMode != .budget { model.statsYear.toggle() } } label: {
                            HStack(spacing: 4) {
                                Text(yearMode ? "Y" : "M").font(.system(size: 14))
                                Text("▾").font(.system(size: 10)).foregroundStyle(MB.fg3)
                            }
                            .padding(.horizontal, 8)
                            .frame(minWidth: 46, minHeight: 30)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(white: 0.64), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Switch between month and year")
                    }
                    .padding(.horizontal, 23)
                }
                .frame(height: 54)
                MonthSwitcher(label: label, onPrev: { model.step(-1) }, onNext: { model.step(1) }, onLabel: { model.goToToday() })
                if model.statsMode != .budget {
                    HStack(spacing: 0) {
                        typeTab(.income, "Income \(model.money(t.income))")
                        typeTab(.expense, "Expenses \(model.money(t.expense))")
                    }
                    .bottomLine()
                }
            }
            .background(MB.chrome)

            ScrollView {
                switch model.statsMode {
                case .stats: pieAndList(txs, period: period, label: label)
                case .budget: budget
                case .note: notes(txs, period: period)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func typeTab(_ type: TxType, _ title: String) -> some View {
        let on = model.statsType == type
        return Button { model.statsType = type } label: {
            Text(title)
                .font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(on ? MB.fg : Color(white: 0.64))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42)
                .overlay(alignment: .bottom) { if on { MB.accent.frame(height: 3) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pieAndList(_ txs: [Transaction], period: Period, label: String) -> some View {
        let type: CategoryType = model.statsType == .income ? .income : .expense
        let rows = Ledger.byCategory(txs, type: type, model.snapshot)
        if rows.isEmpty {
            MBEmpty(text: "No data available.", emoji: "📊")
        } else {
            HStack(alignment: .top, spacing: 0) {
                PieChart(rows: rows)
                    .frame(height: 340)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) { MB.line.frame(width: 0.5) }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: 10) {
                            Text("\(Int(row.percent.rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(minWidth: 40)
                                .padding(.vertical, 3)
                                .background(MB.chartColor(i), in: RoundedRectangle(cornerRadius: 4))
                            Text(row.name).lineLimit(1)
                            Spacer()
                            Text(model.money(row.total)).monospacedDigit()
                        }
                        .font(.system(size: 14.5))
                        .foregroundStyle(MB.fgNote)
                        .padding(.leading, 15)
                        .padding(.trailing, 20)
                        .frame(minHeight: 46)
                        .bottomLine()
                        .rowHover()
                        .onTapGesture { model.open(.category(row.id.isEmpty ? nil : row.id, model.statsType, period, label)) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var budget: some View {
        let lines = Ledger.budgetLines(model.snapshot, month: model.month).filter { $0.budget > 0 }
        return VStack(spacing: 0) {
            HStack {
                Text("Budget")
                Spacer()
                Button("Budget Setting ›") { model.open(.budgetSetting) }.buttonStyle(.plain).foregroundStyle(MB.accent)
            }
            .font(.system(size: 14))
            .foregroundStyle(MB.fg2)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(MB.bg2)
            .bottomLine()
            if lines.isEmpty {
                MBEmpty(text: "No budgets yet. Click \u{201C}Budget Setting\u{201D}.", emoji: "🎯")
            } else {
                ForEach(lines) { BudgetBar(line: $0) }
            }
        }
    }

    @ViewBuilder
    private func notes(_ txs: [Transaction], period: Period) -> some View {
        let type = model.statsType
        let groups = Dictionary(grouping: txs.filter { $0.type == type }) { $0.note.trimmingCharacters(in: .whitespaces) }
            .map { (note: $0.key, count: $0.value.count, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        if groups.isEmpty {
            MBEmpty(text: "No data available.", emoji: "📝")
        } else {
            VStack(spacing: 0) {
                ForEach(groups, id: \.note) { g in
                    HStack(spacing: 14) {
                        Text(g.note.isEmpty ? "(No note)" : g.note).foregroundStyle(g.note.isEmpty ? MB.fg2 : MB.fgNote).lineLimit(1)
                        Spacer()
                        Text("\(g.count)").font(.system(size: 13)).foregroundStyle(MB.fg3)
                        Text(model.money(g.total)).monospacedDigit().foregroundStyle(type == .income ? MB.inc : MB.exp)
                    }
                    .font(.system(size: 14.5))
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
                    .frame(minHeight: 48)
                    .bottomLine()
                    .rowHover()
                    .onTapGesture { model.open(.note(g.note, type, period)) }
                }
            }
        }
    }
}

/// `.seg3`: coral outlined three-way switch.
private struct Seg3: View {
    @Binding var selection: StatsMode
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(StatsMode.allCases.enumerated()), id: \.element) { i, m in
                let on = m == selection
                Button { selection = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14))
                        .foregroundStyle(on ? Color.white : MB.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(on ? MB.accent : .clear)
                        .overlay(alignment: .leading) { if i > 0 { MB.accent.frame(width: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MB.accent, lineWidth: 1))
    }
}

/// Pie with outside labels and leader lines, laid out like the web app's SVG (440×300 design space).
struct PieChart: View {
    var rows: [CategorySlice]

    private struct Slice { var row: CategorySlice; var index: Int; var a0: Double; var a1: Double; var mid: Double { (a0 + a1) / 2 } }
    private struct Label { var slice: Slice; var y: Double; var right: Bool }

    var body: some View {
        Canvas { ctx, size in
            let W = 440.0, H = 300.0
            let scale = min(size.width / W, size.height / H)
            ctx.translateBy(x: (size.width - W * scale) / 2, y: (size.height - H * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            let cx = W / 2, cy = H / 2 + 4, R = 88.0
            let total = rows.reduce(0) { $0 + $1.total }
            guard total > 0 else { return }
            // Largest first, clockwise; the small tail is centred at 9 o'clock where its labels have room.
            let tail = rows.filter { $0.percent < 10 }.reduce(0) { $0 + $1.total / total * .pi * 2 }
            var a0 = tail > 0 ? Double.pi + tail / 2 : -Double.pi / 2
            var slices: [Slice] = []
            for (i, r) in rows.enumerated() {
                let a1 = a0 + r.total / total * .pi * 2
                slices.append(Slice(row: r, index: i, a0: a0, a1: a1))
                a0 = a1
            }
            func pt(_ rad: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a)) }
            for s in slices {
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy))
                p.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: .radians(s.a0), endAngle: .radians(s.a1), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(MB.chartColor(s.index)))
                if slices.count > 1 { ctx.stroke(p, with: .color(.white), lineWidth: 1) }
            }
            // Labels in one column per side, pushed apart so they never overlap.
            var left: [Label] = [], right: [Label] = []
            for s in slices.filter({ $0.row.percent >= 0.5 }).prefix(14) {
                let isRight = cos(s.mid) >= 0
                let l = Label(slice: s, y: pt(R + 22, s.mid).y, right: isRight)
                if isRight { right.append(l) } else { left.append(l) }
            }
            let gap = 32.0, top = 16.0, bottom = H - 16
            for var col in [left, right] {
                col.sort { $0.y < $1.y }
                for i in col.indices { col[i].y = max(col[i].y, i > 0 ? col[i - 1].y + gap : top) }
                for i in col.indices.reversed() { col[i].y = min(col[i].y, i < col.count - 1 ? col[i + 1].y - gap : bottom - 10) }
                for l in col {
                    let s = l.slice
                    let e = pt(R, s.mid), k = pt(R + 10, s.mid)
                    let lx = l.right ? cx + R + 26 : cx - R - 26
                    var line = Path()
                    line.move(to: e); line.addLine(to: k); line.addLine(to: CGPoint(x: lx, y: l.y + 4))
                    ctx.stroke(line, with: .color(MB.chartColor(s.index)), lineWidth: 1)
                    let tx = lx + (l.right ? 4 : -4)
                    let anchor: UnitPoint = l.right ? .leading : .trailing
                    let name = s.row.name.count > 12 ? String(s.row.name.prefix(11)).trimmingCharacters(in: .whitespaces) + "…" : s.row.name
                    ctx.draw(Text(name).font(.system(size: 12.5, weight: .bold)).foregroundColor(MB.fg), at: CGPoint(x: tx, y: l.y - 4), anchor: anchor)
                    ctx.draw(Text(String(format: "%.1f %%", s.row.percent)).font(.system(size: 12)).foregroundColor(MB.fgNote),
                             at: CGPoint(x: tx, y: l.y + 11), anchor: anchor)
                }
            }
        }
        .accessibilityLabel("Category breakdown")
    }
}

/// A top-level category's transactions in a period, with its subcategory split.
struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    var categoryId: String?
    var type: TxType
    var period: Period
    var label: String

    var body: some View {
        let s = model.snapshot
        let txs = Ledger.transactions(in: period, s).filter { $0.type == type && s.rootCategory($0.categoryId)?.id == categoryId }
        let sum = txs.reduce(0) { $0 + $1.amount }
        let subs = Dictionary(grouping: txs) { tx -> String in
            let c = s.categories[tx.categoryId ?? ""]
            return c?.parentId != nil ? c!.name : "(no subcategory)"
        }
        .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
        .sorted { $0.total > $1.total }
        VStack(spacing: 0) {
            DrawerHeader(title: categoryId.flatMap { s.categories[$0]?.name } ?? "Uncategorized")
            Strip(items: [(label, sum, type == .income ? MB.inc : MB.exp), ("Transactions", Double(txs.count), MB.fg)], counts: [1])
            ScrollView {
                if subs.count > 1 {
                    MBCard {
                        ForEach(Array(subs.enumerated()), id: \.offset) { i, r in
                            MBRow(label: r.name, value: "\(model.money(r.total)) · \(sum > 0 ? Int((r.total / sum * 100).rounded()) : 0)%", last: i == subs.count - 1)
                        }
                    }
                    .padding(.top, 12)
                    .background(MB.bg2)
                }
                DayList(transactions: txs, categoryWidth: 96)
            }
        }
    }
}

struct NoteDetailView: View {
    @Environment(AppModel.self) private var model
    var note: String
    var type: TxType
    var period: Period

    var body: some View {
        let txs = Ledger.transactions(in: period, model.snapshot).filter { $0.type == type && $0.note.trimmingCharacters(in: .whitespaces) == note }
        VStack(spacing: 0) {
            DrawerHeader(title: note.isEmpty ? "(No note)" : note)
            ScrollView { DayList(transactions: txs, categoryWidth: 96) }
        }
    }
}
