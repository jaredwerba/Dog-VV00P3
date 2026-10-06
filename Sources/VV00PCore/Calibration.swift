import Foundation

/// A known walk turns peak count into meters per peak.
/// The strap keeps counting peaks on its own. The entered distance is the ruler.
public enum StrideCalibration {
    public static let minimumPeaks = 8
    public static let minimumMetersPerPeak = 0.05
    public static let maximumMetersPerPeak = 3.0

    public static func metersPerPeak(knownMeters: Double, peaks: Int) -> Double? {
        guard knownMeters.isFinite, knownMeters > 0, peaks >= minimumPeaks else { return nil }
        let stride = knownMeters / Double(peaks)
        guard stride.isFinite, stride >= minimumMetersPerPeak, stride <= maximumMetersPerPeak else {
            return nil
        }
        return stride
    }
}
