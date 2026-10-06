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
    @Published var metersPerPeak = Bulldog.metersPerPeak
    @Published var unit: DistanceUnit = .meters
    @Published var range: HistoryRange = .day
    @Published var period = PeriodTotals()
    @Published var todayTotals = PeriodTotals()
    @Published var weekTotals = PeriodTotals()
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
    private var movingBout = MovingBout()
    private var lastObservedPeaks = 0
    private let defaults = UserDefaults.standard

    init() {
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
        model.config = currentConfig()
        reloadHistory()
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
        Task {
            let found = await client.discover()
            guard generation == connectGeneration else { return }
            guard let found else {
                status = "No strap found"
                motionNote = "Quit the WHOOP app, then stay close to the band."
                busy = false
                return
            }
            deviceName = found.name ?? "WHOOP"
            status = "Connecting"
            do {
                try await client.connect(to: found)
                guard generation == connectGeneration else {
                    client.disconnect()
                    return
                }
                try await client.startImuStreaming()
                guard generation == connectGeneration else {
                    client.disconnect()
                    return
                }
                // Do not acknowledge the historical chunk. An ack can make the strap drop it.
                try await client.requestStoredMotion()
                guard generation == connectGeneration else {
                    client.disconnect()
                    return
                }
                connected = true
                status = "Connected"
                busy = false
                armMissingSampleNote()
            } catch {
                status = "Connection failed"
                motionNote = error.localizedDescription
                busy = false
                connected = false
            }
        }
    }

    func disconnect() {
        connectGeneration += 1
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
        let bounds = range.bounds(containing: Date())
        let from = Int(bounds.start.timeIntervalSince1970.rounded(.down))
        let until = Int(bounds.end.timeIntervalSince1970.rounded(.down))
        savedPeriod = (try? store.totals(from: from, until: until)) ?? PeriodTotals()
        todayTotals = totals(for: .day)
        weekTotals = totals(for: .week)
        rows = (try? store.rows(range: range, containing: Date())) ?? []
        if range == .day {
            chartDays = []
        } else {
            chartDays = (try? store.rows(range: range, containing: Date(), includeEmpty: true)) ?? []
        }
        dayParts = (try? store.dayParts(containing: Date())) ?? DayPart.allCases.map {
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

    private func totals(for range: HistoryRange) -> PeriodTotals {
        let bounds = range.bounds(containing: Date())
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
    }
}
