import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 通知の表示・タップを FlutterAppDelegate 経由でプラグインに届ける
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VamosPushPlugin") {
      VamosPushPlugin.register(with: registrar)
    }
  }
}

/// プッシュ通知の許可・端末トークン・通知タップを Dart 側（vamos/push）へつなぐ。
///
/// 試作のため Firebase は使わず、APNs の仕組みをそのまま使う。
/// シミュレーターでは `xcrun simctl push` で届いた通知を表示・タップできる。
final class VamosPushPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var flutterReady = false
  private var pendingLink: String?
  private var permissionResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VamosPushPlugin()
    let channel = FlutterMethodChannel(name: "vamos/push", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      // Dart 側の準備ができた。起動前にタップされた通知があれば渡す
      flutterReady = true
      result(pendingLink)
      pendingLink = nil
    case "requestPermission":
      requestPermission(result: result)
    case "isEnabled":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async { result(settings.authorizationStatus == .authorized) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      DispatchQueue.main.async {
        guard granted else {
          result(Self.response(granted: false, token: nil))
          return
        }
        self.permissionResult = result
        UIApplication.shared.registerForRemoteNotifications()
        // シミュレーターなどでトークンが取れない場合に備えて待ち時間を区切る
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.finishPermission(token: nil) }
      }
    }
  }

  private func finishPermission(token: String?) {
    guard let result = permissionResult else { return }
    permissionResult = nil
    result(Self.response(granted: true, token: token))
  }

  private static func response(granted: Bool, token: String?) -> [String: Any] {
    #if targetEnvironment(simulator)
    let simulator = true
    #else
    let simulator = false
    #endif
    return ["granted": granted, "token": token ?? NSNull(), "simulator": simulator]
  }

  private func deliver(link: String) {
    if flutterReady, let channel {
      channel.invokeMethod("onNotificationTap", arguments: link)
    } else {
      pendingLink = link
    }
  }

  // MARK: - FlutterApplicationLifeCycleDelegate

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    finishPermission(token: deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    finishPermission(token: nil)
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // アプリを開いている間も、バナーで表示する
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let link = response.notification.request.content.userInfo["link"] as? String {
      deliver(link: link)
    }
    completionHandler()
  }
}
