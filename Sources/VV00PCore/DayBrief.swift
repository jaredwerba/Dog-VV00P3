import Foundation

/// The daily note and dinner. Max is hardcoded for now: an active 3-year-old
/// English bulldog who needs at least 3 miles a day. The pantry is the only
/// food the note may use.
public enum DayBrief {
    public static let activity = "active"
    public static let minimumMiles = 3.0
    public static let pantry: [String] = [
        "ground beef",
        "turkey",
        "pumpkin",
        "plain Greek yogurt",
        "eggs",
        "blueberries",
        "venison",
        "lamb",
        "bison",
        "sardines",
        "yellowfin tuna",
    ]

    public struct Note: Equatable, Sendable, Codable {
        public var summary: String
        public var dinnerName: String
        public var ingredients: [String]
        public var steps: [String]

        public init(summary: String, dinnerName: String, ingredients: [String], steps: [String]) {
            self.summary = summary
            self.dinnerName = dinnerName
            self.ingredients = ingredients
            self.steps = steps
        }
    }

    public enum Kind: String, Sendable {
        case record
        case forecast
    }

    public static func systemPrompt(for kind: Kind) -> String {
        let dinner = "Dinner is one cooked meal, about 10 ounces, for this dog. Use a few pantry foods, not all of them. Cook meat and eggs. Plain pumpkin, unsweetened yogurt, no pie spice. Sardines or yellowfin tuna only as a small side. No onion, garlic, salt, grapes, raisins, xylitol, chocolate, or nutmeg."
        switch kind {
        case .record:
            return """
            Reply with JSON only, no markdown: {"summary":"","dinnerName":"","ingredients":[],"steps":[]}.
            Summary is one short sentence: today's distance target and strain target. Decide both from yesterday and the week. A hard yesterday can mean less today. Stay near the 3 mile minimum unless yesterday or the week was already hard. Strain is 0 to 21, and about 30 easy minutes is near 10. Do not describe the dog. Do not recap the day. Do not invent sleep stages or a recovery score.
            \(dinner)
            """
        case .forecast:
            return """
            Reply with JSON only, no markdown: {"summary":"","dinnerName":"","ingredients":[],"steps":[]}.
            Summary is one short sentence: tomorrow's distance target and strain target, from the day and the week given. A harder day can mean a shorter tomorrow. Do not describe the dog. Do not invent sleep stages or a recovery score.
            \(dinner)
            """
        }
    }

    public static func userPrompt(
        profile: DogProfile,
        today: PeriodTotals,
        yesterday: PeriodTotals,
        week: PeriodTotals,
        dayLabel: String,
        kind: Kind,
        strain: Double,
        yesterdayStrain: Double,
        averageSpeed: String
    ) -> String {
        let focus = kind == .forecast
            ? "Summary: one short sentence with tomorrow's distance and strain."
            : "Summary: one short sentence with today's distance target and strain target, from yesterday and the week. Do not summarize the dog."
        return """
        Dog: \(profile.name), \(Bulldog.sex.lowercased()) \(profile.breed), \(profile.weightPounds) lb, \(profile.ageYears) years old, \(activity).
        Minimum movement: \(DistanceUnit.miles.text(meters: minimumMiles * DistanceUnit.metersPerMile)) a day.
        Day: \(dayLabel).
        That day: \(line(today)).
        Strain: \(String(format: "%.1f", strain)) of 21.
        Average moving speed: \(averageSpeed).
        Yesterday: \(line(yesterday)).
        Yesterday strain: \(String(format: "%.1f", yesterdayStrain)) of 21.
        Week: \(line(week)).
        Pantry: \(pantry.joined(separator: ", ")).
        \(focus)
        """
    }

    public static func parse(_ raw: String) -> Note? {
        let text = jsonObject(in: raw)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = clean(object["summary"]),
              let name = clean(object["dinnerName"]) else { return nil }
        let ingredients = list(object["ingredients"])
        let steps = list(object["steps"])
        guard !summary.isEmpty, !name.isEmpty, !ingredients.isEmpty, !steps.isEmpty else { return nil }
        return Note(summary: summary, dinnerName: name, ingredients: ingredients, steps: steps)
    }

    private static func line(_ totals: PeriodTotals) -> String {
        let miles = DistanceUnit.miles.text(meters: totals.distance)
        return "\(miles), \(duration(totals.resting)) resting, \(duration(totals.moving)) moving"
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private static func jsonObject(in raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return text }
        return String(text[start...end])
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func list(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            guard let text = item as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
