import Foundation

/// The one-sentence activity reply. The figures come from the diary.
/// Three miles a day is the movement goal. Three walks a day is the advice.
public enum ActivityReport {
    public static let walksPerDay = 3

    public static var dailyMeters: Double {
        DayBrief.minimumMiles * DistanceUnit.metersPerMile
    }

    public static var weeklyMeters: Double {
        dailyMeters * 7
    }

    public static func percent(todayMeters: Double) -> Int {
        guard dailyMeters > 0, todayMeters.isFinite else { return 0 }
        let ratio = max(0, todayMeters) / dailyMeters
        return Int((ratio * 100).rounded())
    }

    public static func sentence(
        name: String,
        todayMeters: Double,
        weekMeters: Double,
        unit: DistanceUnit
    ) -> String {
        let dog = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Bulldog.dogName : name
        let today = unit.text(meters: max(0, todayMeters))
        let week = unit.text(meters: max(0, weekMeters))
        let dayGoal = unit.text(meters: dailyMeters)
        let weekGoal = unit.text(meters: weeklyMeters)
        let share = percent(todayMeters: todayMeters)
        return "\(dog) has been moving \(today) today, \(week) this week, and is \(share)% of the daily goal. Be sure to walk him \(walksPerDay) times a day for a total of \(dayGoal) a day, \(weekGoal) a week."
    }

    public static let openingQuestion = "tell me about max activity?"
}
