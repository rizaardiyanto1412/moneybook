import Foundation

/// A calendar month 'YYYY-MM'. With a custom month start day, "October" means Oct 25 – Nov 24 etc.
public struct YearMonth: Hashable, Comparable, Codable, Sendable, Identifiable {
    public var year: Int
    public var month: Int // 1...12

    public init(year: Int, month: Int) {
        let total = year * 12 + (month - 1)
        self.year = Int((Double(total) / 12).rounded(.down))
        self.month = total - self.year * 12 + 1
    }

    /// Parses 'YYYY-MM' (or a longer date string).
    public init?(_ key: String) {
        let parts = key.prefix(7).split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    public var id: String { key }
    public var key: String { String(format: "%04d-%02d", year, month) }
    public func adding(months n: Int) -> YearMonth { YearMonth(year: year, month: month + n) }
    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

/// An inclusive range of days, as 'YYYY-MM-DD' keys.
public struct Period: Hashable, Sendable {
    public var from: String
    public var to: String
    public init(from: String, to: String) { self.from = from; self.to = to }

    /// True when a 'YYYY-MM-DD…' date string falls inside the period.
    public func contains(_ date: String) -> Bool {
        let day = date.prefix(10)
        return day >= from && day <= to
    }
    public var days: [String] { Periods.days(from: from, to: to) }
}

public enum Periods {
    /// Gregorian calendar in UTC: day arithmetic on date keys without DST surprises.
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    public static func dayKey(year: Int, month: Int, day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midnight UTC of a 'YYYY-MM-DD' key.
    public static func date(_ key: String) -> Date? {
        let p = key.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    public static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return dayKey(year: c.year!, month: c.month!, day: c.day!)
    }
    public static func addDays(_ key: String, _ n: Int) -> String {
        guard let d = date(key), let r = calendar.date(byAdding: .day, value: n, to: d) else { return key }
        return Self.key(r)
    }
    /// 1 = Sunday … 7 = Saturday.
    public static func weekday(_ key: String) -> Int {
        guard let d = date(key) else { return 1 }
        return calendar.component(.weekday, from: d)
    }
    public static func days(from: String, to: String) -> [String] {
        var out: [String] = []
        var k = from
        while k <= to && out.count < 400 { out.append(k); k = addDays(k, 1) }
        return out
    }

    /// The period a "month" covers, honoring month_start_day S (1…28), matching the server and
    /// Money Manager: with S < 20 "2026-03" runs Mar S – Apr S-1; with S >= 20 a period is named
    /// after the month it ends in, so "2026-03" runs Feb S – Mar S-1.
    public static func month(_ ym: YearMonth, startDay: Int = 1) -> Period {
        let s = min(max(startDay, 1), 28)
        let start = s >= 20 ? ym.adding(months: -1) : ym
        let next = start.adding(months: 1)
        let from = dayKey(year: start.year, month: start.month, day: s)
        let nextStart = dayKey(year: next.year, month: next.month, day: s)
        return Period(from: from, to: addDays(nextStart, -1))
    }

    /// The financial year: the January period through the December period.
    public static func year(_ year: Int, startDay: Int = 1) -> Period {
        Period(from: month(YearMonth(year: year, month: 1), startDay: startDay).from,
               to: month(YearMonth(year: year, month: 12), startDay: startDay).to)
    }

    /// Which "month" a local date belongs to (inverse of `month(_:startDay:)`).
    public static func yearMonth(containing dayKey: String, startDay: Int = 1) -> YearMonth {
        guard let ym = YearMonth(dayKey) else { return YearMonth(year: 2000, month: 1) }
        let s = min(max(startDay, 1), 28)
        let day = Int(dayKey.dropFirst(8).prefix(2)) ?? 1
        let startMonth = day >= s ? ym : ym.adding(months: -1)
        return s >= 20 ? startMonth.adding(months: 1) : startMonth
    }

    /// Today's date key in the given (or current) time zone.
    public static func today(_ now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let comps = c.dateComponents([.year, .month, .day], from: now)
        return dayKey(year: comps.year!, month: comps.month!, day: comps.day!)
    }

    /// 'YYYY-MM-DDTHH:MM' for a Date in the given time zone.
    public static func localStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let p = c.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!)
    }
    /// Inverse of `localStamp`.
    public static func parseStamp(_ s: String, timeZone: TimeZone = .current) -> Date? {
        let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 3 else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c.date(from: DateComponents(year: nums[0], month: nums[1], day: nums[2],
                                           hour: nums.count > 3 ? nums[3] : 12, minute: nums.count > 4 ? nums[4] : 0))
    }

    /// Splits a period into weeks starting on `firstWeekday` (1 = Sunday), clipped to the period.
    public static func weeks(in period: Period, firstWeekday: Int) -> [Period] {
        var out: [Period] = []
        var start = period.from
        while start <= period.to {
            let offset = (weekday(start) - firstWeekday + 7) % 7
            let weekEnd = addDays(start, 6 - offset)
            let end = min(weekEnd, period.to)
            out.append(Period(from: start, to: end))
            start = addDays(end, 1)
        }
        return out
    }

    /// Calendar grid cells for a period: whole weeks, `nil` for padding days outside the period.
    public static func calendarGrid(_ period: Period, firstWeekday: Int) -> [String?] {
        let lead = (weekday(period.from) - firstWeekday + 7) % 7
        var cells: [String?] = Array(repeating: nil, count: lead)
        cells += period.days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Weekday symbols ordered from `firstWeekday`.
    public static func weekdaySymbols(firstWeekday: Int, locale: Locale = .current) -> [String] {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        let s = c.shortWeekdaySymbols
        return (0..<7).map { s[(firstWeekday - 1 + $0) % 7] }
    }
}
