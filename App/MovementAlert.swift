import UserNotifications
import VV00PCore

final class MovementAlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MovementAlertCenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyMoving() {
        let content = UNMutableNotificationContent()
        let name = DogProfileStore.load().name
        content.title = name
        content.body = "\(name) has been moving for 5 minutes."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "max-moving-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
