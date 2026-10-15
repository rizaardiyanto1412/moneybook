import MoneybookCore
import SwiftUI

/// One transaction: category icon, note, category · account, amount coloured by type.
struct TransactionRow: View {
    @Environment(AppModel.self) private var model
    var tx: Transaction
    /// Shown instead of the time (e.g. a running balance in account history).
    var trailingDetail: String?
    var showDate = false

    var body: some View {
        let s = model.snapshot
        let cat = s.categories[tx.categoryId ?? ""]
        let root = s.rootCategory(tx.categoryId)
        HStack(spacing: 12) {
            if tx.type == .transfer {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.12))
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
            } else {
                CategoryIcon(icon: (cat?.icon).flatMap { $0.isEmpty ? nil : $0 } ?? root?.icon ?? "", size: 36, tint: Palette.color(tx.type))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.body.weight(.medium)).lineLimit(1)
                    if tx.isAI { AISparkle() }
                    if tx.receipt != nil {
                        Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary).help("Has a receipt photo")
                    }
                }
                Text(subtitle(cat: cat, root: root))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((tx.type == .expense ? "−" : tx.type == .income ? "+" : "") + model.money(tx.amount))
                    .font(.money(14))
                    .foregroundStyle(tx.type == .transfer ? Color.primary : Palette.color(tx.type))
                Text(trailingDetail ?? (showDate ? "\(Fmt.dayMonth(tx.day)) \(tx.time)" : tx.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var title: String {
        if !tx.note.isEmpty { return tx.note }
        if tx.type == .transfer { return "Transfer" }
        return model.snapshot.categories[tx.categoryId ?? ""]?.name ?? "Uncategorized"
    }

    private func subtitle(cat: MoneybookCore.Category?, root: MoneybookCore.Category?) -> String {
        let s = model.snapshot
        let account = s.accounts[tx.accountId]?.name ?? "Deleted account"
        if tx.type == .transfer {
            let to = s.accounts[tx.toAccountId ?? ""]?.name ?? "Deleted account"
            return "\(account) → \(to)"
        }
        var catName = cat?.name ?? "Uncategorized"
        if let root, let cat, root.id != cat.id { catName = "\(root.name) › \(cat.name)" }
        return "\(catName) · \(account)"
    }
}

/// Day header like Money Manager: big day number, weekday and month, and the day's totals.
struct DayHeader: View {
    @Environment(AppModel.self) private var model
    var day: String
    var totals: Totals

    var body: some View {
        let isToday = day == Periods.today()
        HStack(alignment: .center, spacing: 10) {
            Text(Fmt.dayNumber(day))
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(minWidth: 40, minHeight: 40)
                .background(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(Fmt.weekdayLong(day)).font(.headline).foregroundStyle(weekdayColor(Periods.weekday(day)))
                    if isToday {
                        Text("Today").font(.caption2.weight(.bold)).textCase(.uppercase)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                Text(Fmt.monthTitle(YearMonth(year: Int(day.prefix(4)) ?? 0, month: Int(day.dropFirst(5).prefix(2)) ?? 1)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if totals.expense > 0 {
                    Text("−" + model.money(totals.expense)).font(.money(13)).foregroundStyle(Palette.expense)
                }
                if totals.income > 0 {
                    Text("+" + model.money(totals.income)).font(.money(13)).foregroundStyle(Palette.income)
                }
            }
        }
    }

    private func weekdayColor(_ w: Int) -> Color {
        switch w {
        case 1: Palette.expense
        case 7: Palette.income
        default: .primary
        }
    }
}
