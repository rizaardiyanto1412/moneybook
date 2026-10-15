import Foundation

/// Formats amounts in the user's ISO currency.
public enum Money {
    /// "$1,234.50" (or "−$12.00" when negative). `symbol: false` gives "1,234.50".
    public static func format(_ amount: Double, currency: String, symbol: Bool = true, locale: Locale = .current) -> String {
        let code = normalizedCode(currency)
        let digits = fractionDigits(code)
        if symbol {
            return amount.formatted(.currency(code: code).locale(locale).precision(.fractionLength(digits)))
        }
        return amount.formatted(.number.locale(locale).precision(.fractionLength(digits)).grouping(.automatic))
    }

    /// Compact axis/label form: "$1.2K".
    public static func compact(_ amount: Double, currency: String, locale: Locale = .current) -> String {
        let code = normalizedCode(currency)
        return amount.formatted(.currency(code: code).locale(locale).notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// The currency's symbol in the user's locale ("$", "Rp", "US$").
    public static func symbol(_ currency: String, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = normalizedCode(currency)
        return f.currencySymbol
    }

    /// Minor units used by the currency (2 for USD, 0 for JPY/KRW…).
    public static func fractionDigits(_ code: String) -> Int {
        switch normalizedCode(code) {
        // IDR has cents on paper only; nobody writes them.
        case "JPY", "KRW", "VND", "IDR", "CLP", "ISK", "HUF", "TWD", "UGX", "PYG", "XAF", "XOF": 0
        case "BHD", "KWD", "OMR", "JOD", "TND": 3
        default: 2
        }
    }

    public static func normalizedCode(_ code: String) -> String {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        return c.count == 3 ? c : "USD"
    }

    /// Parses user input like "1,234.5", "12,50" or "$ 3" into a positive amount.
    public static func parse(_ text: String, locale: Locale = .current) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        s = s.filter { $0.isNumber || String($0) == decimal || String($0) == grouping || $0 == "." || $0 == "," || $0 == "-" }
        // If only a comma is present and it looks like a decimal separator ("12,50"), treat it as one.
        if decimal == "." && !s.contains(".") && s.filter({ $0 == "," }).count == 1, let tail = s.split(separator: ",").last, tail.count <= 2 {
            s = s.replacingOccurrences(of: ",", with: ".")
        } else if decimal == "." {
            s = s.replacingOccurrences(of: ",", with: "")
        } else {
            s = s.replacingOccurrences(of: grouping, with: "").replacingOccurrences(of: decimal, with: ".")
        }
        guard let v = Double(s), v.isFinite else { return nil }
        return abs(v)
    }

    /// Common ISO currency codes for the picker (any 3-letter code also works).
    public static let commonCodes = ["USD", "EUR", "GBP", "JPY", "CNY", "KRW", "INR", "IDR", "SGD", "MYR", "THB", "PHP", "VND",
                                     "AUD", "NZD", "CAD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "TRY", "RUB", "UAH",
                                     "BRL", "MXN", "ARS", "CLP", "COP", "ZAR", "NGN", "EGP", "AED", "SAR", "ILS", "HKD", "TWD"]
}
