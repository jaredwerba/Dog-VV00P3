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
        content.title = Bulldog.dogName
        content.body = "Max has been moving for more than 10 seconds."
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
