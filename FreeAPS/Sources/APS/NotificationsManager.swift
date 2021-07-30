import Combine
import Foundation
import SwiftDate
import Swinject
import UserNotifications

protocol NotificationsManager {}

final class BaseNotificationsManager: NotificationsManager, Injectable {
    class NotificationsDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            completionHandler()
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.badge, .sound, .alert])
        }
    }

    var delegate: NotificationsDelegate = {
        NotificationsDelegate()
    }()

    init(resolver: Resolver) {
        injectServices(resolver)
        requestNotificationPermissions()
    }

    func requestNotificationPermissions() {
        //important! DONT USE debug() here. Doing so will create a race condition

        // debug(.apsManager, "freeaps requestNotificationPermissions called")
        print("freeaps requestNotificationPermissions called")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                // debug(.apsManager, "freeaps requestNotificationPermissions was granted")
                print("freeaps requestNotificationPermissions was granted")
            } else {
                // debug(.apsManager, "freeaps requestNotificationPermissions failed because of error: \(String(describing: error))")
                print("freeaps requestNotificationPermissions failed because of error: \(String(describing: error))")
            }
        }
        // We must register a delegate even if our delegate basically is a no-op
        // this ensures that our app and any cgm/pump plugins can send notifications while
        // application is in foreground
        center.delegate = delegate
    }
}
