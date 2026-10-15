import AppKit
import MoneybookCore
import SwiftUI

/// SDK 27's SwiftUI declares `@State` as a macro whose plugin ships only with Xcode, so under
/// Command Line Tools we reach the property wrapper through this alias instead.
typealias UIState = SwiftUI.State

// SwiftUI and the ObjC runtime also export `Transaction`/`Category`; ours win inside this module.
typealias Transaction = MoneybookCore.Transaction
typealias Category = MoneybookCore.Category

/// Money Manager's colour language.
enum Palette {
    static let income = Color(red: 0.20, green: 0.48, blue: 0.92)
    static let expense = Color(red: 0.94, green: 0.36, blue: 0.32)
    static let transfer = Color.secondary
    static let ai = Color(red: 0.62, green: 0.38, blue: 0.95)

    static func color(_ type: TxType) -> Color {
        switch type {
        case .income: income
        case .expense: expense
        case .transfer: transfer
        }
    }

    /// Categorical chart slots (validated for CVD separation; light and dark steps chosen separately).
    /// Charts show at most `chart.count - 1` categories and fold the rest into a grey "Other".
    static let chart: [Color] = [
        dynamic(0x2a78d6, 0x3987e5), dynamic(0xeb6834, 0xd95926), dynamic(0x1baf7a, 0x199e70), dynamic(0xeda100, 0xc98500),
        dynamic(0xe87ba4, 0xd55181), dynamic(0x008300, 0x008300), dynamic(0x6250d6, 0x9085e9), dynamic(0xe34948, 0xe66767),
    ]
    static let other = Color.gray.opacity(0.55)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
    /// Slot colour by position; anything past the last named slot is "Other" grey (never cycled).
    static func chartColor(_ index: Int) -> Color { index < chart.count - 1 ? chart[index] : other }
}

enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let monthYear = formatter("MMMMyyyy")
    private static let monthShort = formatter("MMM")
    private static let monthLong = formatter("MMMM")
    private static let weekdayShort = formatter("EEE")
    private static let weekdayFull = formatter("EEEE")
    private static let dayMonth = formatter("MMMd")
    private static let longDate = formatter("EEEEMMMMdyyyy")
    private static let monthDot = formatter("MMyyyy")

    static func monthTitle(_ ym: YearMonth) -> String { date(ym).map(monthYear.string(from:)) ?? ym.key }
    static func monthName(_ ym: YearMonth, short: Bool = false) -> String { date(ym).map((short ? monthShort : monthLong).string(from:)) ?? ym.key }
    static func weekday(_ day: String) -> String { Periods.date(day).map(weekdayShort.string(from:)) ?? "" }
    static func weekdayLong(_ day: String) -> String { Periods.date(day).map(weekdayFull.string(from:)) ?? "" }
    static func dayMonth(_ day: String) -> String { Periods.date(day).map(dayMonth.string(from:)) ?? day }
    static func longDate(_ day: String) -> String { Periods.date(day).map(longDate.string(from:)) ?? day }
    static func monthYearNumeric(_ day: String) -> String { Periods.date(day).map(monthDot.string(from:)) ?? "" }
    static func dayNumber(_ day: String) -> String { String(Int(day.suffix(2)) ?? 0) }
    static func range(_ p: Period) -> String { "\(dayMonth(p.from)) – \(dayMonth(p.to))" }

    private static func date(_ ym: YearMonth) -> Date? { Periods.date(Periods.dayKey(year: ym.year, month: ym.month, day: 1)) }
}

// MARK: - Small components

struct AmountText: View {
    var amount: Double
    var type: TxType
    var currency: String
    var font: Font = .body
    var body: some View {
        Text(Money.format(amount, currency: currency))
            .font(font.monospacedDigit())
            .foregroundStyle(Palette.color(type))
    }
}

struct CategoryIcon: View {
    var icon: String
    var size: CGFloat = 28
    var tint: Color = .secondary
    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.12))
            if icon.isEmpty {
                Image(systemName: "questionmark").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                Text(icon).font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
    }
}

struct AISparkle: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ai)
            .help("Added by your AI assistant")
            .accessibilityLabel("Added by AI")
    }
}

/// Income / Expenses / Balance hero cards shown above transaction lists.
struct TotalsStrip: View {
    var totals: Totals
    var currency: String
    var body: some View {
        HStack(spacing: 12) {
            StatCard(title: "Income", value: Money.format(totals.income, currency: currency), symbol: "arrow.down.left", tint: Palette.income)
            StatCard(title: "Expenses", value: Money.format(totals.expense, currency: currency), symbol: "arrow.up.right", tint: Palette.expense,
                     footnote: totals.income > 0 ? String(format: "%.0f%% of income", totals.expense / totals.income * 100) : nil,
                     ratio: totals.income > 0 ? totals.expense / totals.income : nil)
            StatCard(title: "Balance", value: Money.format(totals.total, currency: currency), symbol: "equal",
                     tint: totals.total < 0 ? Palette.expense : .accentColor, valueColor: .primary)
        }
    }
}

/// A single figure on a card: tinted glyph, caption, big rounded number, optional ratio bar.
struct StatCard: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color
    var valueColor: Color?
    var footnote: String?
    var ratio: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let footnote { Text(footnote).font(.caption).foregroundStyle(.tertiary) }
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor ?? tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let ratio {
                ProgressBar(ratio: ratio, tint: ratio > 1 ? Palette.expense : tint.opacity(0.8), height: 4)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct EmptyStateView: View {
    var title: String
    var symbol: String
    var message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

struct ProgressBar: View {
    var ratio: Double
    var tint: Color
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(tint).frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
    }
}

enum Surface {
    /// Soft page colour the cards sit on.
    static let page = Palette.dynamic(0xf3f3f6, 0x1c1c1f)
    static let card = Palette.dynamic(0xffffff, 0x2a2a2e)
    static let hover = Color.primary.opacity(0.045)
    static let radius: CGFloat = 14
    /// Readable width for list-style pages; wider windows get margins instead of stretched rows.
    static let contentWidth: CGFloat = 880
}

extension Font {
    /// Rounded figures for money.
    static func money(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Card styling used across dashboards.
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Surface.card, in: RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    /// Page background behind cards.
    func pageBackground() -> some View {
        background(Surface.page)
    }

    /// Centers content at a readable width.
    func readableWidth(_ width: CGFloat = Surface.contentWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
