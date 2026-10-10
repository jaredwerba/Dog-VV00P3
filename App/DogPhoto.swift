import CoreTransferable
import VV00PCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImportedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedPhoto(data: data)
        }
    }
}

enum DogPhotoStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("VV00P", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("max.photo")
    }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func save(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum DogPhotoImage {
    static func make(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

struct GaugeLevels: Equatable {
    var sleep: Double
    var movement: Double
    var strain: Double
}

/// Pull-to-refresh drives the three rings through a full circle, then back to the live readings.
struct GaugeSweep: Equatable {
    var started: Date
    var originSleep: Double
    var originMovement: Double
    var originStrain: Double
    var settling: Bool

    static let fill: TimeInterval = 0.62
    static let settle: TimeInterval = 0.8
    static let stagger: TimeInterval = 0.08

    var fillDuration: TimeInterval { Self.fill + Self.stagger * 2 }
    var settleDuration: TimeInterval { Self.settle + Self.stagger * 2 }

    func levels(sleep: Double, movement: Double, strain: Double, now: Date) -> GaugeLevels {
        let elapsed = now.timeIntervalSince(started)
        if settling {
            return GaugeLevels(
                sleep: Self.mix(from: 1, to: sleep, elapsed: elapsed, delay: 0, duration: Self.settle, easeIn: false),
                movement: Self.mix(from: 1, to: movement, elapsed: elapsed, delay: Self.stagger, duration: Self.settle, easeIn: false),
                strain: Self.mix(from: 1, to: strain, elapsed: elapsed, delay: Self.stagger * 2, duration: Self.settle, easeIn: false)
            )
        }
        return GaugeLevels(
            sleep: Self.mix(from: originSleep, to: 1, elapsed: elapsed, delay: 0, duration: Self.fill, easeIn: true),
            movement: Self.mix(from: originMovement, to: 1, elapsed: elapsed, delay: Self.stagger, duration: Self.fill, easeIn: true),
            strain: Self.mix(from: originStrain, to: 1, elapsed: elapsed, delay: Self.stagger * 2, duration: Self.fill, easeIn: true)
        )
    }

    private static func mix(
        from: Double,
        to: Double,
        elapsed: TimeInterval,
        delay: TimeInterval,
        duration: TimeInterval,
        easeIn: Bool
    ) -> Double {
        let t = min(1, max(0, (elapsed - delay) / duration))
        let eased = easeIn ? t * t : 1 - pow(1 - t, 3)
        return from + (to - from) * eased
    }
}

struct DogPhotoPicker<Middle: View>: View {
    var profile: DogProfile
    var sleep: Double
    var movement: Double
    var strain: Double
    var sleepValue: String
    var movementValue: String
    var movementCaption: String
    var strainValue: String
    var velocity: String
    var gaugeSweep: GaugeSweep?
    @ViewBuilder var middle: () -> Middle

    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showChange = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                showChange.toggle()
            } label: {
                portrait
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photoData == nil ? "Add a photo of \(profile.name)" : "Photo of \(profile.name)")
            .accessibilityHint(photoData == nil ? "Shows the add photo button" : "Shows the change photo button")

            VStack(spacing: 2) {
                Text(profile.name)
                    .military(28, bold: true)
                Text(profile.breed)
                    .military(15, bold: true)
                Text("\(Bulldog.sex) · \(profile.ageYears) years old · \(profile.weightPounds) lb")
                    .military(13)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if photoData == nil || showChange {
                Button(photoData == nil ? "Add photo" : "Change photo") {
                    showPicker = true
                }
                .buttonStyle(.bordered)
                .military(15, bold: true)
                .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
            }

            middle()

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: gaugeSweep == nil)) { context in
                let levels = gaugeSweep?.levels(
                    sleep: sleep,
                    movement: movement,
                    strain: strain,
                    now: context.date
                ) ?? GaugeLevels(sleep: sleep, movement: movement, strain: strain)
                HStack(alignment: .top, spacing: 8) {
                    metricRing("Rest", sleepValue, "of \(Bulldog.dailyRestingHours)h", levels.sleep, Color(red: 0.36, green: 0.72, blue: 0.98))
                    metricRing("Movement", movementValue, movementCaption, levels.movement, Color(red: 0.20, green: 0.84, blue: 0.38))
                    metricRing("Strain", strainValue, "of 21", levels.strain, Color(red: 0.98, green: 0.27, blue: 0.35))
                }
            }
            .padding(.horizontal, 24)
            Text(velocity)
                .military(13)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            photoData = DogPhotoStore.load()
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                guard let photo = try? await item.loadTransferable(type: ImportedPhoto.self), !photo.data.isEmpty else { return }
                DogPhotoStore.save(photo.data)
                photoData = photo.data
                showChange = false
            }
        }
    }

    private func metricRing(_ title: String, _ value: String, _ caption: String, _ progress: Double, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .military(14, bold: true)
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(value), \(caption)")
            Text(title)
                .military(12, bold: true)
                .foregroundStyle(tint)
            Text(caption)
                .military(11)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var portrait: some View {
        photoFill
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var photoFill: some View {
        if let photoData, let image = DogPhotoImage.make(photoData) {
            image
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .overlay {
                    Image(systemName: "dog.fill")
                        .military(36)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
