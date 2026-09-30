import FactoryCore
import Foundation
import UserNotifications

final class SystemNotifier: Notifier {
    func notify(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Slop Factory"
        content.body = message
        deliver(content)
    }

    func notifyPosted(_ message: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Slop Factory"
        content.body = message
        content.userInfo = ["postURL": url.absoluteString]
        deliver(content)
    }

    private func deliver(_ content: UNMutableNotificationContent) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
