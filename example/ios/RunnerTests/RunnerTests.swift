import XCTest

/// Drives an installed app with a scripted gesture, so Liquidum's tab bar and
/// Apple's native one can be compared under exactly the same touches.
///
/// Configure it through xcodebuild's `TEST_RUNNER_` environment variables:
/// - `TEST_RUNNER_APP`: bundle identifier of the app to drive.
/// - `TEST_RUNNER_SCRIPT`: steps separated by `;`, in points from the top left:
///   `wait <s>`, `tap <x> <y>`, `press <x> <y> <s>`,
///   `drag <x0> <y0> <x1> <y1> <press s> <velocity pt/s> <hold s>`.
final class GestureScriptTests: XCTestCase {
  func testScript() throws {
    let environment = ProcessInfo.processInfo.environment
    let app = XCUIApplication(
      bundleIdentifier: environment["APP"] ?? "dev.liquidum.liquidumExample")
    app.launch()
    Thread.sleep(forTimeInterval: Double(environment["SETTLE"] ?? "") ?? 3)

    let origin = app.coordinate(withNormalizedOffset: .zero)
    func at(_ x: String, _ y: String) -> XCUICoordinate {
      origin.withOffset(CGVector(dx: Double(x)!, dy: Double(y)!))
    }

    for step in (environment["SCRIPT"] ?? "").split(separator: ";") {
      let p = step.split(separator: " ").map(String.init)
      switch p.first {
      case "wait":
        Thread.sleep(forTimeInterval: Double(p[1])!)
      case "tap":
        at(p[1], p[2]).tap()
      case "press":
        at(p[1], p[2]).press(forDuration: Double(p[3])!)
      case "drag":
        at(p[1], p[2]).press(
          forDuration: Double(p[5])!,
          thenDragTo: at(p[3], p[4]),
          withVelocity: XCUIGestureVelocity(rawValue: CGFloat(Double(p[6])!)),
          thenHoldForDuration: Double(p[7])!)
      default:
        XCTFail("Unknown step: \(step)")
      }
    }
    Thread.sleep(forTimeInterval: 1.5)
  }
}
