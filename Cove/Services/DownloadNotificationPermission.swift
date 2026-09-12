import Models
import UserNotifications
import os

/// Asks for notification permission the first time it could actually matter.
///
/// The only notification Cove sends is "your download finished", so asking at
/// launch — before the user has connected to a server, let alone queued
/// anything — is a prompt with no context behind it. This defers the ask to the
/// first download, where the payoff is obvious.
enum DownloadNotificationPermission {

    private static let logger = Logger(
        subsystem: AppConstants.bundleIdentifier, category: "Notifications")

    /// Request authorization if the user has not been asked yet.
    ///
    /// Safe to call on every download; the system is only consulted once and the
    /// prompt only ever appears for `.notDetermined`.
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else {
            return
        }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Declining is a normal outcome; downloads work either way.
            logger.info("Notification authorization not granted: \(error.localizedDescription)")
        }
    }
}
