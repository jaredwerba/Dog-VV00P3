import Charts
import SwiftUI
import VV00PCore

struct AnalyticsView: View {
    let range: HistoryRange
    let days: [HistoryRow]
    let unit: DistanceUnit
    var revealToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            chart("Distance", tint: .accentColor) { day in
                unit == .miles ? day.totals.distance / DistanceUnit.metersPerMile : day.totals.distance
            }
            movementChart
        }
    }

    private var movementChart: some View {
        let format: Date.FormatStyle = range == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
        let buckets = days.map { day in
            MovementBucket(
                id: day.id,
                label: day.start.formatted(format),
                kilometers: MovementAxis.kilometers(day.totals.distance),
                minutes: MovementAxis.minutes(day.totals.moving)
            )
        }
        return MovementBars(
            buckets: buckets,
            revealToken: revealToken,
            accessibilityLabel: "Kilometers and minutes by day"
        )
    }

    private func chart(
        _ title: String,
        tint: Color,
        value: @escaping (HistoryRow) -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .military(17, bold: true)
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.start, unit: .day),
                    y: .value(title, value(day))
                )
                .foregroundStyle(tint)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat, centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 140)
            .accessibilityLabel("\(title) by day")
        }
    }

    private var axisFormat: Date.FormatStyle {
        range == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
    }
}

struct DayMovementChart: View {
    let parts: [DayPartSummary]
    var revealToken = 0

    var body: some View {
        let buckets = parts.map { summary in
            MovementBucket(
                id: summary.part.order,
                label: summary.part.title,
                kilometers: MovementAxis.kilometers(summary.totals.distance),
                minutes: MovementAxis.minutes(summary.totals.moving)
            )
        }
        return MovementBars(
            buckets: buckets,
            revealToken: revealToken,
            accessibilityLabel: "Kilometers and minutes through the day"
        )
    }
}

/// Kilometers and minutes each fill the chart from their own peak.
private enum MovementAxis {
    static let kilometer = Color(red: 0.20, green: 0.84, blue: 0.38)
    static let minute = Color(red: 0.98, green: 0.72, blue: 0.22)

    static func kilometers(_ meters: Double) -> Double {
        meters / 1_000
    }

    static func minutes(_ seconds: Int) -> Double {
        Double(seconds) / 60
    }

    static func span(_ values: [Double]) -> Double {
        let peak = values.max() ?? 0
        return peak > 0 ? peak : 1
    }

    static func share(_ value: Double, span: Double) -> Double {
        guard span > 0 else { return 0 }
        return min(1, max(0, value / span))
    }

    static func kilometerText(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f km", value) }
        if value >= 1 { return String(format: "%.1f km", value) }
        return String(format: "%.2f km", value)
    }

    static func minuteText(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f min", value) }
        return String(format: "%.1f min", value)
    }
}

private struct MovementHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Movement")
                .military(17, bold: true)
            HStack(spacing: 16) {
                key("Kilometers", MovementAxis.kilometer)
                key("Minutes", MovementAxis.minute)
            }
        }
    }

    private func key(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .military(12)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MovementBucket<ID: Hashable>: Identifiable {
    var id: ID
    var label: String
    var kilometers: Double
    var minutes: Double
}

private struct MovementBars<ID: Hashable>: View {
    let buckets: [MovementBucket<ID>]
    let revealToken: Int
    let accessibilityLabel: String

    @State private var grow = 0.0
    @State private var onScreen = false

    private var showsFull: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot")
    }

    var body: some View {
        let shown = showsFull ? 1.0 : grow
        let kilometers = buckets.map(\.kilometers)
        let minutes = buckets.map(\.minutes)
        let kilometerSpan = MovementAxis.span(kilometers)
        let minuteSpan = MovementAxis.span(minutes)
        VStack(alignment: .leading, spacing: 16) {
            MovementHeading()
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("When", bucket.label),
                        y: .value("Share", MovementAxis.share(bucket.kilometers, span: kilometerSpan) * shown)
                    )
                    .foregroundStyle(by: .value("Series", "Kilometers"))
                    .position(by: .value("Series", "Kilometers"))
                }
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("When", bucket.label),
                        y: .value("Share", MovementAxis.share(bucket.minutes, span: minuteSpan) * shown)
                    )
                    .foregroundStyle(by: .value("Series", "Minutes"))
                    .position(by: .value("Series", "Minutes"))
                }
            }
            .chartForegroundStyleScale([
                "Kilometers": MovementAxis.kilometer,
                "Minutes": MovementAxis.minute
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(MovementAxis.kilometerText(number * kilometerSpan))
                                .military(10)
                                .foregroundStyle(MovementAxis.kilometer)
                        }
                    }
                }
                AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(MovementAxis.minuteText(number * minuteSpan))
                                .military(10)
                                .foregroundStyle(MovementAxis.minute)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .military(11)
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityLabel(accessibilityLabel)
        }
        .modifier(MovementViewport(onChange: updateVisibility))
        .onChange(of: revealToken) { _ in
            guard onScreen else { return }
            playGrow()
        }
        .onAppear {
            if showsFull {
                grow = 1
            }
        }
    }

    private func updateVisibility(_ visible: Bool) {
        onScreen = visible
        guard !showsFull else { return }
        if visible {
            playGrow()
        } else {
            grow = 0
        }
    }

    private func playGrow() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            grow = 0
        }
        withAnimation(.easeOut(duration: 0.75)) {
            grow = 1
        }
    }
}

private struct MovementViewport: ViewModifier {
    var onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollVisibilityChange(threshold: 0.4) { visible in
                onChange(visible)
            }
        } else {
            content.onAppear {
                onChange(true)
            }
        }
    }
}
