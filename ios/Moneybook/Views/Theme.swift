import MoneybookCore
import SwiftUI
import UIKit

// SwiftUI also exports `Transaction`; ours wins inside this module.
typealias Transaction = MoneybookCore.Transaction
typealias Category = MoneybookCore.Category

/// Money Manager's "white" theme, the same values as the web app (web/styles.css).
enum MM {
    static let accent = dyn(0xff6254, 0xff6254)
    static let accentPress = dyn(0xf04c3e, 0xf04c3e)
    static let inc = dyn(0x1f88ff, 0x3a95ff)
    static let exp = dyn(0xff603b, 0xff6a4a)
    static let xfer = dyn(0x4b4b4b, 0x8a8a8e)
    static let bg = dyn(0xffffff, 0x1c1c1e)
    static let bg2 = dyn(0xf7f7fa, 0x111112)
    static let fg = dyn(0x000000, 0xffffff)
    static let fgNote = dyn(0x4b4b4b, 0xe2e2e4)
    static let fg2 = dyn(0x7b7b7b, 0x9a9a9e)
    static let fg3 = dyn(0x8d8d8d, 0x6e6e73)
    static let chip = dyn(0x8d8d8d, 0x5a5a5e)
    static let line = dyn(0xd5d5d5, 0x2c2c2e)
    static let today = dyn(0x3f4671, 0x5b64a8)
    static let chrome = dyn(0xffffff, 0x2a2a2d)
    static let tabBar = dyn(0xf7f7fa, 0x2a2a2d)
    static let tabIdle = dyn(0xa5a5a5, 0xa5a5a5)
    static let sat = dyn(0x58a6ff, 0x3a95ff)
    static let sun = dyn(0xff796e, 0xff6a4a)
    static let label = dyn(0x747474, 0x9a9a9e)
    static let warn = dyn(0xf5a524, 0xf5a524)
    static let pressed = dyn(0xfff1ed, 0x3a2a28)
    static let ai = dyn(0xa970ff, 0xa970ff)

    /// Pie colours in slice order (Money Manager's Highcharts palette).
    static let chart: [Color] = [0xfd6e63, 0xff9750, 0xfed042, 0xfee700, 0xc1e746, 0x72d36c, 0x66e9db, 0x72b8e3, 0xa588d6, 0xed7ddc, 0xe373a2]
        .map { dyn($0, $0) }
    static func chartColor(_ i: Int) -> Color { chart[i % chart.count] }

    static func color(_ type: TxType) -> Color {
        switch type {
        case .income: inc
        case .expense: exp
        case .transfer: xfer
        }
    }

    // nonisolated: SwiftUI resolves dynamic colours on its render thread during animations.
    nonisolated static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable t in
            let hex = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}

// MARK: - Formatting (mirrors web/js/format.js)

enum Fmt {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let dow = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "Rp 13,170,000" / "Rp -9,279,900": narrow symbol, a space, then the number (Money Manager's style).
    static func money(_ v: Double, _ currency: String) -> String {
        let sign = v < 0 ? "-" : ""
        return "\(symbol(currency)) \(sign)\(num(abs(v), currency))"
    }

    /// "1,234.50" without the symbol.
    static func num(_ v: Double, _ currency: String) -> String {
        let d = Money.fractionDigits(currency)
        return v.formatted(.number.precision(.fractionLength(d)).grouping(.automatic))
    }

    /// Calendar cells: "6.6M", "854.1K", "3,000".
    static func compact(_ v: Double, _ currency: String) -> String {
        let a = abs(v)
        if a >= 100_000 { return v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }
        if a >= 1000 { return v.formatted(.number.precision(.fractionLength(0))) }
        return num(v, currency)
    }

    private static var symbols: [String: String] = [:]
    /// "Rp" for IDR, "$" for USD, "₩" for KRW.
    static func symbol(_ code: String) -> String {
        let code = Money.normalizedCode(code)
        if let s = symbols[code] { return s }
        let skip: Set<Character> = [".", ",", "-", "\u{00a0}"]
        let formatted: String = Double(0).formatted(.currency(code: code).presentation(.narrow))
        let s = String(formatted.filter { c in !c.isNumber && !c.isWhitespace && !skip.contains(c) })
        symbols[code] = s.isEmpty ? code : s
        return symbols[code]!
    }

    static func ymd(_ key: String) -> (y: Int, m: Int, d: Int) {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return (p.count > 0 ? p[0] : 2000, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }
    /// "Oct 2026"
    static func monthLabel(_ ym: YearMonth) -> String { "\(months[ym.month - 1]) \(ym.year)" }
    /// "10/1 ~ 10/31"
    static func shortRange(_ from: String, _ to: String) -> String {
        let f = ymd(from), t = ymd(to)
        return "\(f.m)/\(f.d) ~ \(t.m)/\(t.d)"
    }
    /// "10/25" (zero-padded)
    static func md(_ key: String) -> String { "\(key.dropFirst(5).prefix(2))/\(key.dropFirst(8).prefix(2))" }
    /// 0 = Sunday
    static func weekday(_ key: String) -> Int { Periods.weekday(key) - 1 }
    /// "2026/10/14 (Wed)"
    static func entryDate(_ key: String) -> String { "\(key.replacingOccurrences(of: "-", with: "/")) (\(dow[weekday(key)]))" }
    /// "Wednesday, 14 October"
    static func longDay(_ key: String) -> String {
        guard let d = Periods.date(key) else { return key }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }
}

// MARK: - Icons

/// The web app's line icons (exported by scripts/export-icons.mjs into Assets.xcassets/Icons).
struct Icon: View {
    var name: String
    var size: CGFloat = 22
    init(_ name: String, size: CGFloat = 22) { self.name = name; self.size = size }
    var body: some View {
        Image("mm.\(name)").resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
    }
}

/// A 44 pt round-highlight icon button.
struct IconButton: View {
    var icon: String
    var size: CGFloat = 22
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(icon, size: size).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MM.fg)
        .accessibilityLabel(label)
    }
}

// MARK: - Chrome

struct Hairline: View {
    var color: Color = MM.line
    var body: some View { color.frame(height: 1 / UIScreen.main.scale).frame(maxWidth: .infinity) }
}

struct Line: View {
    var body: some View { MM.line.frame(height: 1).frame(maxWidth: .infinity) }
}

/// 46 pt header bar: left slot, centred title, right slot.
struct HeaderBar<L: View, C: View, R: View>: View {
    var sideWidth: CGFloat = 88
    @ViewBuilder var left: L
    @ViewBuilder var center: C
    @ViewBuilder var right: R
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) { left; Spacer(minLength: 0) }.frame(width: sideWidth)
            center.frame(maxWidth: .infinity)
            HStack(spacing: 0) { Spacer(minLength: 0); right }.frame(width: sideWidth)
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
    }
}

extension HeaderBar where L == EmptyView, R == EmptyView, C == HeaderTitle {
    init(_ title: String) {
        self.init(left: { EmptyView() }, center: { HeaderTitle(title) }, right: { EmptyView() })
    }
}

struct HeaderTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 17.5, weight: .semibold)).lineLimit(1).foregroundStyle(MM.fg) }
}

/// Header for pushed pages: "‹ back" on the left, title, optional right content.
struct PageHeader<R: View>: View {
    var title: String
    var backLabel: String?
    @ViewBuilder var right: R
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HeaderBar(left: {
            Button { dismiss() } label: {
                HStack(spacing: 0) {
                    Icon("left", size: 24)
                    if let backLabel { Text(backLabel).font(.system(size: 16)) }
                }
                .frame(minHeight: 44)
                .padding(.leading, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MM.fg)
            .accessibilityLabel("Back")
        }, center: { HeaderTitle(title) }, right: { right })
        .background(MM.chrome)
    }
}

extension PageHeader where R == EmptyView {
    init(title: String, backLabel: String? = nil) {
        self.init(title: title, backLabel: backLabel, right: { EmptyView() })
    }
}

/// ‹ Oct 2026 ›
struct MonthSwitcher: View {
    var label: String
    var onStep: (Int) -> Void
    var onToday: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button { onStep(-1) } label: { Icon("left", size: 20).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("Previous")
            Spacer(minLength: 0)
            Text(label).font(.system(size: 16.5)).monospacedDigit().frame(minWidth: 96)
                .onTapGesture { onToday?() }
            Spacer(minLength: 0)
            Button { onStep(1) } label: { Icon("right", size: 20).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(MM.fg)
        .padding(.horizontal, 6)
        .frame(height: 40)
    }
}

/// Text tabs with a coral underline (Daily / Calendar / …).
struct SubTabs<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T
    var fontSize: CGFloat = 15
    var height: CGFloat = 40
    var idle: Color = MM.fg3
    var boldSelected = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { key, label in
                let on = key == selection
                Button { selection = key } label: {
                    Text(label)
                        .font(.system(size: fontSize, weight: on && boldSelected ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(on ? MM.fg : idle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .overlay(alignment: .bottom) { if on { MM.accent.frame(height: 3) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Line() }
    }
}

/// Income / Expenses / Total strip.
struct Strip: View {
    @Environment(AppModel.self) private var model
    var items: [(String, Double, Color)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 1) {
                    Text(item.0).font(.system(size: 13)).foregroundStyle(MM.fgNote)
                    Text(Fmt.money(item.1, model.currency))
                        .font(.system(size: 15.5).monospacedDigit())
                        .foregroundStyle(item.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(MM.chrome)
        .overlay(alignment: .bottom) { Line() }
    }

    static func incExpTotal(_ t: Totals) -> [(String, Double, Color)] {
        [("Income", t.income, MM.inc), ("Expenses", t.expense, MM.exp), ("Total", t.total, MM.fg)]
    }
}

struct EmptyText: View {
    var emoji: String?
    var text: String
    var body: some View {
        VStack(spacing: 10) {
            if let emoji { Text(emoji).font(.system(size: 40)) }
            Text(text).font(.system(size: 15)).foregroundStyle(MM.fg3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 64)
    }
}

/// Rows that highlight while pressed, like `:active { background: var(--bg2) }`.
struct PressStyle: ButtonStyle {
    var pressed: Color = MM.bg2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? pressed : Color.clear, ignoresSafeAreaEdges: [])
    }
}

/// Primary / ghost buttons of the forms and sheets.
struct MMButton: View {
    enum Kind { case primary, ghost, danger }
    var title: String
    var icon: String?
    var kind: Kind = .primary
    var tint: Color = MM.accent
    var height: CGFloat = 48
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 19) }
                Text(title).font(.system(size: kind == .primary ? 16.5 : 15, weight: kind == .primary ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(kind == .primary ? .white : kind == .danger ? MM.exp : MM.fg)
            .background(kind == .primary ? tint : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay { if kind != .primary { RoundedRectangle(cornerRadius: 10).strokeBorder(MM.line, lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bottom-sheet title row: optional left/right buttons around a centred title.
struct SheetHeader<R: View>: View {
    var title: String
    @ViewBuilder var right: R
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: { Icon("close", size: 20).frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(MM.fg).frame(width: 64, alignment: .leading)
            Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity)
            HStack(spacing: 0) { Spacer(minLength: 0); right }.frame(width: 64)
        }
        .padding(.horizontal, 6)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Line() }
    }
}

extension SheetHeader where R == EmptyView {
    init(title: String) { self.init(title: title, right: { EmptyView() }) }
}

/// Text field styled like the web `.input`.
struct InputField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text).keyboardType(keyboard) }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(MM.bg2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MM.line, lineWidth: 1.5))
    }
}

struct FieldLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(MM.fg2).padding(.horizontal, 2).padding(.top, 12).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two- or more-way pill switch (web `.seg`).
struct Seg<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { k, l in
                Button { selection = k } label: {
                    Text(l).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(k == selection ? MM.fg : MM.fg2)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(k == selection ? MM.bg : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .shadow(color: k == selection ? .black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MM.bg2, in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Re-enables the swipe-back gesture on stacks whose navigation bar is hidden (we draw our own headers).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
