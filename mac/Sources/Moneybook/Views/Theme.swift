import AppKit
import MoneybookCore
import SwiftUI

/// SDK 27's SwiftUI declares `@State` as a macro whose plugin ships only with Xcode, so under
/// Command Line Tools we reach the property wrapper through this alias instead.
typealias UIState = SwiftUI.State

// SwiftUI and the ObjC runtime also export `Transaction`/`Category`; ours win inside this module.
typealias Transaction = MoneybookCore.Transaction
typealias Category = MoneybookCore.Category

/// The web app's colours (web/styles.css `:root`), light and dark.
enum MB {
    static let accent = Palette.dynamic(0xff6254, 0xff6254)
    static let accentPress = Palette.dynamic(0xf04c3e, 0xf04c3e)
    static let inc = Palette.dynamic(0x1f88ff, 0x3a95ff)
    static let exp = Palette.dynamic(0xff603b, 0xff6a4a)
    static let xfer = Palette.dynamic(0x4b4b4b, 0x8a8a8e)
    static let bg = Palette.dynamic(0xffffff, 0x1c1c1e)
    static let bg2 = Palette.dynamic(0xf7f7fa, 0x111112)
    static let fg = Palette.dynamic(0x000000, 0xffffff)
    static let fgNote = Palette.dynamic(0x4b4b4b, 0xe2e2e4)
    static let fg2 = Palette.dynamic(0x7b7b7b, 0x9a9a9e)
    static let fg3 = Palette.dynamic(0x8d8d8d, 0x6e6e73)
    static let chip = Palette.dynamic(0x8d8d8d, 0x5a5a5e)
    static let line = Palette.dynamic(0xd5d5d5, 0x2c2c2e)
    static let today = Palette.dynamic(0x3f4671, 0x5b64a8)
    static let chrome = Palette.dynamic(0xffffff, 0x2a2a2d)
    static let sat = Palette.dynamic(0x58a6ff, 0x3a95ff)
    static let sun = Palette.dynamic(0xff796e, 0xff6a4a)
    /// Window background around the centred panes.
    static let desk = Palette.dynamic(0xf7f7fa, 0x0b0b0c)
    static let overlay = Palette.dynamic(0x000000, 0x000000).opacity(0.35)
    /// Money Manager's pie colours, in slice order.
    static let chart: [Color] = [0xfd6e63, 0xff9750, 0xfed042, 0xfee700, 0xc1e746, 0x72d36c, 0x66e9db, 0x72b8e3, 0xa588d6, 0xed7ddc, 0xe373a2]
        .map { Palette.dynamic($0, $0) }
    static func chartColor(_ i: Int) -> Color { chart[i % chart.count] }
}

/// Money Manager's colour language.
enum Palette {
    static let income = MB.inc
    static let expense = MB.exp
    static let transfer = MB.xfer
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
    private static let monthYearShort = formatter("MMMyyyy")
    private static let monthShort = formatter("MMM")
    private static let monthLong = formatter("MMMM")
    private static let weekdayShort = formatter("EEE")
    private static let weekdayFull = formatter("EEEE")
    private static let dayMonth = formatter("MMMd")
    private static let longDate = formatter("EEEEMMMMdyyyy")
    private static let monthDot = formatter("MMyyyy")

    static func monthTitle(_ ym: YearMonth) -> String { date(ym).map(monthYear.string(from:)) ?? ym.key }
    /// "Oct 2026", like the web app's month switcher.
    static func monthLabel(_ ym: YearMonth) -> String { date(ym).map(monthYearShort.string(from:)) ?? ym.key }
    /// "10/1 ~ 10/31"
    static func shortRange(_ p: Period) -> String {
        func md(_ d: String) -> String { "\(Int(d.dropFirst(5).prefix(2)) ?? 0)/\(Int(d.suffix(2)) ?? 0)" }
        return "\(md(p.from)) ~ \(md(p.to))"
    }
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

extension Font {
    /// Rounded figures for money.
    static func money(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
