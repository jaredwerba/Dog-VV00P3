import Foundation
import SQLite3

public enum VV00PChecks {
    public static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        expect(DistanceUnit.meters.text(meters: 0) == "0.0 m", "zero meters formatted as \(DistanceUnit.meters.text(meters: 0))")
        expect(DistanceUnit.miles.text(meters: 1_609.344) == "1.00 mi", "one mile formatted as \(DistanceUnit.miles.text(meters: 1_609.344))")
        expect(DistanceUnit.miles.meters(from: "0.25") == 402.336, "quarter mile was \(String(describing: DistanceUnit.miles.meters(from: "0.25")))")
        let quarter = StrideCalibration.metersPerPeak(knownMeters: 402.336, peaks: 400)
        expect(quarter != nil && abs((quarter ?? 0) - 1.00584) < 0.001, "calibrated stride was \(String(describing: quarter))")
        expect(StrideCalibration.metersPerPeak(knownMeters: 402.336, peaks: 3) == nil, "a tiny walk was accepted")
        expect(StrideCalibration.metersPerPeak(knownMeters: 0, peaks: 100) == nil, "a zero distance was accepted")
        expect(Bulldog.dogName == "Max Werba", "dog name was \(Bulldog.dogName)")
        expect(Bulldog.sex == "Male", "sex was \(Bulldog.sex)")
        expect(Bulldog.ageYears == 3, "age was \(Bulldog.ageYears)")
        expect(Bulldog.dailyMovingMinutes == 30, "daily moving goal was \(Bulldog.dailyMovingMinutes) minutes")
        expect(DayPart.part(forHour: 9) == .morning, "9 AM was not morning")
        expect(DayPart.part(forHour: 14) == .afternoon, "2 PM was not afternoon")
        expect(DayPart.part(forHour: 20) == .night, "8 PM was not night")
        expect(DayPart.part(forHour: 3) == .night, "3 AM was not night")

        var bout = MovingBout()
        for _ in 0..<9 {
            expect(bout.observe(motion: .moving, live: true) == false, "alert fired before 10 seconds")
        }
        expect(bout.observe(motion: .moving, live: true), "the 10th moving second did not alert")
        expect(bout.observe(motion: .moving, live: true) == false, "the same bout alerted twice")
        expect(bout.observe(motion: .resting, live: true) == false, "resting alerted")
        for _ in 0..<9 {
            _ = bout.observe(motion: .moving, live: true)
        }
        expect(bout.observe(motion: .moving, live: true), "a new bout did not alert")
        expect(bout.observe(motion: .moving, live: false) == false, "stored motion alerted")
        expect(bout.streak == 0, "stored motion left the streak at \(bout.streak)")
        expect(Bulldog.dailyMovingSeconds == 1_800, "daily moving goal was \(Bulldog.dailyMovingSeconds) seconds")
        expect(Bulldog.dailyRestingSeconds == 12 * 60 * 60, "sleep goal was \(Bulldog.dailyRestingSeconds) seconds")
        expect(DayBrief.minimumMiles == 3, "daily miles were \(DayBrief.minimumMiles)")
        expect(DayBrief.pantry.contains("yellowfin tuna"), "pantry dropped yellowfin tuna")
        let sampleToday = PeriodTotals(resting: 53 * 60, moving: 24, distance: 69.7, peaks: 80)
        let sampleWeek = PeriodTotals(resting: 53 * 60, moving: 24, distance: 69.7, peaks: 80)
        let prompt = DayBrief.userPrompt(
            profile: .starter,
            today: sampleToday,
            week: sampleWeek,
            dayLabel: "Today",
            kind: .record,
            strain: 4.2,
            averageSpeed: "0.83 m/s"
        )
        expect(prompt.contains("3.00 mi"), "prompt missed the 3 mile minimum: \(prompt)")
        expect(prompt.contains("English Bulldog"), "prompt missed the breed")
        expect(prompt.contains("55 lb"), "prompt missed the weight")
        expect(prompt.contains("yellowfin tuna"), "prompt missed the pantry")
        expect(prompt.contains("Strain: 4.2"), "prompt missed the strain number: \(prompt)")
        expect(!prompt.contains("recovery"), "prompt invented a recovery score")
        expect(DayBrief.systemPrompt(for: .forecast).contains("tomorrow"), "forecast prompt missed tomorrow")
        let easy = StrainModel.score(Array(repeating: StoredSecond(motion: .moving, peaks: 1, distance: 0.83), count: 1_800))
        expect(easy.strain > 9.5 && easy.strain < 10.5, "easy half hour strain was \(easy.strain)")
        expect(abs(easy.averageMetersPerSecond - 0.83) < 0.001, "easy speed was \(easy.averageMetersPerSecond)")
        let slowMile = StrainModel.score(Array(repeating: StoredSecond(motion: .moving, peaks: 1, distance: 0.83), count: 300))
        let fastMile = StrainModel.score(Array(repeating: StoredSecond(motion: .moving, peaks: 3, distance: 2.49), count: 100))
        expect(abs(slowMile.averageMetersPerSecond * 300 - 249) < 0.01, "slow mile distance drifted")
        expect(abs(fastMile.averageMetersPerSecond * 100 - 249) < 0.01, "fast mile distance drifted")
        expect(fastMile.strain > slowMile.strain, "a fast mile scored \(fastMile.strain) against a slow mile \(slowMile.strain)")
        let steady = StrainModel.score(Array(repeating: StoredSecond(motion: .moving, peaks: 2, distance: 1.6), count: 10))
        var chase: [StoredSecond] = []
        for _ in 0..<2 {
            chase.append(contentsOf: Array(repeating: StoredSecond(motion: .moving, peaks: 2, distance: 1.6), count: 5))
            chase.append(StoredSecond(motion: .resting, peaks: 0, distance: 0))
        }
        let stops = StrainModel.score(chase)
        expect(stops.starts == 2, "chase starts were \(stops.starts)")
        expect(stops.strain > steady.strain, "stop and go scored \(stops.strain) against steady \(steady.strain)")
        expect(StrainModel.score([StoredSecond(motion: .resting, peaks: 0, distance: 0)]).strain == 0, "rest scored strain")
        let parsed = DayBrief.parse("""
        Sure.
        {\"summary\":\"He has 0.04 miles today.\",\"dinnerName\":\"Beef and pumpkin\",\"ingredients\":[\"4 oz ground beef\",\"2 oz pumpkin\"],\"steps\":[\"Cook the beef.\",\"Stir in the pumpkin.\"]}
        """)
        expect(parsed?.dinnerName == "Beef and pumpkin", "dinner name was \(String(describing: parsed?.dinnerName))")
        expect(parsed?.ingredients.count == 2, "ingredients were \(String(describing: parsed?.ingredients))")
        expect(DayBrief.parse("not json") == nil, "garbage parsed as a note")

        let still = hold(PaceModel(), dynamicG: 0, from: 0, until: 1)
        expect(still.motion == .resting, "still was \(still.motion)")
        expect(still.distanceMeters == 0, "still produced distance")
        expect(hold(PaceModel(), dynamicG: 0.08, from: 0, until: 1).motion == .resting, "a sit was not resting")
        expect(hold(PaceModel(), dynamicG: 0.13, from: 0, until: 1).motion == .resting, "a stand was not resting")
        expect(hold(PaceModel(), dynamicG: 0.26, from: 0, until: 1).motion == .moving, "walk was not moving")
        expect(hold(PaceModel(), dynamicG: 0.80, from: 0, until: 1).motion == .moving, "a hard trot was not moving")
        expect(DogMotion.stored("lying") == .resting, "lying did not fold into resting")
        expect(DogMotion.stored("sitting") == .resting, "sitting did not fold into resting")

        var standing = PaceModel()
        _ = hold(&standing, dynamicG: 0.13, from: 0, until: 1)
        let fidget = spike(into: &standing, at: 1.2, baseline: 0.13, crest: 0.50)
        expect(fidget.motion == .resting, "a rest fidget became \(fidget.motion)")
        expect(fidget.peakCount == 0, "a sit fidget counted a peak")

        var walking = PaceModel()
        _ = hold(&walking, dynamicG: 0.26, from: 0, until: 1)
        var snapshot = walking.snapshotProbe
        for peakTime in [1.4, 1.9, 2.4, 2.9] {
            snapshot = spike(into: &walking, at: peakTime, baseline: 0.26, crest: 0.50)
        }
        expect(snapshot.peakCount == 4, "peaks were \(snapshot.peakCount)")
        expect(abs(snapshot.distanceMeters - 3.32) < 0.001, "distance was \(snapshot.distanceMeters)")

        var paused = PaceModel()
        _ = hold(&paused, dynamicG: 0.26, from: 0, until: 1)
        let ignored = spike(into: &paused, at: 1.4, baseline: 0.26, crest: 0.50, counting: false)
        expect(ignored.peakCount == 0, "peaks counted while stopped")

        var closer = SecondCloser()
        expect(closer.observe(time: 1_700_000_000.2, motion: .moving, peakCount: 1) == nil, "the open second closed early")
        let closed = closer.observe(time: 1_700_000_001.1, motion: .resting, peakCount: 3)
        expect(closed == ClosedSecond(second: 1_700_000_000, motion: .moving, peaks: 1), "closed second was \(String(describing: closed))")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vv00p-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try HistoryStore(path: url.path)
            let second = ClosedSecond(second: 1_700_000_000, motion: .moving, peaks: 2)
            try store.save(second, metersPerPeak: 0.83)
            try store.save(ClosedSecond(second: 1_700_000_000, motion: .moving, peaks: 4), metersPerPeak: 0.83)
            try store.save(ClosedSecond(second: 1_700_000_100, motion: .resting, peaks: 0), metersPerPeak: 0.83)
            let totals = try store.totals(from: 1_700_000_000, until: 1_700_000_200)
            expect(totals.moving == 1, "replayed second was counted \(totals.moving) times")
            expect(totals.resting == 1, "resting second was missing")
            expect(abs(totals.distance - 3.32) < 0.001, "replaced distance was \(totals.distance)")
            expect(totals.peaks == 4, "replaced peaks were \(totals.peaks)")
            let week = try store.rows(
                range: .week,
                containing: Date(timeIntervalSince1970: 1_700_000_000),
                includeEmpty: true
            )
            expect(week.count == 7, "week chart had \(week.count) days")
            expect(week.contains { abs($0.totals.distance - 3.32) < 0.001 }, "week chart dropped the saved day")
            let line = try store.timeline(from: 1_700_000_000, until: 1_700_000_200)
            expect(line.count == 2, "timeline had \(line.count) seconds")
            expect(line.first?.peaks == 4, "timeline dropped the replaced peaks")
            expect(line.last?.motion == .resting, "timeline order was \(String(describing: line.last?.motion))")

            let legacyURL = FileManager.default.temporaryDirectory.appendingPathComponent("vv00p-legacy-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: legacyURL) }
            var raw: OpaquePointer?
            if sqlite3_open(legacyURL.path, &raw) != SQLITE_OK {
                failures.append("legacy diary did not open")
            } else {
                let seed = """
                CREATE TABLE seconds (
                    second INTEGER PRIMARY KEY,
                    motion TEXT NOT NULL,
                    peaks INTEGER NOT NULL,
                    distance REAL NOT NULL
                );
                INSERT INTO seconds VALUES (1700000200, 'lying', 0, 0);
                INSERT INTO seconds VALUES (1700000201, 'sitting', 0, 0);
                """
                if sqlite3_exec(raw, seed, nil, nil, nil) != SQLITE_OK {
                    failures.append("legacy lying and sitting rows were not written")
                }
                sqlite3_close(raw)
                let migrated = try HistoryStore(path: legacyURL.path)
                let folded = try migrated.totals(from: 1_700_000_200, until: 1_700_000_300)
                expect(folded.resting == 2, "lying and sitting folded to \(folded.resting) resting seconds")
                expect(folded.moving == 0, "legacy rest counted as moving")
                let reloaded = try migrated.load(second: 1_700_000_200)
                expect(reloaded?.motion == .resting, "stored lying reloaded as \(String(describing: reloaded?.motion))")

                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
                let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
                let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 20))!
                let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 3))!
                try store.save(ClosedSecond(second: Int(morning.timeIntervalSince1970), motion: .moving, peaks: 1), metersPerPeak: 1)
                try store.save(ClosedSecond(second: Int(night.timeIntervalSince1970), motion: .resting, peaks: 0), metersPerPeak: 1)
                try store.save(ClosedSecond(second: Int(early.timeIntervalSince1970), motion: .resting, peaks: 0), metersPerPeak: 1)
                let parts = try store.dayParts(containing: morning, calendar: calendar)
                expect(parts.count == 3, "day log had \(parts.count) parts")
                expect(parts.first { $0.part == .morning }?.totals.moving == 1, "morning missed the moving second")
                expect(parts.first { $0.part == .afternoon }?.totals.hasActivity == false, "afternoon invented activity")
                expect(parts.first { $0.part == .night }?.totals.resting == 2, "night missed an early or evening second")
            }
        } catch {
            failures.append("history store failed: \(error)")
        }
        return failures
    }

    private static func hold(
        _ model: PaceModel,
        dynamicG: Double,
        from start: TimeInterval,
        until end: TimeInterval
    ) -> PaceSnapshot {
        var model = model
        return hold(&model, dynamicG: dynamicG, from: start, until: end)
    }

    private static func hold(
        _ model: inout PaceModel,
        dynamicG: Double,
        from start: TimeInterval,
        until end: TimeInterval,
        counting: Bool = true
    ) -> PaceSnapshot {
        var snapshot = PaceSnapshot(peakCount: 0, distanceMeters: 0, motion: .resting, sampleCount: 0)
        var time = start
        while time <= end + 0.000_001 {
            snapshot = model.ingest(time: time, x: 0, y: 0, z: 1 + dynamicG, counting: counting)
            time += 0.02
        }
        return snapshot
    }

    private static func spike(
        into model: inout PaceModel,
        at time: TimeInterval,
        baseline: Double,
        crest: Double,
        counting: Bool = true
    ) -> PaceSnapshot {
        _ = model.ingest(time: time - 0.02, x: 0, y: 0, z: 1 + baseline, counting: counting)
        _ = model.ingest(time: time, x: 0, y: 0, z: 1 + crest, counting: counting)
        return model.ingest(time: time + 0.02, x: 0, y: 0, z: 1 + baseline, counting: counting)
    }
}

private extension PaceModel {
    var snapshotProbe: PaceSnapshot {
        PaceSnapshot(peakCount: peakCount, distanceMeters: distanceMeters, motion: motion, sampleCount: sampleCount)
    }
}
