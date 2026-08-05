import Foundation

/// Local-date ("YYYY-MM-DD") helpers. Activity buckets are stored with the
/// local date and timezone offset captured at recording time, so history
/// remains stable across timezone changes.
public struct LocalDateProvider {
    public var timeZone: TimeZone
    public var calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func localDateString(forUnixSeconds seconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    public func tzOffsetSeconds(forUnixSeconds seconds: Int64) -> Int {
        timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// The last `count` local dates ending at `now` (inclusive), oldest first.
    public func recentLocalDates(count: Int, now: Int64 = Int64(Date().timeIntervalSince1970)) -> [String] {
        let today = Date(timeIntervalSince1970: TimeInterval(now))
        var dates: [String] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                dates.append(localDateString(forUnixSeconds: Int64(day.timeIntervalSince1970)))
            }
        }
        return dates
    }

    /// Unix seconds for the start of tomorrow (used by "Pause until tomorrow").
    public func startOfTomorrow(now: Int64 = Int64(Date().timeIntervalSince1970)) -> Int64 {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        return Int64(tomorrow.timeIntervalSince1970)
    }
}

/// Formats keystroke counts for display. The unit is always keystrokes.
public enum CountFormatter {
    /// Compact form for the menu bar: 982 → "982", 12438 → "12.4K", 2400000 → "2.4M".
    public static func compact(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return String(count)
        case ..<1_000_000:
            let value = Double(count) / 1000.0
            return trimmed(value) + "K"
        default:
            let value = Double(count) / 1_000_000.0
            return trimmed(value) + "M"
        }
    }

    /// Exact form with thousands separators: 12438 → "12,438".
    public static func exact(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
