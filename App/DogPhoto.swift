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

struct DogPhotoPicker: View {
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
            .accessibilityLabel(photoData == nil ? "Add a photo of Max" : "Photo of Max Werba")
            .accessibilityHint(photoData == nil ? "Shows the add photo button" : "Shows the change photo button")

            VStack(spacing: 2) {
                Text(Bulldog.dogName)
                    .military(28, bold: true)
                Text(Bulldog.name)
                    .military(15, bold: true)
                Text("\(Bulldog.sex) · \(Bulldog.ageYears) years old · \(Bulldog.weightPounds) lb")
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
