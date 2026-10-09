import Foundation
import UserNotifications

/// 高指数事件前 1 小时提醒
enum NotificationScheduler {
    static let enabledKey = "notifyEnabled"
    static let thresholdKey = "notifyThreshold"
    private static let prefix = "afterglow."

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(events: [SkyEvent], placeName: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let threshold = defaults.object(forKey: thresholdKey) as? Double ?? 60

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        for e in events where !e.isPast && e.score >= threshold {
            let fire = e.sunTime.addingTimeInterval(-3600)
            guard fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(placeName) · \(e.kind.title)\(e.result.level.title)"
            content.body = "霞光指数 \(Int(e.score))，\(e.kind.sunTitle) \(fmt.string(from: e.sunTime))。\(e.result.summary)"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: prefix + e.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }
}
