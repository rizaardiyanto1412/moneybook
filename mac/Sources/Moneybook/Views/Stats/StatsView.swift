import Charts
import MoneybookCore
import SwiftUI

/// A donut slice: a category (or the folded "Other" bucket) with its colour.
struct ChartSlice: Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var total: Double
    var percent: Double
    var color: Color
    /// Category ids behind this slice (several for "Other").
    var categoryIds: [String]
    var drillable: Bool
}

/// Top slices keep their own colour slot; the rest fold into a grey "Other" so hues never repeat.
func makeSlices(_ cats: [CategorySlice], drillable: Bool = true) -> [ChartSlice] {
    let maxNamed = Palette.chart.count - 1
    if cats.count <= maxNamed + 1 {
        return cats.enumerated().map { i, c in
            ChartSlice(id: c.id, name: c.name, icon: c.icon, total: c.total, percent: c.percent,
                       color: Palette.chart[i], categoryIds: [c.id], drillable: drillable && !c.id.isEmpty)
        }
    }
    var out = cats.prefix(maxNamed).enumerated().map { i, c in
        ChartSlice(id: c.id, name: c.name, icon: c.icon, total: c.total, percent: c.percent, color: Palette.chart[i],
                   categoryIds: [c.id], drillable: drillable && !c.id.isEmpty)
    }
    let rest = cats.dropFirst(maxNamed)
    out.append(ChartSlice(id: "__other__", name: "Other (\(rest.count))", icon: "", total: rest.reduce(0) { $0 + $1.total },
                          percent: rest.reduce(0) { $0 + $1.percent }, color: Palette.other, categoryIds: rest.map(\.id), drillable: false))
    return out
}

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @UIState private var type: CategoryType = .expense

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.statsPath) {
            overview
                .navigationDestination(for: String.self) { CategoryStatsView(categoryId: $0) }
        }
        .navigationTitle("Stats")
    }

    private var overview: some View {
        let s = model.snapshot
        let txs = Ledger.transactions(in: model.period, s)
        let cats = Ledger.byCategory(txs, type: type, s)
        let total = cats.reduce(0) { $0 + $1.total }
        let slices = makeSlices(cats)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Type", selection: $type) {
                    let t = Ledger.totals(txs)
                    Text("Income  \(model.money(t.income))").tag(CategoryType.income)
                    Text("Expenses  \(model.money(t.expense))").tag(CategoryType.expense)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)

                if cats.isEmpty {
                    EmptyStateView(title: "No \(type == .expense ? "expenses" : "income") in \(Fmt.monthTitle(model.month))",
                                   symbol: "chart.pie", message: "Pick another month with ⌘[ and ⌘].")
                        .frame(height: 300)
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        DonutChart(slices: slices, total: total, centerTitle: type == .expense ? "Expenses" : "Income") { slice in
                            if slice.drillable { model.statsPath.append(slice.id) }
                        }
                        .frame(width: 300, height: 300)
                        SliceList(slices: slices) { slice in
                            if slice.drillable { model.statsPath.append(slice.id) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .card(padding: 20)
                }

                TrendChart(end: model.month, categoryId: nil, onlyType: nil)
                    .card(padding: 20)
            }
            .readableWidth(1040)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .pageBackground()
    }
}

struct DonutChart: View {
    @Environment(AppModel.self) private var model
    var slices: [ChartSlice]
    var total: Double
    var centerTitle: String
    var onSelect: (ChartSlice) -> Void
    @UIState private var angle: Double?

    var body: some View {
        let hovered = hoveredSlice
        Chart(slices) { s in
            SectorMark(angle: .value("Amount", s.total), innerRadius: .ratio(0.6), outerRadius: .ratio(hovered?.id == s.id ? 1 : 0.94),
                       angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(s.color)
                .opacity(hovered == nil || hovered?.id == s.id ? 1 : 0.55)
                .accessibilityLabel(s.name)
                .accessibilityValue("\(model.money(s.total)), \(String(format: "%.1f", s.percent)) percent")
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $angle)
        .chartBackground { _ in
            VStack(spacing: 2) {
                if let hovered {
                    Text("\(hovered.icon) \(hovered.name)").font(.callout.weight(.medium)).lineLimit(1)
                    Text(model.money(hovered.total)).font(.title3.weight(.semibold).monospacedDigit())
                    Text(String(format: "%.1f%%", hovered.percent)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(centerTitle).font(.callout).foregroundStyle(.secondary)
                    Text(model.money(total)).font(.title3.weight(.semibold).monospacedDigit())
                }
            }
            .frame(maxWidth: 150)
        }
        .onTapGesture { if let hovered { onSelect(hovered) } }
    }

    private var hoveredSlice: ChartSlice? {
        guard let angle else { return nil }
        var acc = 0.0
        for s in slices {
            acc += s.total
            if angle <= acc { return s }
        }
        return nil
    }
}

struct SliceList: View {
    @Environment(AppModel.self) private var model
    var slices: [ChartSlice]
    var onSelect: (ChartSlice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(slices) { s in
                Button { onSelect(s) } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%.0f%%", s.percent))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 20)
                            .background(s.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(s.icon.isEmpty ? s.name : "\(s.icon)  \(s.name)")
                            .lineLimit(1)
                        Spacer()
                        Text(model.money(s.total)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).opacity(s.drillable ? 1 : 0)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(s.drillable)
                Divider()
            }
        }
    }
}

/// Income and expense per month over the last 12 months (or one category's spending).
struct TrendChart: View {
    @Environment(AppModel.self) private var model
    var end: YearMonth
    var categoryId: String?
    var onlyType: CategoryType?
    @UIState private var span = 6
    @UIState private var hoverMonth: String?

    struct Point: Identifiable {
        var month: YearMonth
        var series: String
        var amount: Double
        var id: String { month.key + series }
    }

    var body: some View {
        let trend = Ledger.monthlyTrend(model.snapshot, endingAt: end, count: span, categoryId: categoryId)
        let points = trend.flatMap { ym, t -> [Point] in
            var p: [Point] = []
            if onlyType != .expense { p.append(Point(month: ym, series: "Income", amount: t.income)) }
            if onlyType != .income { p.append(Point(month: ym, series: "Expenses", amount: t.expense)) }
            return p
        }
        let hovered = trend.first { $0.0.key == hoverMonth }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(categoryId == nil ? "Monthly trend" : "Monthly spending").font(.headline)
                Spacer()
                Picker("Range", selection: $span) {
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            Chart(points) { p in
                BarMark(x: .value("Month", p.month.key), y: .value("Amount", p.amount), width: .ratio(onlyType == nil ? 0.7 : 0.5))
                    .position(by: .value("Series", p.series))
                    .foregroundStyle(by: .value("Series", p.series))
                    .cornerRadius(4)
                    .opacity(hoverMonth == nil || hoverMonth == p.month.key ? 1 : 0.5)
                if let hoverMonth, hoverMonth == p.month.key, p.series == (onlyType == .income ? "Income" : "Expenses") {
                    RuleMark(x: .value("Month", hoverMonth))
                        .foregroundStyle(Color.secondary.opacity(0.12))
                        .lineStyle(StrokeStyle(lineWidth: 40))
                        .zIndex(-1)
                }
            }
            .chartForegroundStyleScale(["Income": Palette.income, "Expenses": Palette.expense])
            .chartLegend(onlyType == nil ? .visible : .hidden)
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel {
                        if let key = v.as(String.self), let ym = YearMonth(key) {
                            Text(span > 6 ? Fmt.monthName(ym, short: true) : Fmt.monthTitle(ym))
                                .fontWeight(ym == end ? .bold : .regular)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Money.compact(d, currency: model.currency)) } }
                }
            }
            .chartXSelection(value: $hoverMonth)
            .chartOverlay { _ in
                if let hovered {
                    HStack(spacing: 12) {
                        Text(Fmt.monthTitle(hovered.0)).fontWeight(.semibold)
                        if onlyType != .expense { Text("Income \(model.money(hovered.1.income))") }
                        if onlyType != .income { Text("Expenses \(model.money(hovered.1.expense))") }
                        if onlyType == nil { Text("Net \(model.money(hovered.1.total))").foregroundStyle(.secondary) }
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 220)
        }
    }
}

/// Drill-down: a category's subcategory breakdown, trend and transactions for the month.
struct CategoryStatsView: View {
    @Environment(AppModel.self) private var model
    var categoryId: String
    @UIState private var selection = Set<String>()
    @UIState private var pendingDelete: [String] = []

    var body: some View {
        let s = model.snapshot
        let cat = s.categories[categoryId]
        let monthTxs = Ledger.transactions(in: model.period, s)
        let txs = Ledger.transactions(monthTxs, inCategory: categoryId, s)
        let subs = Ledger.bySubcategory(monthTxs, parentId: categoryId, s)
        let total = txs.reduce(0) { $0 + $1.amount }
        let type: TxType = cat?.type == .income ? .income : .expense
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    CategoryIcon(icon: cat?.icon ?? "", size: 44, tint: Palette.color(type))
                    VStack(alignment: .leading) {
                        Text(cat?.name ?? "Category").font(.title2.weight(.semibold))
                        Text("\(txs.count) transactions in \(Fmt.monthTitle(model.month))").foregroundStyle(.secondary)
                    }
                    Spacer()
                    AmountText(amount: total, type: type, currency: model.currency, font: .title2.weight(.semibold))
                }
                if subs.count > 1 {
                    HStack(alignment: .top, spacing: 24) {
                        DonutChart(slices: makeSlices(subs, drillable: false), total: total, centerTitle: cat?.name ?? "") { _ in }
                            .frame(width: 220, height: 220)
                        SliceList(slices: makeSlices(subs, drillable: false)) { _ in }
                    }
                    .card(padding: 20)
                }
                TrendChart(end: model.month, categoryId: categoryId, onlyType: cat?.type ?? .expense)
                    .card(padding: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Transactions").font(.headline).padding(.bottom, 8)
                    if txs.isEmpty { Text("None this month.").foregroundStyle(.secondary) }
                    ForEach(txs) { tx in
                        TransactionRow(tx: tx, showDate: true)
                            .onTapGesture(count: 2) { model.edit(tx.id) }
                            .contextMenu {
                                Button("Edit…") { model.edit(tx.id) }
                                Button("Delete…", role: .destructive) { pendingDelete = [tx.id] }
                            }
                        Divider()
                    }
                }
                .card()
            }
            .readableWidth(1040)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .pageBackground()
        .navigationTitle(cat?.name ?? "Category")
        .confirmationDialog("Delete this transaction?", isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Delete", role: .destructive) {
                let ids = pendingDelete
                pendingDelete = []
                Task { await model.delete(transactionIds: ids) }
            }
        }
    }
}
