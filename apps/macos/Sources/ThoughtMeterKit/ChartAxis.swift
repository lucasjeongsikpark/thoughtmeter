import Foundation

/// Which x-axis values a by-day chart should label.
///
/// Swift Charts labels every categorical value by default, which turns the
/// 30-day chart into a row of overlapping dates at narrow window widths.
/// Picking evenly spaced ticks keeps the axis readable; the first value is
/// always labeled so the series stays anchored at its left edge.
///
/// Lives in the Kit rather than the app target because the test runner does
/// not depend on the app target.
public enum ChartAxisLabels {
    /// The subset of `values` to label: all of them when the series is short,
    /// otherwise every `ceil(count / maximum)`-th value starting at the first.
    /// A 30-day series therefore gets at most 8 labels.
    public static func evenlySpaced<Value>(_ values: [Value], maximum: Int = 8) -> [Value] {
        guard values.count > 10, maximum > 0 else { return values }
        let step = max(1, Int((Double(values.count) / Double(maximum)).rounded(.up)))
        return stride(from: 0, to: values.count, by: step).map { values[$0] }
    }
}
