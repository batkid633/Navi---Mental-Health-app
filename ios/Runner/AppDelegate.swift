import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let checkInIdentifier = "navi.daily.check_in"
  private var reminderChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NaviLocalCheckIn")!
    let channel = FlutterMethodChannel(name: "navi/local_check_in", binaryMessenger: registrar.messenger())
    reminderChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "configure" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.configureReminder(call.arguments, result: result)
    }
    UNUserNotificationCenter.current().delegate = self
  }

  private func configureReminder(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = arguments as? [String: Any],
          let enabled = arguments["enabled"] as? Bool,
          let minutes = arguments["timeMinutes"] as? Int,
          (0..<1440).contains(minutes) else {
      result(FlutterError(code: "invalid_reminder", message: "Invalid reminder time.", details: nil))
      return
    }
    let center = UNUserNotificationCenter.current()
    if !enabled {
      center.removePendingNotificationRequests(withIdentifiers: [checkInIdentifier])
      center.removeDeliveredNotifications(withIdentifiers: [checkInIdentifier])
      result(["scheduled": false, "permissionStatus": "disabled"])
      return
    }
    center.getNotificationSettings { settings in
      if settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
          if let error = error {
            self.reply(result, error: error)
            return
          }
          center.getNotificationSettings { updatedSettings in
            self.scheduleReminder(minutes: minutes, settings: updatedSettings, result: result)
          }
        }
      } else {
        self.scheduleReminder(minutes: minutes, settings: settings, result: result)
      }
    }
  }

  private func scheduleReminder(minutes: Int, settings: UNNotificationSettings,
                                result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    guard allowed else {
      center.removePendingNotificationRequests(withIdentifiers: [checkInIdentifier])
      DispatchQueue.main.async { result(["scheduled": false, "permissionStatus": "denied"]) }
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "Navi check-in"
    content.body = "Time for your daily check-in."
    content.sound = .default
    // No fixed timezone: repeat at the selected local clock time each day.
    var components = DateComponents()
    components.hour = minutes / 60
    components.minute = minutes % 60
    components.second = 0
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    // Reusing one identifier replaces the prior time without duplicate reminders.
    let request = UNNotificationRequest(identifier: checkInIdentifier, content: content, trigger: trigger)
    center.add(request) { error in
      if let error = error {
        self.reply(result, error: error)
        return
      }
      DispatchQueue.main.async {
        result([
          "scheduled": true,
          "permissionStatus": settings.authorizationStatus == .provisional ? "provisional" : "authorized",
        ])
      }
    }
  }

  private func reply(_ result: @escaping FlutterResult, error: Error) {
    DispatchQueue.main.async {
      result(FlutterError(code: "reminder_failed", message: error.localizedDescription, details: nil))
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      willPresent notification: UNNotification,
                                      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier == checkInIdentifier {
      completionHandler([.banner, .list, .sound])
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }
}
