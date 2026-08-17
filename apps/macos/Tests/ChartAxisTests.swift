import Foundation
import ThoughtMeterKit

/// The by-day chart's x-axis labels. Swift Charts labels every categorical
/// value by default, which overlaps on the 30-day chart.
let chartAxisTests: [TC] = [
    TC("a 7-day series labels every day") { t in
        let dates = (1...7).map { String(format: "2026-08-%02d", $0) }
        t.expectEqual(ChartAxisLabels.evenlySpaced(dates), dates)
    },
    TC("a 10-day series still labels every day") { t in
        let dates = (1...10).map { String(format: "2026-08-%02d", $0) }
        t.expectEqual(ChartAxisLabels.evenlySpaced(dates).count, 10)
    },
    TC("a 30-day series is thinned to at most 8 evenly spaced labels") { t in
        let dates = (1...30).map { String(format: "2026-08-%02d", $0) }
        let labeled = ChartAxisLabels.evenlySpaced(dates)
        t.expect(labeled.count <= 8, "expected at most 8 labels, got \(labeled.count)")
        t.expectEqual(labeled.first, dates.first, "the first date is always labeled")
        t.expect(labeled.allSatisfy { dates.contains($0) }, "labels must be real dates")
        // Evenly spaced: every gap is the same step.
        let indices = labeled.compactMap { dates.firstIndex(of: $0) }
        let steps = Set(zip(indices, indices.dropFirst()).map { $1 - $0 })
        t.expectEqual(steps.count, 1, "labels must be evenly spaced, got steps \(steps)")
    },
    TC("an empty series has nothing to label") { t in
        t.expect(ChartAxisLabels.evenlySpaced([String]()).isEmpty)
    },
]
