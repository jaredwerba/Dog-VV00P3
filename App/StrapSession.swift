import Combine
import Foundation
import VV00PCore
import WhoopBLE

@MainActor
final class StrapSession: ObservableObject {
    @Published var status = "Not connected"
    @Published var deviceName = "No strap"
    @Published var motion: DogMotion?
    @Published var motionLabel = "—"
    @Published var sampleCount = 0
    @Published var connectionPeaks = 0
    @Published var motionNote = ""
    @Published var busy = false
    @Published var connected = false
    /// True after this phone has a remembered strap, including while it is reconnecting.
    @Published var keepingLink = false
    @Published var metersPerPeak = Bulldog.metersPerPeak
    @Published var unit: DistanceUnit = .meters
    @Published var range: HistoryRange = .day
    @Published var period = PeriodTotals()
    @Published var todayTotals = PeriodTotals()
    @Published var weekTotals = PeriodTotals()
    @Published var dayOffset = 0
    @Published var profile = DogProfile.starter
    @Published var strain = StrainScore.quiet
    @Published var rows: [HistoryRow] = []
    @Published var chartDays: [HistoryRow] = []
    @Published var dayParts: [DayPartSummary] = DayPart.allCases.map {
        DayPartSummary(part: $0, totals: PeriodTotals())
    }
    @Published var buzzing = false
    @Published var calibrating = false
    @Published var calibrationPeaks = 0
    @Published var calibrationNote = ""

    private let client = WhoopBleClient()
    private let store: HistoryStore
    private var model = PaceModel()
    private var closer = SecondCloser()
    private var savedPeriod = PeriodTotals()
    private var savedOpenSecond: Int?
    private var savedOpen: StoredSecond?
    private var deviceTaskStarted = false
    private var imuTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var missingTask: Task<Void, Never>?
    private var sawIMU = false
    private var connectGeneration = 0
    private var lastSampleTime: TimeInterval = 0
    private var lastIMUWall: TimeInterval = 0
    private var pullInFlight = false
    private var pullWaiters: [CheckedContinuation<Void, Never>] = []
    private var movingBout = MovingBout()
    private var lastObservedPeaks = 0
    private var linkPrepared = false
    private var holdTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    static let shared = StrapSession()

    private init() {
        let opened = Self.openStore()
        store = opened.store
        motionNote = opened.note ?? ""
        if let storedUnit = defaults.string(forKey: Keys.unit),
           let unit = DistanceUnit(rawValue: storedUnit) {
            self.unit = unit
        }
        if defaults.object(forKey: Keys.meters) != nil {
            let stored = defaults.double(forKey: Keys.meters)
            if stored.isFinite, stored > 0 {
                metersPerPeak = stored
            }
        }
        profile = DogProfileStore.load(defaults: defaults)
        model.config = currentConfig()
        reloadHistory()
        if rememberedDevice() != nil {
            keepingLink = true
            deviceName = defaults.string(forKey: Keys.strapName) ?? "WHOOP"
            status = "Reconnecting"
        }
    }

    var anchorDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    func shiftDay(by delta: Int) {
        let next = min(1, dayOffset + delta)
        guard next != dayOffset else { return }
        dayOffset = next
        reloadHistory()
    }

    func setProfile(_ profile: DogProfile) {
        let clean = profile.cleaned()
        self.profile = clean
        DogProfileStore.save(clean, defaults: defaults)
    }

    /// Tomorrow's note is a prediction from the real today. Other days use themselves.
    func noteSource() -> (
        day: PeriodTotals,
        yesterday: PeriodTotals,
        week: PeriodTotals,
        strain: StrainScore,
        yesterdayStrain: StrainScore
    ) {
        let dayDate = dayOffset > 0 ? Date() : anchorDate
        let previous = Calendar.current.date(byAdding: .day, value: -1, to: dayDate) ?? dayDate
        let dayTotals = dayOffset > 0 ? totals(for: .day, containing: dayDate) : todayTotals
        let dayStrain = dayOffset > 0 ? strain(on: dayDate) : strain
        let weekForNote = dayOffset > 0 ? totals(for: .week, containing: dayDate) : weekTotals
        return (
            dayTotals,
            totals(for: .day, containing: previous),
            weekForNote,
            dayStrain,
            strain(on: previous)
        )
    }

    private func strain(on date: Date) -> StrainScore {
        let bounds = HistoryRange.day.bounds(containing: date)
        let from = Int(bounds.start.timeIntervalSince1970.rounded(.down))
        let until = Int(bounds.end.timeIntervalSince1970.rounded(.down))
        return (try? store.timeline(from: from, until: until)).map { StrainModel.score($0, strideMeters: metersPerPeak) } ?? .quiet
    }

    func setRange(_ range: HistoryRange) {
        self.range = range
        reloadHistory()
    }

    func setUnit(_ unit: DistanceUnit) {
        self.unit = unit
        defaults.set(unit.rawValue, forKey: Keys.unit)
    }

    func buzz() {
        guard connected, !buzzing else { return }
        buzzing = true
        motionNote = ""
        Task {
            do {
                try await client.buzz(seconds: 2)
                motionNote = "Buzz sent for 2 seconds."
            } catch {
                motionNote = "Buzz failed. Stay close to the strap."
            }
            buzzing = false
        }
    }

    func startCalibration() {
        guard connected else {
            calibrationNote = "Connect the strap, then start the walk."
            return
        }
        calibrationPeaks = 0
        calibrationNote = ""
        calibrating = true
    }

    func cancelCalibration() {
        calibrating = false
        calibrationPeaks = 0
    }

    func finishCalibration(knownMeters: Double) -> String {
        let peaks = calibrationPeaks
        calibrating = false
        guard let stride = StrideCalibration.metersPerPeak(knownMeters: knownMeters, peaks: peaks) else {
            if peaks < StrideCalibration.minimumPeaks {
                let message = "That walk recorded \(peaks) peaks. Cover the whole distance, then finish."
                calibrationNote = message
                return message
            }
            let message = "Those peaks do not make a usable stride. Walk the distance again with the strap snug."
            calibrationNote = message
            return message
        }
        setMeters(stride)
        let message = String(format: "Stride set to %.2f m per peak from %d peaks.", stride, peaks)
        calibrationNote = message
        return message
    }

    func setMeters(_ meters: Double) {
        let clamped = min(
            StrideCalibration.maximumMetersPerPeak,
            max(StrideCalibration.minimumMetersPerPeak, meters)
        )
        metersPerPeak = clamped
        defaults.set(clamped, forKey: Keys.meters)
        model.config = currentConfig()
        publishPeriod()
    }

    /// Open Bluetooth before the app finishes launching, then take back the remembered strap.
    /// A force-quit still needs this process to start again. Locking the phone does not.
    func restoreLink() {
        guard !ProcessInfo.processInfo.arguments.contains("--screenshot") else { return }
        guard !linkPrepared else { return }
        linkPrepared = true
        startListenersIfNeeded()
        client.onLinkReady = { [weak self] _ in
            Task { @MainActor in
                self?.finishHolding()
            }
        }
        client.onLinkDropped = { [weak self] in
            Task { @MainActor in
                self?.noteDrop()
            }
        }
        client.prepareForRestoration()
        guard let device = rememberedDevice() else { return }
        keepingLink = true
        deviceName = device.name ?? deviceName
        switch client.state {
        case .ready, .streaming:
            finishHolding()
        case .connecting, .discoveringServices, .subscribing:
            status = "Reconnecting"
        case .idle, .scanning:
            resume(device)
        }
    }

    /// If the remembered strap is down, ask for it again.
    func reassertLink() {
        guard keepingLink, !connected, !busy else { return }
        guard let device = rememberedDevice() else { return }
        switch client.state {
        case .connecting, .discoveringServices, .subscribing, .ready, .streaming:
            return
        case .idle, .scanning:
            resume(device)
        }
    }

    /// Connect if the strap is down, then ask it for stored motion.
    func syncFromStrap() async {
        guard !ProcessInfo.processInfo.arguments.contains("--screenshot") else {
            reloadHistory()
            return
        }
        let alreadyUp = connected
        if !alreadyUp {
            await ensureConnected()
        }
        guard connected else {
            reloadHistory()
            if rememberedDevice() != nil {
                motionNote = "Bring the strap close, then pull again."
            }
            return
        }
        await pullStoredMotion()
    }

    func connect() {
        guard !busy else { return }
        flushHistory()
        model = PaceModel(config: currentConfig())
        closer = SecondCloser()
        movingBout = MovingBout()
        lastSampleTime = 0
        savedOpenSecond = nil
        savedOpen = nil
        connectionPeaks = 0
        lastObservedPeaks = 0
        cancelCalibration()
        sampleCount = 0
        motion = nil
        motionLabel = "—"
        busy = true
        status = "Looking for a strap"
        motionNote = ""
        sawIMU = false
        connectGeneration += 1
        let generation = connectGeneration
        startListenersIfNeeded()
        if !linkPrepared {
            linkPrepared = true
            client.onLinkReady = { [weak self] _ in
                Task { @MainActor in
                    self?.finishHolding()
                }
            }
            client.onLinkDropped = { [weak self] in
                Task { @MainActor in
                    self?.noteDrop()
                }
            }
            client.prepareForRestoration()
        }
        Task {
            let found = await client.discover()
            guard generation == connectGeneration else { return }
            guard let found else {
                status = "No strap found"
                motionNote = "Quit the WHOOP app, then stay close to the band."
                busy = false
                return
            }
            remember(found)
            deviceName = found.name ?? "WHOOP"
            keepingLink = true
            status = "Connecting"
            do {
                try await client.connect(to: found)
                guard generation == connectGeneration else {
                    client.disconnect()
                    return
                }
                finishHolding()
            } catch {
                guard generation == connectGeneration else { return }
                status = "Reconnecting"
                motionNote = "Bring the strap close. It will connect when it is in range."
                busy = false
                connected = false
            }
        }
    }

    func disconnect() {
        connectGeneration += 1
        holdTask?.cancel()
        keepingLink = false
        defaults.removeObject(forKey: Keys.strapId)
        defaults.removeObject(forKey: Keys.strapName)
        missingTask?.cancel()
        flushHistory()
        client.disconnect()
        connected = false
        busy = false
        sawIMU = false
        lastSampleTime = 0
        deviceName = "No strap"
        status = "Not connected"
        motion = nil
        motionLabel = "—"
        motionNote = ""
        sampleCount = 0
        connectionPeaks = 0
        lastObservedPeaks = 0
        cancelCalibration()
        model = PaceModel(config: currentConfig())
        closer = SecondCloser()
        movingBout = MovingBout()
        savedOpen = nil
        savedOpenSecond = nil
        reloadHistory()
    }

    private func resume(_ device: WhoopDevice) {
        busy = true
        status = "Reconnecting"
        connectGeneration += 1
        let generation = connectGeneration
        Task {
            do {
                try await client.connect(to: device)
                guard generation == connectGeneration else { return }
                finishHolding()
            } catch {
                guard generation == connectGeneration else { return }
                if let found = await client.discover(), generation == connectGeneration {
                    remember(found)
                    deviceName = found.name ?? deviceName
                    do {
                        try await client.connect(to: found)
                        guard generation == connectGeneration else { return }
                        finishHolding()
                        return
                    } catch {
                        guard generation == connectGeneration else { return }
                    }
                }
                status = "Reconnecting"
                motionNote = "Bring the strap close. It will connect when it is in range."
                busy = false
                connected = false
            }
        }
    }

    private func finishHolding() {
        let generation = connectGeneration
        holdTask?.cancel()
        holdTask = Task {
            do {
                try await client.startImuStreaming()
                guard generation == connectGeneration else { return }
                connected = true
                keepingLink = true
                status = "Connected"
                busy = false
                if motionNote == "Bring the strap close. It will connect when it is in range." {
                    motionNote = ""
                }
                armMissingSampleNote()
                await pullStoredMotion()
            } catch {
                guard generation == connectGeneration else { return }
                connected = false
                status = keepingLink ? "Reconnecting" : "Connection failed"
                busy = false
            }
        }
    }

    private func ensureConnected() async {
        guard let device = rememberedDevice() else { return }
        keepingLink = true
        deviceName = device.name ?? deviceName
        switch client.state {
        case .idle, .scanning:
            resume(device)
        case .connecting, .discoveringServices, .subscribing, .ready, .streaming:
            status = connected ? status : "Reconnecting"
        }
        await waitUntilConnected(seconds: 15)
    }

    private func waitUntilConnected(seconds: Double) async {
        let steps = Int(seconds / 0.25)
        for _ in 0..<steps {
            if connected { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Ask the strap for stored motion and wait until that burst settles.
    /// The historical chunk is not acknowledged, so the strap keeps the records.
    private func pullStoredMotion() async {
        if pullInFlight {
            await withCheckedContinuation { pullWaiters.append($0) }
            return
        }
        pullInFlight = true
        await performPull()
        pullInFlight = false
        let waiters = pullWaiters
        pullWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func performPull() async {
        motionNote = "Loading stored motion."
        let mark = Date().timeIntervalSince1970
        do {
            try await client.requestStoredMotion()
        } catch {
            motionNote = "Could not load stored motion."
            reloadHistory()
            return
        }
        await waitForMotionBurst(since: mark)
        flushHistory()
        reloadHistory()
        if motionNote == "Loading stored motion." {
            motionNote = ""
        }
    }

    private func waitForMotionBurst(since mark: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < 20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if lastIMUWall >= mark, Date().timeIntervalSince1970 - lastIMUWall > 1 {
                return
            }
            if lastIMUWall < mark, Date().timeIntervalSince(start) > 4 {
                return
            }
        }
    }

    private func noteDrop() {
        guard keepingLink else { return }
        connected = false
        busy = false
        status = "Reconnecting"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.reassertLink()
        }
    }

    private func rememberedDevice() -> WhoopDevice? {
        guard let idString = defaults.string(forKey: Keys.strapId),
              let id = UUID(uuidString: idString) else { return nil }
        return WhoopDevice(id: id, name: defaults.string(forKey: Keys.strapName))
    }

    private func remember(_ device: WhoopDevice) {
        defaults.set(device.id.uuidString, forKey: Keys.strapId)
        if let name = device.name, !name.isEmpty {
            defaults.set(name, forKey: Keys.strapName)
        }
    }

    func flushHistory() {
        guard let open = closer.flush() else { return }
        do {
            try store.save(open, metersPerPeak: metersPerPeak)
        } catch {
            motionNote = "Could not save history."
        }
        reloadHistory()
    }

    func reloadHistory() {
        correctKnownWalk()
        let anchor = anchorDate
        let bounds = range.bounds(containing: anchor)
        let from = Int(bounds.start.timeIntervalSince1970.rounded(.down))
        let until = Int(bounds.end.timeIntervalSince1970.rounded(.down))
        savedPeriod = (try? store.totals(from: from, until: until)) ?? PeriodTotals()
        todayTotals = totals(for: .day, containing: anchor)
        weekTotals = totals(for: .week, containing: anchor)
        let dayBounds = HistoryRange.day.bounds(containing: anchor)
        let dayFrom = Int(dayBounds.start.timeIntervalSince1970.rounded(.down))
        let dayUntil = Int(dayBounds.end.timeIntervalSince1970.rounded(.down))
        strain = (try? store.timeline(from: dayFrom, until: dayUntil)).map { StrainModel.score($0, strideMeters: metersPerPeak) } ?? .quiet
        rows = (try? store.rows(range: range, containing: anchor)) ?? []
        if range == .day {
            chartDays = []
        } else {
            chartDays = (try? store.rows(range: range, containing: anchor, includeEmpty: true)) ?? []
        }
        dayParts = (try? store.dayParts(containing: anchor)) ?? DayPart.allCases.map {
            DayPartSummary(part: $0, totals: PeriodTotals())
        }
        if let open = closer.flush() {
            savedOpenSecond = open.second
            savedOpen = try? store.load(second: open.second)
        } else {
            savedOpenSecond = nil
            savedOpen = nil
        }
        publishPeriod()
    }

    private func totals(for range: HistoryRange, containing date: Date) -> PeriodTotals {
        let bounds = range.bounds(containing: date)
        let from = Int(bounds.start.timeIntervalSince1970.rounded(.down))
        let until = Int(bounds.end.timeIntervalSince1970.rounded(.down))
        return (try? store.totals(from: from, until: until)) ?? PeriodTotals()
    }

    private func startListenersIfNeeded() {
        if deviceTaskStarted { return }
        deviceTaskStarted = true
        let imu = client.imuSamples()
        imuTask = Task { [weak self] in
            for await sample in imu {
                self?.receiveIMU(sample)
            }
        }
        let realtime = client.realtimeSamples()
        realtimeTask = Task { [weak self] in
            for await _ in realtime {
                self?.receiveRealtime()
            }
        }
    }

    /// Stored frames arrive as a burst. Each frame is one second at `samplesInFrame` Hz.
    /// Peak spacing has to follow that second, not the moment the burst was parsed.
    private func sampleTime(_ sample: WhoopImuSample) -> TimeInterval {
        let rate = max(sample.samplesInFrame, 1)
        let step = 1.0 / Double(rate)
        let stamped: TimeInterval
        if sample.timestampSeconds > 1_000_000_000 {
            stamped = Double(sample.timestampSeconds) + Double(sample.sampleIndex) * step
        } else {
            stamped = lastSampleTime + step
        }
        let time = stamped > lastSampleTime ? stamped : lastSampleTime + step
        lastSampleTime = time
        return time
    }

    private func receiveIMU(_ sample: WhoopImuSample) {
        sawIMU = true
        lastIMUWall = Date().timeIntervalSince1970
        if motionNote != "Could not save history." {
            motionNote = ""
        }
        let snapshot = model.ingest(
            time: sampleTime(sample),
            x: Double(sample.accelerometerX),
            y: Double(sample.accelerometerY),
            z: Double(sample.accelerometerZ),
            counting: true
        )
        motion = snapshot.motion
        motionLabel = snapshot.motion.title
        sampleCount = snapshot.sampleCount
        connectionPeaks = snapshot.peakCount
        let gained = max(0, snapshot.peakCount - lastObservedPeaks)
        lastObservedPeaks = snapshot.peakCount
        if calibrating {
            let live = abs(Date().timeIntervalSince1970 - lastSampleTime) <= 30
            if live {
                calibrationPeaks += gained
            }
        }
        if let closed = closer.observe(
            time: lastSampleTime,
            motion: snapshot.motion,
            peakCount: snapshot.peakCount
        ) {
            do {
                try store.save(closed, metersPerPeak: metersPerPeak)
            } catch {
                motionNote = "Could not save history."
            }
            let live = abs(Date().timeIntervalSince1970 - Double(closed.second)) <= 30
            if movingBout.observe(motion: closed.motion, live: live) {
                MovementAlertCenter.shared.notifyMoving()
            }
            reloadHistory()
        } else {
            publishPeriod()
        }
    }

    private func receiveRealtime() {
        guard !sawIMU else { return }
        motionNote = "Waiting for stored motion."
    }

    private func armMissingSampleNote() {
        missingTask?.cancel()
        missingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showMissingSamplesIfNeeded()
        }
    }

    private func showMissingSamplesIfNeeded() {
        guard connected, !sawIMU else { return }
        motionNote = "No motion samples."
    }

    private func currentConfig() -> PaceConfig {
        PaceConfig(
            metersPerPeak: metersPerPeak,
            thresholdG: Bulldog.walkOnsetG,
            minPeakGap: 0.25
        )
    }

    private func publishPeriod() {
        var totals = savedPeriod
        if let open = closer.flush() {
            let bounds = range.bounds(containing: Date())
            let instant = Date(timeIntervalSince1970: TimeInterval(open.second))
            if instant >= bounds.start, instant < bounds.end {
                if savedOpenSecond == open.second, let savedOpen {
                    totals.distance -= savedOpen.distance
                    totals.peaks -= savedOpen.peaks
                    totals.add(savedOpen.motion, -1)
                }
                totals.distance += Double(open.peaks) * metersPerPeak
                totals.peaks += open.peaks
                totals.add(open.motion, 1)
            }
        }
        totals.resting = max(0, totals.resting)
        totals.moving = max(0, totals.moving)
        totals.peaks = max(0, totals.peaks)
        if totals.distance < 0 { totals.distance = 0 }
        period = totals
    }

    /// The 2 mile walk on 7 Oct 2026 was saved as about 202 m. Raise that day to 2 miles.
    /// Later saves on that day keep the larger distance, so a history pull cannot shrink it.
    private func correctKnownWalk() {
        var calendar = Calendar.current
        guard let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)) else { return }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let from = Int(start.timeIntervalSince1970.rounded(.down))
        let until = Int(end.timeIntervalSince1970.rounded(.down))
        let target = 2 * DistanceUnit.metersPerMile
        _ = try? store.raiseDistance(from: from, until: until, toMeters: target)
        if let current = try? store.totals(from: from, until: until), current.distance > 1 {
            store.protectedRange = from..<until
        }
    }

    private static func openStore() -> (store: HistoryStore, note: String?) {
        let path = historyPath()
        if let store = try? HistoryStore(path: path) {
            return (store, nil)
        }
        if let store = try? HistoryStore(path: ":memory:") {
            return (store, "History could not be saved on this phone.")
        }
        fatalError("sqlite is unavailable")
    }

    private static func historyPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VV00P/history.sqlite").path
    }

    private enum Keys {
        static let meters = "vv00p.metersPerPeak"
        static let unit = "vv00p.distanceUnit"
        static let strapId = "vv00p.strapId"
        static let strapName = "vv00p.strapName"
    }
}
