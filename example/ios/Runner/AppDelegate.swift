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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTabBar") {
      NativeTabBarFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SymbolRenderer") {
      SymbolRenderer.register(with: registrar)
    }
  }
}

/// Draws SF Symbols with UIKit, white on transparent, so Flutter can show the
/// same glyphs as native controls and tint them itself.
enum SymbolRenderer {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "liquidum/sf_symbols", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "render", let args = call.arguments as? [String: Any],
        let name = args["name"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(render(name, args))
    }
  }

  private static func render(_ name: String, _ args: [String: Any]) -> Any? {
    let weights: [String: UIImage.SymbolWeight] = [
      "regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold,
    ]
    let scales: [String: UIImage.SymbolScale] = ["small": .small, "medium": .medium, "large": .large]
    let config = UIImage.SymbolConfiguration(
      pointSize: args["pointSize"] as? Double ?? 17,
      weight: weights[args["weight"] as? String ?? "regular"] ?? .regular,
      scale: scales[args["scale"] as? String ?? "medium"] ?? .medium)
    guard let symbol = UIImage(systemName: name, withConfiguration: config) else {
      return nil
    }
    // An image view sizes itself to the symbol's full drawing bounds, as the
    // tab bar's own item image views do.
    let view = UIImageView(image: symbol.withTintColor(.white, renderingMode: .alwaysOriginal))
    view.sizeToFit()
    let format = UIGraphicsImageRendererFormat()
    format.scale = args["scale_factor"] as? Double ?? UIScreen.main.scale
    let png = UIGraphicsImageRenderer(bounds: view.bounds, format: format).pngData { context in
      view.layer.render(in: context.cgContext)
    }
    // UIKit lays symbols out by their alignment rect, which sits inside the
    // drawing bounds by these insets.
    let insets = symbol.alignmentRectInsets
    return [
      "png": FlutterStandardTypedData(bytes: png),
      "width": view.bounds.width,
      "height": view.bounds.height,
      "insets": [insets.left, insets.top, insets.right, insets.bottom],
    ]
  }
}

/// Apple's own tab bar, embedded as a platform view so the example can compare
/// it with Liquidum's over the same content.
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativeTabBarFactory(registrar: registrar), withId: "liquidum/native_tab_bar")
  }

  private let registrar: FlutterPluginRegistrar

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBar(
      frame: frame, viewId: viewId, arguments: args as? [String: Any] ?? [:],
      registrar: registrar)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// A `UITabBarController` with clear pages: only its floating glass bar shows,
/// over whatever Flutter paints behind the platform view.
final class NativeTabBar: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private let controller = UITabBarController()
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect, viewId: Int64, arguments: [String: Any],
    registrar: FlutterPluginRegistrar
  ) {
    channel = FlutterMethodChannel(
      name: "liquidum/native_tab_bar/\(viewId)", binaryMessenger: registrar.messenger())
    super.init()

    let items = arguments["items"] as? [[String: String]] ?? []
    controller.viewControllers = items.enumerated().map { index, item in
      let page = UIViewController()
      page.view.backgroundColor = .clear
      page.tabBarItem = UITabBarItem(
        title: item["label"], image: UIImage(systemName: item["symbol"] ?? ""), tag: index)
      return page
    }
    // Optional colors and badges, to compare customized bars.
    func color(_ key: String) -> UIColor? {
      guard let argb = arguments[key] as? Int else { return nil }
      return UIColor(
        red: CGFloat(argb >> 16 & 0xff) / 255, green: CGFloat(argb >> 8 & 0xff) / 255,
        blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24 & 0xff) / 255)
    }
    if let tint = color("tint") {
      controller.tabBar.tintColor = tint
    }
    if let tint = color("unselectedTint") {
      controller.tabBar.unselectedItemTintColor = tint
    }
    for (index, badge) in (arguments["badges"] as? [String] ?? []).enumerated()
    where !badge.isEmpty && index < controller.viewControllers?.count ?? 0 {
      controller.viewControllers?[index].tabBarItem.badgeValue = badge
    }
    controller.selectedIndex = arguments["selected"] as? Int ?? 0
    controller.delegate = self
    controller.view.backgroundColor = .clear
    controller.view.frame = frame

    if let parent = registrar.viewController {
      parent.addChild(controller)
      controller.didMove(toParent: parent)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "select", let index = call.arguments as? Int {
        self?.controller.selectedIndex = index
      }
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    controller.willMove(toParent: nil)
    controller.removeFromParent()
  }

  func view() -> UIView {
    controller.view
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    channel.invokeMethod("selected", arguments: tabBarController.selectedIndex)
  }
}
