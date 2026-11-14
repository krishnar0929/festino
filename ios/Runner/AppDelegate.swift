import ContactsUI
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let contactPicker = ContactPicker()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets party reminders show as banners even while Festino is open.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Hands reels saved by the "Share to Festino" extension to the Flutter app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HooplaSharedReels") {
      let channel = FlutterMethodChannel(name: "hoopla/share", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "takeSharedReels" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let defaults = UserDefaults(suiteName: "group.com.northbitapps.hoopla")
        let items = defaults?.array(forKey: "pendingReels") ?? []
        defaults?.removeObject(forKey: "pendingReels")
        result(items)
      }
    }

    // Apple's own contact picker for party invites (pick several; no contacts permission needed).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HooplaContacts") {
      let channel = FlutterMethodChannel(name: "hoopla/contacts", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "pick" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.contactPicker.present(result: result)
      }
    }
  }
}

/// Shows CNContactPickerViewController and returns [{name, phone, email}] for the people picked.
final class ContactPicker: NSObject, CNContactPickerDelegate {
  private var pending: FlutterResult?

  func present(result: @escaping FlutterResult) {
    guard pending == nil, let top = ContactPicker.topViewController() else {
      result([])
      return
    }
    pending = result
    let picker = CNContactPickerViewController()
    picker.delegate = self
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
    picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
    top.present(picker, animated: true)
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
    let people: [[String: String]] = contacts.map { c in
      let name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
      return [
        "name": name,
        "phone": c.phoneNumbers.first?.value.stringValue ?? "",
        "email": c.emailAddresses.first.map { $0.value as String } ?? "",
      ]
    }
    pending?(people)
    pending = nil
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    pending?([])
    pending = nil
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
