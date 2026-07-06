//
//  PushService.swift
//  InterlinedList
//

import UIKit
import UserNotifications
import os.log

private let pushLog = Logger(subsystem: "com.interlinedlist.app", category: "PushService")

@MainActor
final class PushService: NSObject {
    static let shared = PushService()

    private var registeredToken: String?

    private override init() { super.init() }

    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                pushLog.error("Push permission error: \(error)")
                return
            }
            guard granted else {
                pushLog.info("Push permission denied")
                return
            }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != registeredToken else { return }
        registeredToken = token
        pushLog.info("APNs device token registered")
        Task {
            do {
                try await APIClient.shared.registerPushDevice(token: token)
            } catch {
                pushLog.error("Failed to register push device: \(error)")
                registeredToken = nil
            }
        }
    }

    func didFailToRegister(error: Error) {
        pushLog.error("APNs registration failed: \(error)")
    }

    func unregister() {
        guard let token = registeredToken else { return }
        registeredToken = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        Task {
            do {
                try await APIClient.shared.unregisterPushDevice(token: token)
            } catch {
                pushLog.error("Failed to unregister push device: \(error)")
            }
        }
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error { pushLog.error("Badge clear error: \(error)") }
        }
    }

    func handleForegroundNotification(
        _ notification: UNNotification,
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        guard let actionUrl = userInfo["actionUrl"] as? String,
              let url = URL(string: actionUrl) else { return }
        UIApplication.shared.open(url)
    }
}
