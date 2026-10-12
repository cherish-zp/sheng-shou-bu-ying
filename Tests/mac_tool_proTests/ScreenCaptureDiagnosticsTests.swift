import XCTest

/// TDD: 截图亮度带诊断默认关闭——它对每块屏做一次全图解码（5K 屏 ~59MB 临时分配 +
/// 主线程数十 ms），只应在排查 HDR"截图变暗"类问题时开启。
final class ScreenCaptureDiagnosticsTests: XCTestCase {

    func test_defaultOff() {
        let defaults = UserDefaults(suiteName: "ScreenCaptureDiagnosticsTests-default")!
        defaults.removeObject(forKey: ScreenCaptureService.luminanceDiagnosticsKey)
        XCTAssertFalse(ScreenCaptureService.luminanceDiagnosticsEnabled(defaults: defaults))
    }

    func test_explicitEnable() {
        let defaults = UserDefaults(suiteName: "ScreenCaptureDiagnosticsTests-on")!
        defaults.set(true, forKey: ScreenCaptureService.luminanceDiagnosticsKey)
        defer { defaults.removeObject(forKey: ScreenCaptureService.luminanceDiagnosticsKey) }
        XCTAssertTrue(ScreenCaptureService.luminanceDiagnosticsEnabled(defaults: defaults))
    }
}
