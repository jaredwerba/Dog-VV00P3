import Foundation

/// A basic 0–21 strain score from saved seconds.
/// Each moving second adds more when it has more peaks, so a fast mile scores
/// higher than the same distance walked slowly. Each time moving starts again
/// adds a little more, so a chase with stops scores higher than one steady walk.
/// Saved seconds do not include a heading, so sideways turns are not part of this score.
public struct StrainScore: Equatable, Sendable {
    public var strain: Double
    public var averageMetersPerSecond: Double
    public var peakMetersPerSecond: Double
    public var starts: Int

    public init(
        strain: Double,
        averageMetersPerSecond: Double,
        peakMetersPerSecond: Double,
        starts: Int
    ) {
        self.strain = strain
        self.averageMetersPerSecond = averageMetersPerSecond
        self.peakMetersPerSecond = peakMetersPerSecond
        self.starts = starts
    }

    public static let quiet = StrainScore(
        strain: 0,
        averageMetersPerSecond: 0,
        peakMetersPerSecond: 0,
        starts: 0
    )
}

public enum StrainModel {
    public static let scale = 21.0
    /// Load for one easy moving second is 2 (one peak). About 30 minutes of that
    /// lands near 10 on the 0–21 scale.
    public static let loadScale = 5_570.0
    public static let startLoad = 8.0

    public static func score(_ seconds: [StoredSecond]) -> StrainScore {
        var load = 0.0
        var movingTime = 0
        var movingDistance = 0.0
        var peakSpeed = 0.0
        var starts = 0
        var previous: DogMotion?
        for second in seconds {
            if second.motion == .moving {
                if previous != .moving {
                    starts += 1
                }
                let peaks = max(0, second.peaks)
                load += 1 + Double(peaks * peaks)
                let speed = max(0, second.distance)
                movingTime += 1
                movingDistance += speed
                peakSpeed = max(peakSpeed, speed)
            }
            previous = second.motion
        }
        load += Double(starts) * startLoad
        let strain = movingTime == 0 ? 0 : scale * (1 - exp(-load / loadScale))
        let average = movingTime > 0 ? movingDistance / Double(movingTime) : 0
        return StrainScore(
            strain: min(scale, max(0, strain)),
            averageMetersPerSecond: average,
            peakMetersPerSecond: peakSpeed,
            starts: starts
        )
    }
}
