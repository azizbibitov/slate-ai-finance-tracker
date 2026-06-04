import Foundation

enum CurrencyFormatter {
    static func format(_ amount: Double, showSign: Bool = false) -> String {
        let abs = Swift.abs(amount)
        let digits = abs == abs.rounded() ? "\(Int(abs))" : String(format: "%.2f", abs)
        if showSign {
            return (amount >= 0 ? "+" : "-") + digits
        }
        return (amount < 0 ? "-" : "") + digits
    }
}
