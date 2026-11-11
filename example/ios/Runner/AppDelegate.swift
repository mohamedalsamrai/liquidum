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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeGlass") {
      NativeGlassFactory.register(with: registrar)
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

/// Apple's glass (`UIGlassEffect`) in shapes laid out from Flutter, for
/// comparison with Liquidum's `Glass` over the same content.
final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(NativeGlassFactory(), withId: "liquidum/native_glass")
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    NativeGlass(frame: frame, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Each shape: `x`, `y`, `width`, `height` (points, in the view), `radius`
/// (a capsule when absent), `style` ("regular" or "clear"), `tint` (ARGB),
/// `interactive`, `group`: shapes with the same group are in one
/// `UIGlassContainerEffect`, whose spacing is its first shape's `spacing`,
/// and `appear`: the shape's glass materializes `appearAt` seconds after the
/// view is made and dematerializes at `leaveAt`, in half-second animations.
/// Shapes with a `button` are glass buttons (see `button(_:_:)`).
/// `speed`: the view's layer speed.
final class NativeGlass: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, arguments: [String: Any]) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    super.init()
    guard #available(iOS 26.0, *) else { return }
    container.layer.speed = Float(arguments["speed"] as? Double ?? 1)
    if arguments["dark"] as? Bool == true {
      container.overrideUserInterfaceStyle = .dark
    }
    var containers: [Int: UIView] = [:]
    var appearing: [(UIVisualEffectView, UIVisualEffect)] = []
    for shape in arguments["shapes"] as? [[String: Any]] ?? [] {
      if let label = shape["button"] as? String {
        container.addSubview(Self.button(label, shape))
        continue
      }
      if let kind = shape["control"] as? String {
        container.addSubview(Self.control(kind, shape))
        continue
      }
      let effect = UIGlassEffect(style: shape["style"] as? String == "clear" ? .clear : .regular)
      if let argb = shape["tint"] as? Int {
        effect.tintColor = UIColor(
          red: CGFloat(argb >> 16 & 0xff) / 255, green: CGFloat(argb >> 8 & 0xff) / 255,
          blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24 & 0xff) / 255)
      }
      effect.isInteractive = shape["interactive"] as? Bool ?? false
      let view = UIVisualEffectView(effect: effect)
      func d(_ key: String) -> CGFloat { CGFloat(shape[key] as? Double ?? 0) }
      view.frame = CGRect(x: d("x"), y: d("y"), width: d("width"), height: d("height"))
      if let radius = shape["radius"] as? Double {
        view.cornerConfiguration = .corners(radius: .fixed(radius))
      } else {
        view.cornerConfiguration = .capsule()
      }
      if shape["appear"] as? Bool == true {
        appearing.append((view, effect))
        view.effect = nil
      }
      if let group = shape["group"] as? Int {
        if containers[group] == nil {
          let effect = UIGlassContainerEffect()
          effect.spacing = CGFloat(shape["spacing"] as? Double ?? 0)
          let groupView = UIVisualEffectView(effect: effect)
          groupView.frame = container.bounds
          groupView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          container.addSubview(groupView)
          containers[group] = groupView.contentView
        }
        containers[group]?.addSubview(view)
      } else {
        container.addSubview(view)
      }
    }
    for (key, glass) in [("appearAt", true), ("leaveAt", false)] {
      guard let t = arguments[key] as? Double else { continue }
      DispatchQueue.main.asyncAfter(deadline: .now() + t) {
        UIView.animate(withDuration: 0.5) {
          for (view, effect) in appearing { view.effect = glass ? effect : nil }
        }
      }
    }
  }

  /// A glass button (`UIButton.Configuration.glass()` and kin) at the
  /// shape's `x`, `y`, its own size: `button` (its title, none if empty),
  /// `icon` (a plus), `prominent`, `style`, `tint`, `size` (mini, small,
  /// medium, large), `enabled`.
  @available(iOS 26.0, *)
  private static func button(_ label: String, _ shape: [String: Any]) -> UIButton {
    let clear = shape["style"] as? String == "clear"
    let prominent = shape["prominent"] as? Bool ?? false
    var config: UIButton.Configuration =
      clear
      ? (prominent ? .prominentClearGlass() : .clearGlass())
      : (prominent ? .prominentGlass() : .glass())
    if !label.isEmpty { config.title = label }
    if shape["icon"] as? Bool == true {
      config.image = UIImage(systemName: "plus")
      config.imagePadding = 6
    }
    switch shape["size"] as? String {
    case "mini": config.buttonSize = .mini
    case "small": config.buttonSize = .small
    case "large": config.buttonSize = .large
    default: config.buttonSize = .medium
    }
    let button = UIButton(configuration: config)
    if let argb = shape["tint"] as? Int {
      button.tintColor = UIColor(
        red: CGFloat(argb >> 16 & 0xff) / 255, green: CGFloat(argb >> 8 & 0xff) / 255,
        blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24 & 0xff) / 255)
    }
    button.isEnabled = shape["enabled"] as? Bool ?? true
    button.sizeToFit()
    button.frame.origin = CGPoint(
      x: CGFloat(shape["x"] as? Double ?? 0), y: CGFloat(shape["y"] as? Double ?? 0))
    return button
  }

  /// A lens control at the shape's `x`, `y`: `control` = "switch" (its own
  /// size; `on`, `tint` = onTintColor, `thumbColor`), "slider" (`width`
  /// wide, 34 tall; `value`, `tint` = minimumTrackTintColor, `thumbColor`)
  /// or "segmented" (`width` wide; `items`, `selected`, `tint` =
  /// selectedSegmentTintColor); `enabled`.
  private static func control(_ kind: String, _ shape: [String: Any]) -> UIView {
    func color(_ key: String) -> UIColor? {
      guard let argb = shape[key] as? Int else { return nil }
      return UIColor(
        red: CGFloat(argb >> 16 & 0xff) / 255, green: CGFloat(argb >> 8 & 0xff) / 255,
        blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24 & 0xff) / 255)
    }
    func d(_ key: String) -> CGFloat { CGFloat(shape[key] as? Double ?? 0) }
    let control: UIControl
    switch kind {
    case "switch":
      let s = UISwitch()
      s.isOn = shape["on"] as? Bool ?? false
      s.onTintColor = color("tint")
      s.thumbTintColor = color("thumbColor")
      control = s
    case "slider":
      let s = UISlider()
      s.value = Float(shape["value"] as? Double ?? 0)
      s.minimumTrackTintColor = color("tint")
      s.thumbTintColor = color("thumbColor")
      control = s
    default:
      let s = UISegmentedControl(items: shape["items"] as? [String] ?? [])
      s.selectedSegmentIndex = shape["selected"] as? Int ?? 0
      s.selectedSegmentTintColor = color("tint")
      control = s
    }
    control.isEnabled = shape["enabled"] as? Bool ?? true
    control.sizeToFit()
    var frame = control.frame
    frame.origin = CGPoint(x: d("x"), y: d("y"))
    if kind != "switch" { frame.size.width = d("width") }
    control.frame = frame
    return control
  }

  func view() -> UIView { container }
}
