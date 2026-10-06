import Foundation

public enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case meters
    case miles

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meters: return "Meters"
        case .miles: return "Miles"
        }
    }

    public static let metersPerMile = 1_609.344

    public func meters(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        switch self {
        case .meters:
            return value
        case .miles:
            return value * Self.metersPerMile
        }
    }

    public func text(meters: Double) -> String {
        switch self {
        case .meters:
            if meters >= 1_000 {
                return String(format: "%.2f km", meters / 1_000)
            }
            return String(format: "%.1f m", meters)
        case .miles:
            return String(format: "%.2f mi", meters / Self.metersPerMile)
        }
    }
}
