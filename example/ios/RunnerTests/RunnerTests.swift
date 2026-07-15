import Flutter
import XCTest

final class RunnerTests: XCTestCase {
  func testFlutterFrameworkIsAvailable() {
    XCTAssertNotNil(FlutterEngine.self)
  }
}
