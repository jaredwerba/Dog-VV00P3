import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MilitaryFont {
    static let regular = "OCRA"
    static let bold = "OCRABold"

    static func register() {
        for file in ["OCRA", "OCRABold"] {
            let urls = [
                Bundle.main.url(forResource: file, withExtension: "ttf"),
                Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts"),
            ]
            for url in urls.compactMap({ $0 }) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        #if canImport(UIKit)
        let large = UIFont(name: bold, size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        let body = UIFont(name: regular, size: 17) ?? .systemFont(ofSize: 17)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: large]
        bar.titleTextAttributes = [.font: body]
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: body.withSize(12)],
            for: .normal
        )
        #endif
    }

    static func text(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? Self.bold : regular, size: size)
    }
}

extension View {
    func military(_ size: CGFloat, bold: Bool = false) -> some View {
        font(MilitaryFont.text(size, bold: bold))
    }
}
