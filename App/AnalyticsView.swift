import Charts
import SwiftUI
import VV00PCore

struct AnalyticsView: View {
    let range: HistoryRange
    let days: [HistoryRow]
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            chart("Distance", tint: .accentColor) { day in
                unit == .miles ? day.totals.distance / DistanceUnit.metersPerMile : day.totals.distance
            }
            movementChart
        }
    }

    private var movementChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Movement")
                .military(17, bold: true)
            Chart {
                ForEach(days) { day in
                    LineMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Minutes", Double(day.totals.resting) / 60),
                        series: .value("State", "Resting")
                    )
                    .foregroundStyle(by: .value("State", "Resting"))
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
                    LineMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Minutes", Double(day.totals.moving) / 60),
                        series: .value("State", "Moving")
                    )
                    .foregroundStyle(by: .value("State", "Moving"))
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
                }
            }
            .chartForegroundStyleScale([
                "Resting": Color.secondary,
                "Moving": Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat, centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
            .accessibilityLabel("Resting and moving by day")
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Movement")
                .military(17, bold: true)
            Chart(parts) { summary in
                LineMark(
                    x: .value("Part", summary.part.order),
                    y: .value("Minutes", Double(summary.totals.resting) / 60),
                    series: .value("State", "Resting")
                )
                .foregroundStyle(by: .value("State", "Resting"))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
                LineMark(
                    x: .value("Part", summary.part.order),
                    y: .value("Minutes", Double(summary.totals.moving) / 60),
                    series: .value("State", "Moving")
                )
                .foregroundStyle(by: .value("State", "Moving"))
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
            }
            .chartForegroundStyleScale([
                "Resting": Color.secondary,
                "Moving": Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: [0, 1, 2]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let order = value.as(Int.self), DayPart.allCases.indices.contains(order) {
                            Text(DayPart.allCases[order].title)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
            .accessibilityLabel("Resting and moving through the day")
        }
    }
}
