import SwiftUI
import VV00PCore

private enum OpeningGauge {
    static var last = Date.distantPast
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: StrapSession
    @State private var showSettings = false
    @State private var showChat = false
    @State private var shareFile: ShareFile?
    @State private var showTodayNote = false
    @State private var showDinner = false
    @State private var brief: DayBrief.Note?
    @State private var briefNote = ""
    @State private var briefLoading = false
    @State private var gaugeSweep: GaugeSweep?
    @State private var sweepToken = 0
    @State private var chartReveal = 0
    @State private var lastScenePhase: ScenePhase = .active

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DogPhotoPicker(
                        profile: session.profile,
                        sleep: sleepProgress,
                        movement: movementProgress,
                        strain: strainProgress,
                        sleepValue: duration(session.todayTotals.resting),
                        movementValue: session.unit.text(meters: session.todayTotals.distance),
                        movementCaption: "of \(session.unit.text(meters: DayBrief.minimumMiles * DistanceUnit.metersPerMile))",
                        strainValue: String(format: "%.1f", session.strain.strain),
                        velocity: velocityText,
                        gaugeSweep: gaugeSweep
                    ) {
                        periodPicker
                            .padding(.horizontal, 20)
                    }
                    VStack(alignment: .leading, spacing: 28) {
                        healthCard
                        if session.range == .day {
                            dailyLog
                            dinnerCard
                            historyList
                        } else {
                            AnalyticsView(range: session.range, days: session.chartDays, unit: session.unit, revealToken: chartReveal)
                            dinnerCard
                        }
                        statusBlock
                        settingsButton
                        connectionButton
                            .frame(maxWidth: .infinity, alignment: .leading)
                        exportButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .refreshable {
                await session.syncFromStrap()
                await refreshBrief(force: true)
                chartReveal += 1
                Task { @MainActor in
                    await playGaugeSweep()
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showSettings) {
                DogSettingsSheet(session: session)
            }
            .sheet(isPresented: $showChat) {
                ActivityChatSheet(session: session)
            }
            .sheet(item: $shareFile) { file in
                ActivityShare(url: file.url)
                    .ignoresSafeArea()
            }
            .toolbar {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarLeading) { restingMark }
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) { movingMark }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { restingMark }
                    ToolbarItem(placement: .topBarTrailing) { movingMark }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        Button {
                            session.shiftDay(by: -1)
                        } label: {
                            Text("<<")
                                .military(17, bold: true)
                        }
                        .accessibilityLabel("Earlier day")
                        Text(dayTitle)
                            .military(17, bold: true)
                        Button {
                            session.shiftDay(by: 1)
                        } label: {
                            Text(">>")
                                .military(17, bold: true)
                        }
                        .disabled(session.dayOffset >= 1)
                        .accessibilityLabel("Tomorrow")
                    }
                    .buttonStyle(.plain)
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
            if !ProcessInfo.processInfo.arguments.contains("--screenshot") {
                Task { await refreshBrief(force: false) }
                playOpeningGaugeIfNeeded()
            }
        }
        .onChange(of: session.dayOffset) { _ in
            showTodayNote = false
            showDinner = false
            brief = nil
            briefNote = ""
            guard !ProcessInfo.processInfo.arguments.contains("--screenshot") else { return }
            Task { await refreshBrief(force: false) }
        }
        .onChange(of: scenePhase) { phase in
            let previous = lastScenePhase
            lastScenePhase = phase
            if phase == .active {
                session.reloadHistory()
                session.reassertLink()
                if previous == .background {
                    playOpeningGaugeIfNeeded()
                }
            } else {
                session.flushHistory()
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.deviceName)
                .military(13, bold: true)
            Text(session.status)
                .military(12)
                .foregroundStyle(.secondary)
            if session.connected {
                Text(session.motionLabel)
                    .military(12, bold: true)
                    .foregroundStyle(motionColor)
            }
            if session.sampleCount > 0 {
                Text("\(session.sampleCount) samples")
                    .military(11)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !session.motionNote.isEmpty {
                Text(session.motionNote)
                    .military(12)
                    .foregroundStyle(.orange)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodPicker: some View {
        VStack(spacing: 8) {
            Picker("Period", selection: rangeBinding) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            Text(periodTitle)
                .military(13)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showTodayNote.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(healthTitle)
                        .military(20, bold: true)
                    Spacer(minLength: 8)
                    Image(systemName: showTodayNote ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(healthTitle)
            .accessibilityHint(showTodayNote ? "Hides the note" : "Shows the note")
            if showTodayNote {
                Text(brief?.summary ?? healthBody)
                    .military(15)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if briefLoading, brief == nil {
                    Text("Writing today's note.")
                        .military(13)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var dinnerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Button {
                    showDinner.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("Dinner")
                            .military(20, bold: true)
                        Image(systemName: showDinner ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showDinner ? "Hides the meal" : "Shows the meal")
                Spacer()
                Button(briefLoading ? "Writing" : "Generate") {
                    Task { await refreshBrief(force: true) }
                }
                .buttonStyle(.bordered)
                .disabled(briefLoading)
                .military(15, bold: true)
            }
            if showDinner, let brief {
                Text(brief.dinnerName)
                    .military(17, bold: true)
                ForEach(Array(brief.ingredients.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .military(15)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(brief.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .military(15)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("One meal from the pantry. It is not a complete diet.")
                    .military(12)
                    .foregroundStyle(.secondary)
            } else if showDinner, !briefNote.isEmpty {
                Text(briefNote)
                    .military(15)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var healthTitle: String {
        if session.dayOffset > 0 { return "Tomorrow" }
        if session.dayOffset < 0 { return dayTitle }
        let meters = session.todayTotals.distance
        return meters >= DayBrief.minimumMiles * DistanceUnit.metersPerMile ? "Day covered" : "Today"
    }

    private var healthBody: String {
        if session.dayOffset > 0 {
            return "Tomorrow's distance and strain, from today and the week."
        }
        return "Today's distance and strain, from yesterday and the week."
    }

    private func refreshBrief(force: Bool) async {
        let day = DayBriefCache.dayString(for: session.anchorDate)
        let kind: DayBrief.Kind = session.dayOffset > 0 ? .forecast : .record
        let cacheKind = kind.rawValue + "-goal"
        if !force, let cached = DayBriefCache.load(day: day, kind: cacheKind) {
            brief = cached
            briefNote = ""
            return
        }
        guard !briefLoading else { return }
        briefLoading = true
        if !force { briefNote = "" }
        defer { briefLoading = false }
        let source = session.noteSource()
        let speed = String(format: "%.2f m/s", source.strain.averageMetersPerSecond)
        do {
            let note = try await DayBriefClient.fetch(
                profile: session.profile,
                today: source.day,
                yesterday: source.yesterday,
                week: source.week,
                dayLabel: kind == .forecast ? "Today" : dayTitle,
                kind: kind,
                strain: source.strain.strain,
                yesterdayStrain: source.yesterdayStrain.strain,
                averageSpeed: speed
            )
            brief = note
            DayBriefCache.save(note, day: day, kind: cacheKind)
        } catch DayBriefError.missingKey {
            briefNote = "This note needs an OpenRouter key on this phone."
        } catch DayBriefError.requestFailed(let status) {
            briefNote = "This note did not come back (\(status))."
        } catch {
            briefNote = "This note did not come back."
        }
    }

    private func playOpeningGaugeIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(OpeningGauge.last) > 3 else { return }
        OpeningGauge.last = now
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await playGaugeSweep()
        }
    }

    private func playGaugeSweep() async {
        sweepToken += 1
        let token = sweepToken
        gaugeSweep = GaugeSweep(
            started: Date(),
            originSleep: sleepProgress,
            originMovement: movementProgress,
            originStrain: strainProgress,
            settling: false
        )
        try? await Task.sleep(nanoseconds: UInt64(GaugeSweep.fill * 1_000_000_000) + UInt64(GaugeSweep.stagger * 2 * 1_000_000_000))
        guard token == sweepToken else { return }
        guard !Task.isCancelled else {
            gaugeSweep = nil
            return
        }
        gaugeSweep = GaugeSweep(
            started: Date(),
            originSleep: sleepProgress,
            originMovement: movementProgress,
            originStrain: strainProgress,
            settling: true
        )
        try? await Task.sleep(nanoseconds: UInt64(GaugeSweep.settle * 1_000_000_000) + UInt64(GaugeSweep.stagger * 2 * 1_000_000_000))
        guard token == sweepToken else { return }
        gaugeSweep = nil
    }

    private var sleepProgress: Double {
        min(1, Double(session.todayTotals.resting) / Double(Bulldog.dailyRestingSeconds))
    }

    private var movementProgress: Double {
        let goal = DayBrief.minimumMiles * DistanceUnit.metersPerMile
        guard goal > 0 else { return 0 }
        return min(1, session.todayTotals.distance / goal)
    }

    private var strainProgress: Double {
        min(1, session.strain.strain / StrainModel.scale)
    }

    private var velocityText: String {
        let average = session.strain.averageMetersPerSecond
        let peak = session.strain.peakMetersPerSecond
        switch session.unit {
        case .meters:
            return String(format: "Velocity %.2f m/s average, %.2f m/s peak", average, peak)
        case .miles:
            return String(format: "Velocity %.1f mph average, %.1f mph peak", average * 2.236936, peak * 2.236936)
        }
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
            DayMovementChart(parts: session.dayParts, revealToken: chartReveal)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.rows.isEmpty, !session.period.hasActivity {
                Text("No saved movement for this day.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .military(13, bold: true)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(session.unit.text(meters: row.totals.distance))
                                .military(13)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        if !rowDetail(row.totals).isEmpty {
                            Text(rowDetail(row.totals))
                                .military(12)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var restingMark: some View {
        if session.motion != .moving {
            Button {
                showChat = true
            } label: {
                Text("🦴")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resting. Ask about Max.")
        }
    }

    @ViewBuilder
    private var movingMark: some View {
        if session.motion == .moving {
            SpinningTennisBall()
        }
    }

    private var controlBar: some View {
        HStack {
            Spacer()
            buzzButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var exportButton: some View {
        Button {
            guard let url = DiaryPDF.write(
                profile: session.profile,
                dayTitle: dayTitle,
                today: session.todayTotals,
                week: session.weekTotals,
                strain: session.strain.strain,
                unit: session.unit,
                rows: session.rows,
                photo: DogPhotoStore.load()
            ) else { return }
            shareFile = ShareFile(url: url)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .military(17, bold: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Share a PDF of this diary")
    }

    private var connectionButton: some View {
        Button(connectionTitle) {
            if session.keepingLink {
                session.disconnect()
            } else {
                session.connect()
            }
        }
        .vvControlGlass(prominent: false)
        .disabled(session.busy && !session.keepingLink)
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
        if session.busy && !session.keepingLink { return "Connecting" }
        return session.keepingLink ? "Disconnect" : "Connect"
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .military(17, bold: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Set stride, name, age, breed, and weight")
    }

    private var rangeBinding: Binding<HistoryRange> {
        Binding(get: { session.range }, set: { session.setRange($0) })
    }

    private var motionColor: Color {
        switch session.motion {
        case .resting, nil: return .secondary
        case .moving: return .green
        }
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if session.dayOffset == 0 { return "Today" }
        if session.dayOffset == 1 { return "Tomorrow" }
        if session.dayOffset == -1 { return "Yesterday" }
        return HistoryStore.label(session.anchorDate, step: .day, calendar: calendar)
    }

    private var periodTitle: String {
        let calendar = Calendar.current
        let bounds = session.range.bounds(containing: session.anchorDate, calendar: calendar)
        switch session.range {
        case .day:
            return dayTitle
        case .week:
            return "Week of \(HistoryStore.label(bounds.start, step: .day, calendar: calendar))"
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
            return formatter.string(from: bounds.start)
        }
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

private struct SpinningTennisBall: View {
    @State private var angle = 0.0

    var body: some View {
        Text("🎾")
            .font(.system(size: 22))
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityLabel("Moving")
    }
}

private struct DogSettingsSheet: View {
    @ObservedObject var session: StrapSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breed = ""
    @State private var age = 3
    @State private var weight = 55
    @State private var showCalibration = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Breed", text: $breed)
                    Stepper(value: $age, in: 0...30) {
                        Text("Age \(age)")
                    }
                    Stepper(value: $weight, in: 1...200) {
                        Text("Weight \(weight) lb")
                    }
                } header: {
                    Text("Dog")
                }
                Section {
                    HStack {
                        Text("Meters per peak")
                        Spacer()
                        Text(String(format: "%.2f m", session.metersPerPeak))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: metersBinding,
                        in: StrideCalibration.minimumMetersPerPeak...StrideCalibration.maximumMetersPerPeak
                    )
                    Text("Saved days keep the stride they were written with.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(session.calibrating ? "Calibrating" : "Calibrate") {
                        showCalibration = true
                    }
                } header: {
                    Text("Stride")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                Button("Done") {
                    session.setProfile(DogProfile(
                        name: name,
                        breed: breed,
                        ageYears: age,
                        weightPounds: weight
                    ))
                    dismiss()
                }
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationSheet(session: session)
            }
        }
        .onAppear {
            name = session.profile.name
            breed = session.profile.breed
            age = session.profile.ageYears
            weight = session.profile.weightPounds
        }
    }

    private var metersBinding: Binding<Double> {
        Binding(get: { session.metersPerPeak }, set: { session.setMeters($0) })
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

extension View {
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
