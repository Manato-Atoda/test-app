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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VamosGlassPlugin") {
      VamosGlassPlugin.register(with: registrar)
    }
  }
}

// MARK: - Liquid Glass

/// iOS のリキッドグラス（UIGlassEffect）を Flutter の画面に重ねて使えるようにする。
///
/// - `vamos/glass`（PlatformView）: ガラスの面だけを描く。アイコンや文字は Flutter が上に描く
/// - `vamos/glass`（MethodChannel）: 使えるか（iOS 26 以降・「透明度を下げる」がオフ）を返す
final class VamosGlassPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VamosGlassPlugin()
    let channel = FlutterMethodChannel(name: "vamos/glass", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(VamosGlassViewFactory(), withId: "vamos/glass")
    registrar.register(VamosTabBarFactory(messenger: registrar.messenger()), withId: "vamos/tabbar")
    registrar.register(VamosGlassButtonFactory(messenger: registrar.messenger()), withId: "vamos/glassbutton")
    NotificationCenter.default.addObserver(
      instance,
      selector: #selector(accessibilityChanged),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
  }

  static var isSupported: Bool {
    if #available(iOS 26.0, *) {
      return !UIAccessibility.isReduceTransparencyEnabled
    }
    return false
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(Self.isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 「設定」で「透明度を下げる」が切り替わったら Dart 側に知らせる
  @objc private func accessibilityChanged() {
    channel?.invokeMethod("onSupportChanged", arguments: Self.isSupported)
  }
}

final class VamosGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    VamosGlassPlatformView(frame: frame, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class VamosGlassPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, arguments: [String: Any]) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isUserInteractionEnabled = false

    let effectView = UIVisualEffectView(effect: Self.makeEffect(arguments))
    effectView.frame = container.bounds
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let radius = (arguments["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    if radius > 0 {
      effectView.layer.cornerRadius = radius
      effectView.layer.cornerCurve = .continuous
      effectView.clipsToBounds = true
    }
    container.addSubview(effectView)
    super.init()
  }

  func view() -> UIView { container }

  private static func makeEffect(_ arguments: [String: Any]) -> UIVisualEffect {
    if #available(iOS 26.0, *) {
      let style: UIGlassEffect.Style = (arguments["style"] as? String) == "clear" ? .clear : .regular
      let glass = UIGlassEffect(style: style)
      if let argb = (arguments["tint"] as? NSNumber)?.uint32Value {
        glass.tintColor = UIColor(
          red: CGFloat((argb >> 16) & 0xFF) / 255,
          green: CGFloat((argb >> 8) & 0xFF) / 255,
          blue: CGFloat(argb & 0xFF) / 255,
          alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
      }
      return glass
    }
    return UIBlurEffect(style: .systemThinMaterial)
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

// MARK: - 本物のタブバー（リキッドグラスのアニメーションつき）

/// iOS の UITabBar をそのまま使う。選択の「レンズ」が滑る動き・押したときの反応・
/// 指でなぞってタブを切り替える操作は、すべて iOS 標準の動きになる。
final class VamosTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    VamosTabBarView(frame: frame, viewId: viewId, messenger: messenger, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class VamosTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    channel = FlutterMethodChannel(name: "vamos/tabbar/\(viewId)", binaryMessenger: messenger)
    super.init()

    let items = (arguments["items"] as? [[String: Any]] ?? []).enumerated().map { index, item in
      let tabItem = UITabBarItem(
        title: item["title"] as? String,
        image: UIImage(systemName: item["symbol"] as? String ?? "circle"),
        selectedImage: UIImage(systemName: item["selectedSymbol"] as? String ?? item["symbol"] as? String ?? "circle")
      )
      tabItem.tag = index
      return tabItem
    }
    tabBar.items = items
    let selected = (arguments["selected"] as? NSNumber)?.intValue ?? 0
    if items.indices.contains(selected) {
      tabBar.selectedItem = items[selected]
    }
    if let argb = (arguments["tint"] as? NSNumber)?.uint32Value {
      tabBar.tintColor = UIColor(argb: argb)
    }
    tabBar.delegate = self
    tabBar.frame = container.bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(tabBar)

    // Flutter 側からタブを切り替えた場合（ホームの「すべて見る」など）
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "select", let index = call.arguments as? Int, let self, let items = self.tabBar.items,
         items.indices.contains(index) {
        self.tabBar.selectedItem = items[index]
      }
      result(nil)
    }
  }

  func view() -> UIView { container }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("onSelect", arguments: item.tag)
  }
}

// MARK: - ガラスのボタン（押すとガラスが反応する）

final class VamosGlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    VamosGlassButtonView(frame: frame, viewId: viewId, messenger: messenger, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class VamosGlassButtonView: NSObject, FlutterPlatformView {
  private let button: UIButton
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    channel = FlutterMethodChannel(name: "vamos/glassbutton/\(viewId)", binaryMessenger: messenger)
    var config: UIButton.Configuration
    if #available(iOS 26.0, *) {
      config = .glass()
    } else {
      config = .gray()
    }
    config.cornerStyle = .capsule
    let image = UIImage(
      systemName: arguments["symbol"] as? String ?? "circle",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    )
    let foreground = (arguments["tint"] as? NSNumber).map { UIColor(argb: $0.uint32Value) } ?? .label
    // ガラスのボタンはアイコンの色を自動で決めるため、色を指定したいときは画像自体に色をつける
    config.image = arguments["tint"] == nil ? image : image?.withTintColor(foreground, renderingMode: .alwaysOriginal)
    config.baseForegroundColor = foreground
    button = UIButton(configuration: config)
    // ガラスのボタンはアイコンの色に tintColor を使うため、両方に設定する
    button.tintColor = foreground
    button.frame = CGRect(origin: .zero, size: frame.size)
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    button.accessibilityLabel = arguments["label"] as? String
    super.init()
    button.addAction(UIAction { [weak self] _ in
      self?.channel.invokeMethod("onTap", arguments: nil)
    }, for: .primaryActionTriggered)
  }

  func view() -> UIView { button }
}

extension UIColor {
  /// Flutter の Color（0xAARRGGBB）から作る
  convenience init(argb: UInt32) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
