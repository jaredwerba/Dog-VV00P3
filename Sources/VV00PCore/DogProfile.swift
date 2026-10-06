import Foundation

/// The dog shown on the diary. Defaults are Max. Settings can replace them.
public struct DogProfile: Equatable, Sendable, Codable {
    public var name: String
    public var breed: String
    public var ageYears: Int
    public var weightPounds: Int

    public init(name: String, breed: String, ageYears: Int, weightPounds: Int) {
        self.name = name
        self.breed = breed
        self.ageYears = ageYears
        self.weightPounds = weightPounds
    }

    public static let starter = DogProfile(
        name: Bulldog.dogName,
        breed: Bulldog.name,
        ageYears: Bulldog.ageYears,
        weightPounds: Bulldog.weightPounds
    )

    public func cleaned() -> DogProfile {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBreed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmedName.isEmpty ? Bulldog.dogName : trimmedName
        copy.breed = trimmedBreed.isEmpty ? Bulldog.name : trimmedBreed
        copy.ageYears = min(30, max(0, ageYears))
        copy.weightPounds = min(200, max(1, weightPounds))
        return copy
    }
}

public enum DogProfileStore {
    public static let defaultsKey = "vv00p.profile"

    public static func load(defaults: UserDefaults = .standard) -> DogProfile {
        guard let data = defaults.data(forKey: defaultsKey),
              let profile = try? JSONDecoder().decode(DogProfile.self, from: data) else {
            return .starter
        }
        return profile.cleaned()
    }

    public static func save(_ profile: DogProfile, defaults: UserDefaults = .standard) {
        let clean = profile.cleaned()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
