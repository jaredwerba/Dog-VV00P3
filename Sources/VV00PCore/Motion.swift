import Foundation

/// Starting stride for the English bulldog preset.
/// Kim, Kazmierczak, and Breur, Am J Vet Res 2011, measured a 0.83 m same-paw
/// walk stride on dogs over 25 kg. A 55 lb bulldog is about 25 kg and shorter
/// in the leg, so this starting value can read long until one measured walk.
public enum Bulldog {
    public static let dogName = "Max Werba"
    public static let name = "English Bulldog"
    public static let sex = "Male"
    public static let ageYears = 3
    public static let weightPounds = 55
    public static let metersPerPeak = 0.83
    /// Midpoint of the published stand mean (0.13 g) and walk mean (0.26 g).
    public static let walkOnsetG = 0.195
    /// Active adult English bulldogs are guided to about 20–40 minutes of easy
    /// activity a day, in short walks. Thirty minutes is the daily moving goal.
    /// Forty minutes is the usual ceiling, so the goal stays under it.
    public static let dailyMovingMinutes = 30
    public static let dailyMovingSeconds = dailyMovingMinutes * 60
    /// The sleep ring fills against 12 hours of resting. The stored label is still resting.
    public static let dailyRestingHours = 12
    public static let dailyRestingSeconds = dailyRestingHours * 60 * 60
}

/// Collar means from Karimjee, Harron, Piercy, and Daley, R Soc Open Sci 2024
/// set the walk-onset cut. At or below that cut the dog is resting. Above it
/// the dog is moving, and only moving adds distance.
public enum DogMotion: String, Equatable, Sendable {
    case resting
    case moving

    public var title: String {
        switch self {
        case .resting: return "Resting"
        case .moving: return "Moving"
        }
    }

    public var countsDistance: Bool { self == .moving }

    public static func classify(meanDynamicG: Double, walkOnsetG: Double) -> DogMotion {
        meanDynamicG <= walkOnsetG ? .resting : .moving
    }

    /// Older diaries stored lying and sitting as separate labels. Both are resting.
    public static func stored(_ raw: String) -> DogMotion? {
        switch raw {
        case "resting", "lying", "sitting":
            return .resting
        case "moving":
            return .moving
        default:
            return nil
        }
    }
}

public struct PaceConfig: Equatable, Sendable {
    public var metersPerPeak: Double
    public var thresholdG: Double
    public var minPeakGap: TimeInterval

    public init(metersPerPeak: Double, thresholdG: Double, minPeakGap: TimeInterval) {
        self.metersPerPeak = metersPerPeak
        self.thresholdG = thresholdG
        self.minPeakGap = minPeakGap
    }

    public static let englishBulldog = PaceConfig(
        metersPerPeak: Bulldog.metersPerPeak,
        thresholdG: Bulldog.walkOnsetG,
        minPeakGap: 0.25
    )
}

public struct PaceSnapshot: Equatable, Sendable {
    public var peakCount: Int
    public var distanceMeters: Double
    public var motion: DogMotion
    public var sampleCount: Int

    public var isMoving: Bool { motion == .moving }
}

public struct PaceModel {
    public var config: PaceConfig
    public private(set) var peakCount = 0
    public private(set) var sampleCount = 0

    private var window: [(time: TimeInterval, dynamicG: Double)] = []
    private var older: Double?
    private var previous: Double?
    private var lastPeakTime: TimeInterval?

    public init(config: PaceConfig = .englishBulldog) {
        self.config = config
    }

    public var motion: DogMotion {
        guard !window.isEmpty else { return .resting }
        let mean = window.reduce(0) { $0 + $1.dynamicG } / Double(window.count)
        return DogMotion.classify(meanDynamicG: mean, walkOnsetG: config.thresholdG)
    }

    public var distanceMeters: Double {
        Double(peakCount) * config.metersPerPeak
    }

    public mutating func ingest(
        time: TimeInterval,
        x: Double,
        y: Double,
        z: Double,
        counting: Bool
    ) -> PaceSnapshot {
        guard x.isFinite, y.isFinite, z.isFinite, time.isFinite else {
            return snapshot()
        }
        let magnitude = (x * x + y * y + z * z).squareRoot()
        let dynamic = abs(magnitude - 1)
        sampleCount += 1
        window.append((time, dynamic))
        let cutoff = time - 1
        window.removeAll { $0.time < cutoff }
        let motion = self.motion
        if counting, motion.countsDistance, let older, let previous {
            let isPeak = previous >= config.thresholdG && previous >= older && previous > dynamic
            let gap = lastPeakTime.map { time - $0 >= config.minPeakGap } ?? true
            if isPeak, gap {
                peakCount += 1
                lastPeakTime = time
            }
        }
        older = previous
        previous = dynamic
        return snapshot()
    }

    private func snapshot() -> PaceSnapshot {
        PaceSnapshot(
            peakCount: peakCount,
            distanceMeters: distanceMeters,
            motion: motion,
            sampleCount: sampleCount
        )
    }
}

public struct ClosedSecond: Equatable, Sendable {
    public var second: Int
    public var motion: DogMotion
    public var peaks: Int

    public init(second: Int, motion: DogMotion, peaks: Int) {
        self.second = second
        self.motion = motion
        self.peaks = peaks
    }

    public func distance(metersPerPeak: Double) -> Double {
        Double(peaks) * metersPerPeak
    }
}

/// Closes one record per strap second. A replay of the same second replaces it.
public struct SecondCloser {
    private var openSecond: Int?
    private var peaksAtOpen = 0
    private var latestMotion: DogMotion = .resting
    private var latestPeaks = 0

    public init() {}

    public mutating func observe(
        time: TimeInterval,
        motion: DogMotion,
        peakCount: Int
    ) -> ClosedSecond? {
        guard time.isFinite else { return nil }
        let second = Int(time.rounded(.down))
        guard let openSecond else {
            self.openSecond = second
            // The pace model starts at zero with the closer. Peaks already on this
            // first sample belong to the second being opened.
            peaksAtOpen = 0
            latestMotion = motion
            latestPeaks = peakCount
            return nil
        }
        if second == openSecond {
            latestMotion = motion
            latestPeaks = peakCount
            return nil
        }
        let closed = ClosedSecond(
            second: openSecond,
            motion: latestMotion,
            peaks: max(0, latestPeaks - peaksAtOpen)
        )
        self.openSecond = second
        peaksAtOpen = latestPeaks
        latestMotion = motion
        latestPeaks = peakCount
        return closed
    }

    public func flush() -> ClosedSecond? {
        guard let openSecond else { return nil }
        return ClosedSecond(
            second: openSecond,
            motion: latestMotion,
            peaks: max(0, latestPeaks - peaksAtOpen)
        )
    }
}

/// Counts a live run of moving seconds and asks for one alert at 10 seconds.
/// A resting second, or a stored second from outside the live window, starts over.
public struct MovingBout: Equatable, Sendable {
    public static let notifyAfterSeconds = 10
    public private(set) var streak = 0
    public private(set) var notified = false

    public init() {}

    public mutating func observe(motion: DogMotion, live: Bool) -> Bool {
        guard live else {
            streak = 0
            notified = false
            return false
        }
        switch motion {
        case .moving:
            streak += 1
            if streak >= Self.notifyAfterSeconds, !notified {
                notified = true
                return true
            }
            return false
        case .resting:
            streak = 0
            notified = false
            return false
        }
    }
}
