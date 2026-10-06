import Foundation
import SQLite3

public struct PeriodTotals: Equatable, Sendable {
    public var resting: Int
    public var moving: Int
    public var distance: Double
    public var peaks: Int

    public init(resting: Int = 0, moving: Int = 0, distance: Double = 0, peaks: Int = 0) {
        self.resting = resting
        self.moving = moving
        self.distance = distance
        self.peaks = peaks
    }

    public var hasActivity: Bool {
        resting + moving > 0
    }

    public mutating func add(_ motion: DogMotion, _ count: Int) {
        switch motion {
        case .resting: resting += count
        case .moving: moving += count
        }
    }

    public mutating func merge(_ other: PeriodTotals) {
        resting += other.resting
        moving += other.moving
        distance += other.distance
        peaks += other.peaks
    }
}

/// Morning is 5:00 AM–12:00 PM. Afternoon is 12:00 PM–5:00 PM.
/// Night is 5:00 PM–midnight and midnight–5:00 AM of the same calendar day.
public enum DayPart: String, CaseIterable, Identifiable, Sendable {
    case morning
    case afternoon
    case night

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .night: return "Night"
        }
    }

    public var hours: String {
        switch self {
        case .morning: return "5 AM – 12 PM"
        case .afternoon: return "12 PM – 5 PM"
        case .night: return "5 PM – midnight, and midnight – 5 AM"
        }
    }

    public var order: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .night: return 2
        }
    }

    public static func part(forHour hour: Int) -> DayPart {
        if hour >= 5 && hour < 12 { return .morning }
        if hour >= 12 && hour < 17 { return .afternoon }
        return .night
    }
}

public struct DayPartSummary: Equatable, Sendable, Identifiable {
    public var part: DayPart
    public var totals: PeriodTotals

    public var id: String { part.rawValue }

    public init(part: DayPart, totals: PeriodTotals) {
        self.part = part
        self.totals = totals
    }
}

public struct StoredSecond: Equatable, Sendable {
    public var motion: DogMotion
    public var peaks: Int
    public var distance: Double

    public init(motion: DogMotion, peaks: Int, distance: Double) {
        self.motion = motion
        self.peaks = peaks
        self.distance = distance
    }
}

public struct HistoryRow: Equatable, Sendable, Identifiable {
    public var start: Date
    public var label: String
    public var totals: PeriodTotals

    public var id: TimeInterval { start.timeIntervalSinceReferenceDate }

    public init(start: Date, label: String, totals: PeriodTotals) {
        self.start = start
        self.label = label
        self.totals = totals
    }
}

public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    public func bounds(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component
        switch self {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        return calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: date, duration: 1)
    }
}

public final class HistoryStore {
    private var db: OpaquePointer?

    public init(path: String) throws {
        if path != ":memory:" {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let reason = message(db)
            sqlite3_close(db)
            db = nil
            throw HistoryError.open(reason)
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS seconds (
                second INTEGER PRIMARY KEY,
                motion TEXT NOT NULL,
                peaks INTEGER NOT NULL,
                distance REAL NOT NULL
            )
            """
        )
        try execute(
            """
            UPDATE seconds SET motion = 'resting'
            WHERE motion IN ('lying', 'sitting')
            """
        )
        if path != ":memory:" {
            try execute("PRAGMA journal_mode=WAL")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func save(_ second: ClosedSecond, metersPerPeak: Double) throws {
        let meters = metersPerPeak.isFinite ? metersPerPeak : 0
        let distance = second.distance(metersPerPeak: meters)
        let safeDistance = distance.isFinite ? distance : 0
        try execute(
            """
            INSERT INTO seconds(second, motion, peaks, distance)
            VALUES (\(second.second), '\(second.motion.rawValue)', \(second.peaks), \(safeDistance))
            ON CONFLICT(second) DO UPDATE SET
                motion = excluded.motion,
                peaks = excluded.peaks,
                distance = excluded.distance
            """
        )
    }

    public func load(second: Int) throws -> StoredSecond? {
        let sql = "SELECT motion, peaks, distance FROM seconds WHERE second = \(second)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryError.query(message(db))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let text = sqlite3_column_text(statement, 0) else { return nil }
        guard let motion = DogMotion.stored(String(cString: text)) else { return nil }
        return StoredSecond(
            motion: motion,
            peaks: Int(sqlite3_column_int(statement, 1)),
            distance: sqlite3_column_double(statement, 2)
        )
    }

    public func totals(from: Int, until: Int) throws -> PeriodTotals {
        let sql = """
        SELECT motion, COUNT(*), COALESCE(SUM(distance), 0), COALESCE(SUM(peaks), 0)
        FROM seconds
        WHERE second >= \(from) AND second < \(until)
        GROUP BY motion
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryError.query(message(db))
        }
        defer { sqlite3_finalize(statement) }
        var totals = PeriodTotals()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            let motion = String(cString: text)
            let count = Int(sqlite3_column_int(statement, 1))
            let distance = sqlite3_column_double(statement, 2)
            let peaks = Int(sqlite3_column_int(statement, 3))
            switch DogMotion.stored(motion) {
            case .resting: totals.resting += count
            case .moving: totals.moving += count
            case nil: break
            }
            totals.distance += distance
            totals.peaks += peaks
        }
        return totals
    }

    public func rows(
        range: HistoryRange,
        containing date: Date,
        calendar: Calendar = .current,
        includeEmpty: Bool = false
    ) throws -> [HistoryRow] {
        let bounds = range.bounds(containing: date, calendar: calendar)
        var cursor = bounds.start
        var rows: [HistoryRow] = []
        let step: Calendar.Component = range == .day ? .hour : .day
        while cursor < bounds.end {
            guard let next = calendar.date(byAdding: step, value: 1, to: cursor) else { break }
            let chunkEnd = min(next, bounds.end)
            let totals = try totals(
                from: Int(cursor.timeIntervalSince1970.rounded(.down)),
                until: Int(chunkEnd.timeIntervalSince1970.rounded(.down))
            )
            if includeEmpty || totals.hasActivity {
                rows.append(HistoryRow(start: cursor, label: Self.label(cursor, step: step, calendar: calendar), totals: totals))
            }
            cursor = next
        }
        return rows
    }

    public func dayParts(containing date: Date, calendar: Calendar = .current) throws -> [DayPartSummary] {
        let start = calendar.startOfDay(for: date)
        var buckets = Dictionary(uniqueKeysWithValues: DayPart.allCases.map { ($0, PeriodTotals()) })
        for hour in 0..<24 {
            guard
                let cursor = calendar.date(byAdding: .hour, value: hour, to: start),
                let next = calendar.date(byAdding: .hour, value: 1, to: cursor)
            else { continue }
            let chunk = try totals(
                from: Int(cursor.timeIntervalSince1970.rounded(.down)),
                until: Int(next.timeIntervalSince1970.rounded(.down))
            )
            buckets[DayPart.part(forHour: hour), default: PeriodTotals()].merge(chunk)
        }
        return DayPart.allCases.map { part in
            DayPartSummary(part: part, totals: buckets[part] ?? PeriodTotals())
        }
    }

    public static func label(_ date: Date, step: Calendar.Component, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(step == .hour ? "j" : "EEEd")
        return formatter.string(from: date)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryError.query(message(db))
        }
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db else { return "sqlite failed" }
        return String(cString: sqlite3_errmsg(db))
    }
}

public enum HistoryError: Error, Equatable {
    case open(String)
    case query(String)
}
