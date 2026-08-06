import Charts
import SwiftUI
import ThoughtMeterKit

/// Time range filter for the dashboard.
enum DashboardRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"

    var id: String { rawValue }
    var dayCount: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

/// Everything one dashboard render needs, loaded off the live store.
struct DashboardStats {
    var total = 0
    var bySource: [(source: SourceRecord, keystrokes: Int)] = []
    var hourly: [Int] = Array(repeating: 0, count: 24)
    var daily: [(date: String, keystrokes: Int)] = []
    var sevenDayAverage: Int? // yesterday-back-7 average, for today comparison
    var peakHour: Int?

    var isEmpty: Bool { total == 0 }
}

/// Stateful wrapper: header, data loading, live refresh, share sheet.
/// The visual content lives in DashboardSections so it can also be rendered
/// offscreen (see PreviewRenderer).
struct DashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var range: DashboardRange = .today
    @State private var stats = DashboardStats()
    @State private var shareStats = DashboardStats()
    @State private var shareSheetShown = false
    @State private var shareAvailable = false
    /// Local date ("YYYY-MM-DD") being inspected after clicking a day in a
    /// by-day chart. Nil = the normal range view. `range` is preserved so
    /// Back returns to where the user came from.
    @State private var selectedDay: String?

    /// Keep the charts live while the window is open (stops with the view).
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let startupError = coordinator.startupError {
                    // Nothing is being recorded in this state — telling the
                    // user to "start typing" (the normal empty state) would
                    // blame them for a storage failure. Match the popover.
                    storageErrorState(startupError)
                } else {
                    DashboardSections(
                        stats: stats,
                        range: range,
                        // A past day with no input is a fact about that day,
                        // not a tracking problem to explain away.
                        inactiveReason: selectedDay == nil ? inactiveReason : nil,
                        dayDate: selectedDay,
                        onSelectDay: { date in
                            selectedDay = date
                            reload()
                        }
                    )
                }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
        .onReceive(refreshTimer) { _ in reload() }
        .sheet(isPresented: $shareSheetShown) {
            ShareCardSheet(stats: shareStats)
                .environmentObject(coordinator)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Thought Input")
                    .font(.title.weight(.semibold))
                Text(selectedDay.map(dayTitleLabel)
                     ?? "Keystrokes inside the tools you chose to track")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selectedDay {
                Button {
                    self.selectedDay = nil
                    reload()
                } label: {
                    Label("Back to \(range.rawValue)", systemImage: "chevron.left")
                }
                .help("Return to the \(range.rawValue) view")
                .accessibilityLabel("Back to \(range.rawValue), leaving \(dayTitleLabel(selectedDay))")
            } else {
                Picker("Range", selection: $range) {
                    ForEach(DashboardRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }

            Button {
                coordinator.refreshNow()
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                // The card's headline is "Today's Thought Input", so it must
                // always render today's stats — not the selected range's.
                shareStats = range == .today ? stats : loadStats(for: .today)
                shareSheetShown = true
            } label: {
                Label("Share Proof of Thought", systemImage: "square.and.arrow.up")
            }
            .disabled(!shareAvailable)
            .help("Share today's trace as an image")

            Button {
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    /// Why the empty state cannot be fixed by typing, when that is the case.
    /// The dashboard is a standalone window with no status row: a stopped or
    /// paused tracker must be named here, or the empty state blames the user
    /// ("start typing") for a pipeline that provably records nothing.
    private var inactiveReason: String? {
        if !coordinator.trackingHealthy {
            return "Tracking is stopped — Input Monitoring is missing or was lost. Re-grant it in System Settings ▸ Privacy & Security ▸ Input Monitoring."
        }
        if coordinator.isPaused {
            return "Tracking is paused. Resume it from the menu bar icon to keep counting."
        }
        if !coordinator.sources.contains(where: { $0.isEnabled }) {
            return "No tools are selected. Choose what to track in Settings ▸ Tracking."
        }
        return nil
    }

    private func storageErrorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Stopped — local database unavailable")
                .font(.title3.weight(.medium))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }

    // MARK: - Data

    private func reload() {
        if let selectedDay {
            stats = loadDayStats(selectedDay)
        } else {
            stats = loadStats(for: range)
        }
        // The card always renders TODAY's stats (see the share button), so
        // the button's empty-guard must check today too — the selected range,
        // or an inspected past day, can have data while today is still zero.
        let showingToday = selectedDay == nil && range == .today
        shareAvailable = showingToday ? !stats.isEmpty : todayHasInput()
    }

    /// One past day: the same shape as the Today view, for a fixed date.
    private func loadDayStats(_ date: String) -> DashboardStats {
        guard let store = coordinator.store else { return DashboardStats() }
        coordinator.flushNow()
        var next = DashboardStats()
        next.bySource = (try? store.totalsBySource(localDates: [date])) ?? []
        next.total = next.bySource.reduce(0) { $0 + $1.keystrokes }
        next.hourly = (try? store.hourlyTotals(forLocalDate: date)) ?? next.hourly
        if let maxCount = next.hourly.max(), maxCount > 0 {
            next.peakHour = next.hourly.firstIndex(of: maxCount)
        }
        return next
    }

    private func todayHasInput() -> Bool {
        guard let store = coordinator.store else { return false }
        let today = LocalDateProvider().localDateString(forUnixSeconds: Int64(Date().timeIntervalSince1970))
        let rows = (try? store.totalsBySource(localDates: [today])) ?? []
        return rows.contains { $0.keystrokes > 0 }
    }

    private func loadStats(for range: DashboardRange) -> DashboardStats {
        guard let store = coordinator.store else { return DashboardStats() }
        // Everything typed in the last flush interval is still in memory —
        // persist it first so the charts are current to the second.
        coordinator.flushNow()
        var next = DashboardStats()
        let provider = LocalDateProvider()
        let now = Int64(Date().timeIntervalSince1970)
        let dates = provider.recentLocalDates(count: range.dayCount, now: now)
        let today = provider.localDateString(forUnixSeconds: now)

        next.bySource = (try? store.totalsBySource(localDates: dates)) ?? []
        next.total = next.bySource.reduce(0) { $0 + $1.keystrokes }

        if range == .today {
            next.hourly = (try? store.hourlyTotals(forLocalDate: today)) ?? next.hourly
            if let maxCount = next.hourly.max(), maxCount > 0 {
                next.peakHour = next.hourly.firstIndex(of: maxCount)
            }
            // Trend + comparison need recent history regardless of range.
            // The comparison window is the 7 days ending YESTERDAY, so fetch
            // 8 dates (7 prior days + today) and split.
            let historyDates = provider.recentLocalDates(count: 8, now: now)
            let daily = (try? store.dailyTotals(localDates: historyDates)) ?? [:]
            let trendDates = Array(historyDates.dropFirst())
            next.daily = trendDates.map { ($0, daily[$0] ?? 0) }
            let previous = historyDates.dropLast()
            if !previous.isEmpty {
                let sum = previous.reduce(0) { $0 + (daily[$1] ?? 0) }
                let nonZeroDays = previous.filter { (daily[$0] ?? 0) > 0 }.count
                next.sevenDayAverage = nonZeroDays > 0 ? sum / nonZeroDays : nil
            }
        } else {
            let daily = (try? store.dailyTotals(localDates: dates)) ?? [:]
            next.daily = dates.map { ($0, daily[$0] ?? 0) }
        }
        return next
    }
}

/// The dashboard's visual content, purely a function of (stats, range).
struct DashboardSections: View {
    let stats: DashboardStats
    let range: DashboardRange
    /// Non-nil when tracking provably records nothing (permission lost,
    /// paused, no sources) — replaces the "start typing" advice, which
    /// cannot work in those states. Nil for offscreen preview renders.
    var inactiveReason: String? = nil
    /// Non-nil when these stats are one inspected past day rather than a
    /// range: the by-day chart and the "vs 7-day average" card belong to the
    /// range views, and the totals card names the date instead.
    var dayDate: String? = nil
    /// Called with a local date when a by-day bar is clicked. Nil (the
    /// default, used by offscreen preview renders) makes the bars inert.
    var onSelectDay: ((String) -> Void)? = nil

    /// Pins the hover readout open for `--render-previews`, which has no
    /// pointer: the tooltip is the one part of these charts a static render
    /// would otherwise never show, and Swift Charts has surprised this
    /// project before (D26). Nil in the app; hover drives it there.
    var previewHoveredHour: Int? = nil
    var previewHoveredDate: String? = nil

    /// Which bar the pointer is over, per chart.
    @State private var hoveredHour: Int?
    @State private var hoveredDate: String?

    private var activeHour: Int? { hoveredHour ?? previewHoveredHour }
    private var activeDate: String? { hoveredDate ?? previewHoveredDate }

    /// One calm hue for all marks: identity lives in labels, not color.
    private let barStyle = Color.accentColor

    private var isDayView: Bool { dayDate != nil }

    var body: some View {
        if stats.isEmpty {
            emptyState
        } else {
            summaryCards
            if range == .today || isDayView {
                hourlyChart
            } else {
                dayBarChart(title: "By day", height: 180)
            }
            sourceBreakdown
            if range == .today && !isDayView {
                dayBarChart(title: "Last 7 days", height: 140)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: inactiveReason == nil ? "keyboard" : "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(inactiveReason == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            Text(isDayView ? "Nothing recorded on this day" : "Nothing here yet")
                .font(.title3.weight(.medium))
            Text(emptyStateDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }

    private var emptyStateDetail: String {
        if isDayView {
            return "No Thought Input was recorded on this day."
        }
        return inactiveReason ?? "Start typing in a selected tool to see your Thought Input here."
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: totalCardTitle,
                value: CountFormatter.exact(stats.total),
                detail: "keystrokes"
            )
            // Both comparison cards describe a range; neither means anything
            // for a single inspected day.
            if !isDayView {
                if range == .today, let average = stats.sevenDayAverage, average > 0 {
                    StatCard(
                        title: "vs 7-day average",
                        value: comparisonText(average: average),
                        detail: "avg \(CountFormatter.compact(average))"
                    )
                } else if range != .today {
                    StatCard(
                        title: "Daily average",
                        value: CountFormatter.compact(stats.total / max(range.dayCount, 1)),
                        detail: "keystrokes / day"
                    )
                }
            }
            if let top = stats.bySource.first {
                StatCard(
                    title: "Top source",
                    value: top.source.displayName,
                    detail: CountFormatter.compact(top.keystrokes) + " keystrokes"
                )
            }
            if range == .today || isDayView, let peak = stats.peakHour {
                StatCard(
                    title: "Peak hour",
                    value: hourLabel(peak),
                    detail: CountFormatter.compact(stats.hourly[peak]) + " keystrokes"
                )
            }
        }
    }

    private var totalCardTitle: String {
        if isDayView { return "Day total" }
        return range == .today ? "Today’s Thought Input" : "Total (\(range.rawValue))"
    }

    private func comparisonText(average: Int) -> String {
        guard average > 0 else { return "—" }
        let ratio = Double(stats.total) / Double(average)
        let percent = Int(((ratio - 1) * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }

    // MARK: - Charts

    private var hourlyChart: some View {
        ChartCard(title: "By hour") {
            Chart {
                // Numeric x-axis: bar width must be fixed — .ratio()/.inset()
                // resolve against a categorical step that a numeric axis lacks,
                // producing invisible or hairline bars.
                ForEach(Array(stats.hourly.enumerated()), id: \.offset) { hour, count in
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Keystrokes", count),
                        width: .fixed(16)
                    )
                    .foregroundStyle(barStyle)
                    .cornerRadius(3)
                }
                if let hour = activeHour, stats.hourly.indices.contains(hour) {
                    hoverMarker(
                        x: .value("Hour", hour),
                        tooltip: HoverTooltip(
                            title: hourLabel(hour),
                            value: CountFormatter.exact(stats.hourly[hour]) + " keystrokes"
                        )
                    )
                }
            }
            .chartXScale(domain: -1...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(shortHourLabel(hour)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 160)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geometry[plotAnchor]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                hoveredHour = hour(at: phase, proxy: proxy, plot: plot)
                            }
                    }
                }
            }
        }
    }

    /// The by-day chart, shared by the 7/30-day "By day" view and Today's
    /// "Last 7 days" trend: same data shape, so same hover and click.
    /// The bar's x value is the full local date; the axis shows the short
    /// form, which keeps the click target unambiguous.
    private func dayBarChart(title: String, height: CGFloat) -> some View {
        ChartCard(title: title) {
            Chart {
                ForEach(stats.daily, id: \.date) { entry in
                    BarMark(
                        x: .value("Day", entry.date),
                        y: .value("Keystrokes", entry.keystrokes),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(barStyle)
                    .cornerRadius(3)
                }
                if let date = activeDate,
                   let entry = stats.daily.first(where: { $0.date == date }) {
                    hoverMarker(
                        x: .value("Day", entry.date),
                        tooltip: HoverTooltip(
                            title: dayTitleLabel(entry.date),
                            value: CountFormatter.exact(entry.keystrokes) + " keystrokes",
                            hint: onSelectDay == nil ? nil : "Click for this day"
                        )
                    )
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(String.self) { Text(shortDateLabel(date)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: height)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotAnchor = proxy.plotFrame {
                        let plot = geometry[plotAnchor]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                hoveredDate = day(at: phase, proxy: proxy, plot: plot)
                            }
                            // A click always follows a hover on macOS, so the
                            // hovered bar IS the clicked one — no second
                            // coordinate calculation to keep in sync.
                            .onTapGesture {
                                if let hoveredDate { onSelectDay?(hoveredDate) }
                            }
                    }
                }
            }
        }
    }

    /// Dashed marker plus floating readout for the hovered bar.
    /// The return type is pinned to `ChartContent` deliberately: the SDK also
    /// ships a 3-D chart API whose builder otherwise wins inference here and
    /// fails on `lineStyle`/`annotation`.
    private func hoverMarker<V: Plottable>(x: PlottableValue<V>,
                                           tooltip: HoverTooltip) -> some ChartContent {
        RuleMark(x: x)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Color.secondary.opacity(0.35))
            .annotation(
                position: AnnotationPosition.top,
                spacing: 4,
                // Keep the readout inside the card at the first and last bars.
                overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled)
            ) {
                tooltip
            }
    }

    // MARK: - Hover hit-testing

    /// Maps a pointer position to an hour bucket, or nil outside the plot.
    /// `value(atX:)` is relative to the plot area, not the chart view.
    private func hour(at phase: HoverPhase, proxy: ChartProxy, plot: CGRect) -> Int? {
        guard case .active(let point) = phase, plot.contains(point),
              let raw = proxy.value(atX: point.x - plot.minX, as: Double.self)
        else { return nil }
        let hour = Int(raw.rounded())
        return stats.hourly.indices.contains(hour) ? hour : nil
    }

    private func day(at phase: HoverPhase, proxy: ChartProxy, plot: CGRect) -> String? {
        guard case .active(let point) = phase, plot.contains(point),
              let date = proxy.value(atX: point.x - plot.minX, as: String.self),
              stats.daily.contains(where: { $0.date == date })
        else { return nil }
        return date
    }

    /// Row list instead of a bare chart: the app icon carries identity at a
    /// glance, the label names it, the thin bar carries magnitude, and the
    /// exact count is direct-labeled. One hue throughout.
    private var sourceBreakdown: some View {
        ChartCard(title: "By source") {
            let entries = Array(stats.bySource.prefix(8))
            let maxCount = entries.first?.keystrokes ?? 1
            VStack(spacing: 10) {
                ForEach(entries, id: \.source.id) { entry in
                    HStack(spacing: 10) {
                        SourceIcon(source: entry.source, size: 18)
                        Text(entry.source.displayName)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary.opacity(0.5))
                                Capsule()
                                    .fill(barStyle)
                                    .frame(width: max(4, proxy.size.width * CGFloat(entry.keystrokes) / CGFloat(max(maxCount, 1))))
                            }
                        }
                        .frame(height: 7)
                        Text(CountFormatter.exact(entry.keystrokes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                if stats.bySource.count > entries.count {
                    let remaining = stats.bySource.dropFirst(entries.count)
                    HStack {
                        Text("+ \(remaining.count) more")
                        Spacer()
                        Text(CountFormatter.exact(remaining.reduce(0) { $0 + $1.keystrokes }))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Labels

    private func hourLabel(_ hour: Int) -> String {
        let start = shortHourLabel(hour)
        let end = shortHourLabel((hour + 1) % 24)
        return "\(start)–\(end)"
    }

    private func shortHourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 1..<12: return "\(hour) AM"
        case 12: return "12 PM"
        default: return "\(hour - 12) PM"
        }
    }
}

// MARK: - Shared date labels

/// "2026-08-04" → "8/4". Built by hand rather than via DateFormatter so the
/// axis stays identical in offscreen preview renders regardless of locale.
private func shortDateLabel(_ localDate: String) -> String {
    let parts = localDate.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return localDate }
    return "\(month)/\(day)"
}

/// "2026-08-04" → "Tue, Aug 4, 2026". Used by the day-detail header and the
/// by-day tooltip, where the bare "8/4" would be too terse to orient by.
func dayTitleLabel(_ localDate: String) -> String {
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let parts = localDate.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return localDate }
    let base = "\(months[parts[1] - 1]) \(parts[2]), \(parts[0])"

    var components = DateComponents()
    components.year = parts[0]
    components.month = parts[1]
    components.day = parts[2]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    guard let date = calendar.date(from: components) else { return base }
    let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let index = calendar.component(.weekday, from: date) - 1
    guard weekdays.indices.contains(index) else { return base }
    return "\(weekdays[index]), \(base)"
}

/// Floating readout for the bar under the pointer. Never hit-testable: it
/// sits over the plot, and swallowing the pointer would cancel the very
/// hover that produced it (and any click on the bar beneath).
private struct HoverTooltip: View {
    let title: String
    let value: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        )
        .fixedSize()
        .allowsHitTesting(false)
    }
}

// MARK: - Building blocks

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
