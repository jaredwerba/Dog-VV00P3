import SwiftUI
import VV00PCore

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = StrapSession()
    @State private var showCalibration = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DogPhotoPicker()
                    VStack(alignment: .leading, spacing: 28) {
                        statusBlock
                        metricRings
                        healthCard
                        periodPicker
                        if session.range == .day {
                            dailyLog
                            historyList
                        } else {
                            AnalyticsView(range: session.range, days: session.chartDays, unit: session.unit)
                        }
                        calibrateButton
                        strideTuner
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle(periodTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showCalibration) {
                CalibrationSheet(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Distance", selection: unitBinding) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Distance unit")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlBar
            }
        }
        .environment(\.font, MilitaryFont.text(17))
        .onAppear {
            MilitaryFont.register()
            MovementAlertCenter.shared.install()
            if !ProcessInfo.processInfo.arguments.contains("--screenshot") {
                MovementAlertCenter.shared.requestPermission()
            }
            if ProcessInfo.processInfo.arguments.contains("--week") {
                session.setRange(.week)
            } else if ProcessInfo.processInfo.arguments.contains("--month") {
                session.setRange(.month)
            }
            if ProcessInfo.processInfo.arguments.contains("--connect") {
                session.connect()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                session.reloadHistory()
            } else {
                session.flushHistory()
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.deviceName)
                .military(20, bold: true)
            Text(session.status)
                .foregroundStyle(.secondary)
            if session.connected {
                Text(session.motionLabel)
                    .military(15, bold: true)
                    .foregroundStyle(motionColor)
            }
            if session.sampleCount > 0 {
                Text("\(session.sampleCount) samples")
                    .military(12)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !session.motionNote.isEmpty {
                Text(session.motionNote)
                    .military(15)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Period", selection: rangeBinding) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            Text(periodTitle)
                .military(15)
                .foregroundStyle(.secondary)
        }
    }

    private var metricRings: some View {
        HStack(alignment: .top, spacing: 10) {
            MetricRing(
                title: "Distance",
                value: session.unit.text(meters: session.period.distance),
                caption: "of 1 mi",
                progress: min(1, session.period.distance / DistanceUnit.metersPerMile),
                tint: Color(red: 0.45, green: 0.74, blue: 0.98)
            )
            MetricRing(
                title: "Resting",
                value: duration(session.period.resting),
                caption: "of recorded",
                progress: recordedShare(session.period.resting),
                tint: .green
            )
            MetricRing(
                title: "Moving",
                value: duration(goalSeconds),
                caption: "of 30m",
                progress: min(1, Double(goalSeconds) / Double(Bulldog.dailyMovingSeconds)),
                tint: .blue
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(healthTitle)
                .military(20, bold: true)
            Text(healthBody)
                .military(15)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var healthTitle: String {
        session.todayTotals.moving >= Bulldog.dailyMovingSeconds ? "Day covered" : "Today"
    }

    private var healthBody: String {
        let today = session.range == .day ? session.period : session.todayTotals
        let week = session.weekTotals
        let remaining = max(0, Bulldog.dailyMovingSeconds - today.moving)
        let todayLine = "Today Max has \(session.unit.text(meters: today.distance)), \(duration(today.resting)) resting, and \(duration(today.moving)) moving."
        let weekLine = "This week he has \(session.unit.text(meters: week.distance)), \(duration(week.resting)) resting, and \(duration(week.moving)) moving."
        if remaining == 0 {
            return "\(todayLine) The 30 minutes of easy walking are covered. \(weekLine)"
        }
        return "\(todayLine) He still needs \(duration(remaining)) of easy walking, in short outings. \(weekLine)"
    }

    private func recordedShare(_ seconds: Int) -> Double {
        let total = session.period.resting + session.period.moving
        guard total > 0 else { return 0 }
        return Double(seconds) / Double(total)
    }

    private var dailyLog: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Day")
                .military(22, bold: true)
            ForEach(session.dayParts) { summary in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.part.title)
                            .military(17, bold: true)
                        Spacer()
                        Text(session.unit.text(meters: summary.totals.distance))
                            .monospacedDigit()
                    }
                    Text(summary.part.hours)
                        .military(12)
                        .foregroundStyle(.secondary)
                    Text("\(duration(summary.totals.moving)) moving · \(duration(summary.totals.resting)) resting")
                        .military(15)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            DayMovementChart(parts: session.dayParts)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.rows.isEmpty, !session.period.hasActivity {
                Text("No saved movement for this day.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.rows) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(session.unit.text(meters: row.totals.distance))
                            .monospacedDigit()
                        Text(rowDetail(row.totals))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            connectionButton
            buzzButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var connectionButton: some View {
        Button(connectionTitle) {
            if session.connected || session.busy {
                session.disconnect()
            } else {
                session.connect()
            }
        }
        .vvControlGlass(prominent: false)
        .disabled(session.busy && !session.connected)
    }

    private var buzzButton: some View {
        Button {
            session.buzz()
        } label: {
            Label(session.buzzing ? "Buzzing" : "Buzz", systemImage: "wave.3.right")
        }
        .vvControlGlass(prominent: true)
        .disabled(!session.connected || session.buzzing)
    }

    private var connectionTitle: String {
        if session.busy { return "Connecting" }
        return session.connected ? "Disconnect" : "Connect"
    }

    private var calibrateButton: some View {
        Button(session.calibrating ? "Calibrating" : "Calibrate") {
            showCalibration = true
        }
        .buttonStyle(.bordered)
        .military(17, bold: true)
        .accessibilityHint("Set the stride from a walk whose distance you already know")
    }

    private var strideTuner: some View {
        DisclosureGroup("Stride") {
            VStack(alignment: .leading, spacing: 8) {
                labeledSlider
                Text("Peaks this connection: \(session.connectionPeaks)")
                    .military(13)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("Starting stride is 0.83 m, from large-dog walk research. Calibrate replaces it with a walk whose distance you already know. Days already saved keep the stride they were written with. The slider stays in meters.")
                    .military(13)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .military(17, bold: true)
    }

    private var labeledSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Meters per peak")
                    .military(17)
                Spacer()
                Text(metersText)
                    .military(17)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: metersBinding, in: StrideCalibration.minimumMetersPerPeak...StrideCalibration.maximumMetersPerPeak)
        }
    }

    private var rangeBinding: Binding<HistoryRange> {
        Binding(get: { session.range }, set: { session.setRange($0) })
    }

    private var unitBinding: Binding<DistanceUnit> {
        Binding(get: { session.unit }, set: { session.setUnit($0) })
    }

    private var metersBinding: Binding<Double> {
        Binding(get: { session.metersPerPeak }, set: { session.setMeters($0) })
    }

    private var motionColor: Color {
        switch session.motion {
        case .resting, nil: return .secondary
        case .moving: return .green
        }
    }

    private var periodTitle: String {
        let calendar = Calendar.current
        let bounds = session.range.bounds(containing: Date(), calendar: calendar)
        switch session.range {
        case .day:
            if calendar.isDateInToday(bounds.start) { return "Today" }
            return HistoryStore.label(bounds.start, step: .day, calendar: calendar)
        case .week:
            return "This week"
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
            return formatter.string(from: bounds.start)
        }
    }

    private var goalSeconds: Int {
        let moving = session.period.moving
        guard session.range != .day else { return moving }
        return moving / elapsedDays
    }

    private var elapsedDays: Int {
        let calendar = Calendar.current
        let bounds = session.range.bounds(containing: Date(), calendar: calendar)
        let end = min(Date(), bounds.end.addingTimeInterval(-1))
        let start = calendar.startOfDay(for: bounds.start)
        let stop = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: start, to: stop).day ?? 0
        return max(1, days + 1)
    }

    private var metersText: String {
        String(format: "%.2f m", session.metersPerPeak)
    }

    private func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private func rowDetail(_ totals: PeriodTotals) -> String {
        var parts: [String] = []
        if totals.moving > 0 { parts.append("\(duration(totals.moving)) moving") }
        if totals.resting > 0 { parts.append("\(duration(totals.resting)) resting") }
        return parts.joined(separator: " · ")
    }
}

private struct MetricRing: View {
    let title: String
    let value: String
    let caption: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .military(15, bold: true)
                    .monospacedDigit()
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(value), \(caption)")
            Text(title)
                .military(12, bold: true)
            Text(caption)
                .military(11)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CalibrationSheet: View {
    @ObservedObject var session: StrapSession
    @Environment(\.dismiss) private var dismiss
    @State private var distanceText = ""
    @State private var result = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Enter the distance you will walk with Max. The strap counts peaks on its own. When you finish, that distance divided by those peaks becomes the stride.")
                        .military(15)
                    Text(session.unit == .miles ? "Miles you will walk" : "Meters you will walk")
                        .military(13)
                        .foregroundStyle(.secondary)
                    TextField(session.unit == .miles ? "0.25" : "400", text: $distanceText)
                        .military(28, bold: true)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    if session.calibrating {
                        Text("Peaks this walk: \(session.calibrationPeaks)")
                            .military(20, bold: true)
                            .monospacedDigit()
                        Text("App measure: \(session.unit.text(meters: Double(session.calibrationPeaks) * session.metersPerPeak))")
                            .military(15)
                            .foregroundStyle(.secondary)
                        Button("Finish") { finish() }
                            .buttonStyle(.borderedProminent)
                            .military(17, bold: true)
                        Button("Cancel") { session.cancelCalibration() }
                            .military(17)
                    } else {
                        Button("Start walk") { session.startCalibration() }
                            .buttonStyle(.borderedProminent)
                            .military(17, bold: true)
                            .disabled(!session.connected)
                        if !session.connected {
                            Text("Connect the strap, then start the walk.")
                                .military(15)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !result.isEmpty {
                        Text(result)
                            .military(15)
                    } else if !session.calibrationNote.isEmpty, !session.calibrating {
                        Text(session.calibrationNote)
                            .military(15)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Calibrate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .environment(\.font, MilitaryFont.text(17))
        .onAppear {
            if distanceText.isEmpty {
                distanceText = session.unit == .miles ? "0.25" : "400"
            }
        }
    }

    private func finish() {
        guard let meters = session.unit.meters(from: distanceText) else {
            result = "Enter the distance you walked."
            return
        }
        result = session.finishCalibration(knownMeters: meters)
    }
}

private extension View {
    @ViewBuilder
    func vvControlGlass(prominent: Bool) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
