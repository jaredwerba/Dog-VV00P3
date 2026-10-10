import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct VV00PApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(VV00PLaunch.self) private var launch
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(session: .shared)
                .preferredColorScheme(.dark)
        }
    }
}

#if canImport(UIKit)
final class VV00PLaunch: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            StrapSession.shared.restoreLink()
        }
        return true
    }
}
#endif
