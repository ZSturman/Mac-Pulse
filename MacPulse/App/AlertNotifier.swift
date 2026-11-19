import AppKit
import OSLog
import UserNotifications

/// Posts local notifications for new alerts and routes clicks back to the dashboard.
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotifier()
    static let enabledKey = "alertNotifications"
    private static let log = Logger(subsystem: "com.local.MacPulse", category: "alerts")

    private var center: UNUserNotificationCenter { .current() }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func start() {
        center.delegate = self
        if Self.isEnabled { requestAuthorization() }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.log.notice("Notification authorization granted: \(granted, privacy: .public)")
            }
        }
    }

    func authorizationDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func post(_ alerts: [SystemAlert]) {
        guard Self.isEnabled else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.message
            content.sound = alert.isCritical ? .default : nil
            content.userInfo = ["page": alert.kind.involvesProcesses ? "processes" : "overview"]
            content.threadIdentifier = alert.kind.rawValue
            // Reusing an identifier silently updates the old notification without a banner, so each post is unique;
            // older ones of the same kind are removed to keep one per kind in Notification Center.
            let prefix = "alert.\(alert.kind.rawValue)."
            center.getDeliveredNotifications { [center] delivered in
                center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) })
            }
            center.add(UNNotificationRequest(identifier: prefix + UUID().uuidString, content: content, trigger: nil)) { error in
                if let error {
                    Self.log.error("Could not post \(alert.kind.rawValue, privacy: .public) alert: \(error.localizedDescription, privacy: .public)")
                } else {
                    Self.log.notice("Posted \(alert.kind.rawValue, privacy: .public) alert")
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let page = response.notification.request.content.userInfo["page"] as? String ?? "overview"
        DispatchQueue.main.async { Self.openDashboard(page: page) }
        completionHandler()
    }

    /// Opens this exact app copy's URL route so SwiftUI brings the dashboard window back, even when it was closed.
    static func openDashboard(page: String) {
        guard let url = URL(string: "macpulse://\(page)") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
