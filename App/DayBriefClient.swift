import Foundation
import VV00PCore

enum DayBriefError: Error {
    case missingKey
    case requestFailed(Int)
    case unreadable
}

enum OpenRouterKey {
    static func load() -> String? {
        guard let url = Bundle.main.url(forResource: "OpenRouter", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let key = plist["APIKey"] as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20, !trimmed.contains("REPLACE") else { return nil }
        return trimmed
    }
}

/// One short completion. Solar Mini 4 with reasoning effort none is the cheap path:
/// about $0.05 per million prompt tokens and $0.20 per million completion tokens.
enum DayBriefClient {
    static let model = "upstage/solar-mini4"

    static func fetch(
        profile: DogProfile,
        today: PeriodTotals,
        yesterday: PeriodTotals,
        week: PeriodTotals,
        dayLabel: String,
        kind: DayBrief.Kind,
        strain: Double,
        yesterdayStrain: Double,
        averageSpeed: String
    ) async throws -> DayBrief.Note {
        guard let key = OpenRouterKey.load() else { throw DayBriefError.missingKey }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(profile.name, forHTTPHeaderField: "X-Title")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "max_tokens": 500,
            "reasoning": ["effort": "none"],
            "messages": [
                ["role": "system", "content": DayBrief.systemPrompt(for: kind)],
                ["role": "user", "content": DayBrief.userPrompt(
                    profile: profile,
                    today: today,
                    yesterday: yesterday,
                    week: week,
                    dayLabel: dayLabel,
                    kind: kind,
                    strain: strain,
                    yesterdayStrain: yesterdayStrain,
                    averageSpeed: averageSpeed
                )],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw DayBriefError.requestFailed(status) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let note = DayBrief.parse(content) else {
            throw DayBriefError.unreadable
        }
        return note
    }
}

enum DayBriefCache {
    private static let storageKey = "vv00p.dayBrief"

    struct Entry: Codable {
        var day: String
        var kind: String
        var note: DayBrief.Note
    }

    static func dayString(for date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func load(day: String, kind: String) -> DayBrief.Note? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.day == day,
              entry.kind == kind else { return nil }
        return entry.note
    }

    static func save(_ note: DayBrief.Note, day: String, kind: String) {
        let entry = Entry(day: day, kind: kind, note: note)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
