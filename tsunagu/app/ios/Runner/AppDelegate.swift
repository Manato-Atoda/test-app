import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TsunaguGlassPlugin") {
      TsunaguGlassPlugin.register(with: registrar)
    }
  }
}

// MARK: - Liquid Glass

/// iOS のリキッドグラスを Flutter の画面で使えるようにする。
///
/// - `tsunagu/glass`（MethodChannel）: 使えるか（iOS 26 以降・「透明度を下げる」がオフ）を返す
/// - `tsunagu/tabbar`: iOS 本物の UITabBar（選択のレンズ・押したときの反応・なぞって切り替え）
/// - `tsunagu/glassbutton`: 押すとガラスが反応する iOS 本物のボタン（アイコンのみ / 文字つき）
final class TsunaguGlassPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TsunaguGlassPlugin()
    let channel = FlutterMethodChannel(name: "tsunagu/glass", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(TsunaguTabBarFactory(messenger: registrar.messenger()), withId: "tsunagu/tabbar")
    registrar.register(TsunaguGlassButtonFactory(messenger: registrar.messenger()), withId: "tsunagu/glassbutton")
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

// MARK: - 本物のタブバー

final class TsunaguTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    TsunaguTabBarView(frame: frame, viewId: viewId, messenger: messenger, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class TsunaguTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    channel = FlutterMethodChannel(name: "tsunagu/tabbar/\(viewId)", binaryMessenger: messenger)
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
    if let argb = (arguments["tint"] as? NSNumber)?.uint32Value {
      tabBar.tintColor = UIColor(argb: argb)
    }
    select((arguments["selected"] as? NSNumber)?.intValue ?? 0)
    setBadges(arguments["badges"])
    tabBar.delegate = self
    tabBar.frame = container.bounds
    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(tabBar)

    // Flutter 側からの更新（選択中のタブ・未読の数）
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "select":
        if let index = call.arguments as? Int { self?.select(index) }
      case "setBadges":
        self?.setBadges(call.arguments)
      default:
        break
      }
      result(nil)
    }
  }

  func view() -> UIView { container }

  private func select(_ index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  /// 未読の数などのバッジ（空文字はバッジなし、"dot" は数のない赤い点）
  private func setBadges(_ value: Any?) {
    guard let badges = value as? [String], let items = tabBar.items else { return }
    for (index, item) in items.enumerated() {
      let badge = badges.indices.contains(index) ? badges[index] : ""
      switch badge {
      case "":
        item.badgeValue = nil
      case "dot":
        // 空文字のバッジは、数字のない小さな点として表示される
        item.badgeValue = ""
      default:
        item.badgeValue = badge
      }
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("onSelect", arguments: item.tag)
  }
}

// MARK: - ガラスのボタン

final class TsunaguGlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    TsunaguGlassButtonView(frame: frame, viewId: viewId, messenger: messenger, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// - アイコンだけ（戻る・検索など）: 透明なガラス
/// - 文字つき・prominent（「投稿」など）: 色つきのガラス（tint の色）に白い文字
final class TsunaguGlassButtonView: NSObject, FlutterPlatformView {
  private let button: UIButton
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: [String: Any]) {
    channel = FlutterMethodChannel(name: "tsunagu/glassbutton/\(viewId)", binaryMessenger: messenger)
    let prominent = (arguments["prominent"] as? Bool) ?? false
    let tint = (arguments["tint"] as? NSNumber).map { UIColor(argb: $0.uint32Value) }

    var config: UIButton.Configuration
    if #available(iOS 26.0, *) {
      config = prominent ? .prominentGlass() : .glass()
    } else {
      config = prominent ? .filled() : .gray()
    }
    config.cornerStyle = .capsule
    let symbolSize: CGFloat = (arguments["title"] as? String) == nil ? 16 : 15
    // 文字だけのボタン（「参加する」など）はアイコンなし
    let image = (arguments["symbol"] as? String).flatMap {
      UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold))
    }
    if let title = arguments["title"] as? String {
      config.title = title
      config.imagePadding = 6
      config.titleLineBreakMode = .byClipping
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var updated = attributes
        updated.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        return updated
      }
    }

    if prominent {
      // 色つきのガラス: ガラスの色に tint、文字とアイコンは白
      config.image = image
      config.baseForegroundColor = .white
      button = UIButton(configuration: config)
      button.tintColor = tint
    } else {
      // 透明なガラス: アイコンの色に tint（指定がなければ文字色）
      let foreground = tint ?? .label
      config.image = tint == nil ? image : image?.withTintColor(foreground, renderingMode: .alwaysOriginal)
      config.baseForegroundColor = foreground
      button = UIButton(configuration: config)
      button.tintColor = foreground
    }
    button.frame = CGRect(origin: .zero, size: frame.size)
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    button.accessibilityLabel = arguments["label"] as? String
    button.isEnabled = (arguments["enabled"] as? Bool) ?? true
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
