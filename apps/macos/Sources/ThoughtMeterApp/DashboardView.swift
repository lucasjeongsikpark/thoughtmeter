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

struct DashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var range: DashboardRange = .today
    @State private var stats = DashboardStats()
    @State private var shareSheetShown = false

    /// One calm hue for all marks: identity lives in labels, not color.
    private let barStyle = Color.accentColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if stats.isEmpty {
                    emptyState
                } else {
                    summaryCards
                    if range == .today {
                        hourlyChart
                    } else {
                        dailyChart
                    }
                    sourceBreakdown
                    if range == .today {
                        weekTrend
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
        .sheet(isPresented: $shareSheetShown) {
            ShareCardSheet(stats: stats)
                .environmentObject(coordinator)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Human Input")
                    .font(.title.weight(.semibold))
                Text("Keystrokes inside the tools you chose to track")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(DashboardRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            Button {
                coordinator.refreshNow()
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button("Share…") { shareSheetShown = true }
                .disabled(stats.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.title3.weight(.medium))
            Text("Start typing in a selected tool to see your Human Input here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: range == .today ? "Today’s Human Input" : "Total (\(range.rawValue))",
                value: HumanInputFormatter.exact(stats.total),
                detail: "keystrokes"
            )
            if range == .today, let average = stats.sevenDayAverage, average > 0 {
                StatCard(
                    title: "vs 7-day average",
                    value: comparisonText(average: average),
                    detail: "avg \(HumanInputFormatter.compact(average))"
                )
            } else if range != .today {
                StatCard(
                    title: "Daily average",
                    value: HumanInputFormatter.compact(stats.total / max(range.dayCount, 1)),
                    detail: "keystrokes / day"
                )
            }
            if let top = stats.bySource.first {
                StatCard(
                    title: "Top source",
                    value: top.source.displayName,
                    detail: HumanInputFormatter.compact(top.keystrokes) + " keystrokes"
                )
            }
            if range == .today, let peak = stats.peakHour {
                StatCard(
                    title: "Peak hour",
                    value: hourLabel(peak),
                    detail: HumanInputFormatter.compact(stats.hourly[peak]) + " keystrokes"
                )
            }
        }
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
            Chart(Array(stats.hourly.enumerated()), id: \.offset) { hour, count in
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Keystrokes", count),
                    width: .ratio(0.62)
                )
                .foregroundStyle(barStyle)
                .cornerRadius(3)
            }
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
        }
    }

    private var dailyChart: some View {
        ChartCard(title: "By day") {
            Chart(stats.daily, id: \.date) { entry in
                BarMark(
                    x: .value("Day", shortDateLabel(entry.date)),
                    y: .value("Keystrokes", entry.keystrokes),
                    width: .ratio(0.62)
                )
                .foregroundStyle(barStyle)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
    }

    private var sourceBreakdown: some View {
        ChartCard(title: "By source") {
            let entries = Array(stats.bySource.prefix(8))
            Chart(entries, id: \.source.id) { entry in
                BarMark(
                    x: .value("Keystrokes", entry.keystrokes),
                    y: .value("Source", entry.source.displayName),
                    height: .ratio(0.6)
                )
                .foregroundStyle(barStyle)
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text(HumanInputFormatter.compact(entry.keystrokes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel() }
            }
            .frame(height: CGFloat(entries.count) * 34 + 16)
        }
    }

    private var weekTrend: some View {
        ChartCard(title: "Last 7 days") {
            Chart(stats.daily, id: \.date) { entry in
                BarMark(
                    x: .value("Day", shortDateLabel(entry.date)),
                    y: .value("Keystrokes", entry.keystrokes),
                    width: .ratio(0.62)
                )
                .foregroundStyle(barStyle)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: - Data

    private func reload() {
        guard let store = coordinator.store else { return }
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
            // Trend + comparison need the previous week regardless of range.
            let trendDates = provider.recentLocalDates(count: 7, now: now)
            let daily = (try? store.dailyTotals(localDates: trendDates)) ?? [:]
            next.daily = trendDates.map { ($0, daily[$0] ?? 0) }
            let previous = trendDates.dropLast()
            if !previous.isEmpty {
                let sum = previous.reduce(0) { $0 + (daily[$1] ?? 0) }
                let nonZeroDays = previous.filter { (daily[$0] ?? 0) > 0 }.count
                next.sevenDayAverage = nonZeroDays > 0 ? sum / nonZeroDays : nil
            }
        } else {
            let daily = (try? store.dailyTotals(localDates: dates)) ?? [:]
            next.daily = dates.map { ($0, daily[$0] ?? 0) }
        }
        stats = next
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

    private func shortDateLabel(_ localDate: String) -> String {
        // "2026-08-04" → "8/4"
        let parts = localDate.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return localDate }
        return "\(month)/\(day)"
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
