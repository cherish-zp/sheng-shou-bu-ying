import XCTest

/// TDD: GIF 录制导出规格——帧调度、命名（时区注入）、用户反馈文案。
/// 此前 GIF「功能无效」的根因是全程零反馈（开始/停止/保存无任何提示），
/// 且 0.5s 帧距导致成卡顿 PPT；本规格统一调度与反馈契约。
final class GIFExportPlanTests: XCTestCase {

    // MARK: - 帧调度

    /// 截帧间隔 0.25s（4fps）：比旧 0.5s 顺滑一倍，GIF delay 与截帧间隔一致才不卡。
    func test_captureInterval_matchesGIFDelay() {
        XCTAssertEqual(GIFExportPlan.captureInterval, 0.25, accuracy: 0.001)
        XCTAssertEqual(GIFExportPlan.gifDelayTime, GIFExportPlan.captureInterval,
                       "GIF 帧延迟必须等于截帧间隔，否则回放变速卡顿")
    }

    /// 上限 60 秒：maxFrames = 60 / 0.25 = 240。
    func test_maxFrames_matchesDuration() {
        XCTAssertEqual(GIFExportPlan.maxFrames, 240)
        XCTAssertEqual(Double(GIFExportPlan.maxFrames) * GIFExportPlan.captureInterval,
                       GIFExportPlan.maxDuration, accuracy: 0.001)
    }

    /// 半分辨率缩放（控制体积），奇数像素向上取整。
    func test_scaledSize() {
        let size = GIFExportPlan.scaledSize(pixelWidth: 3457, pixelHeight: 2233, scale: 0.5)
        XCTAssertEqual(size.width, 1729, accuracy: 0.5)
        XCTAssertEqual(size.height, 1117, accuracy: 0.5)
    }

    // MARK: - 命名（时区注入——文件名类测试显式时区，勿依赖宿主时区）

    func test_fileName_formatAndPrefix() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 7
        components.hour = 12; components.minute = 34; components.second = 56
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let date = calendar.date(from: components)!
        let name = GIFExportPlan.fileName(date: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(name, "GIF 2026-11-07 12.34.56.gif", "命名与录屏同构：GIF yyyy-MM-dd HH.mm.ss.gif")
    }

    // MARK: - 用户反馈文案（「功能无效」体感的根治：全程有反馈）

    func test_startToast() {
        XCTAssertEqual(GIFExportPlan.startToast, "开始录制 GIF · ⌥G 停止")
    }

    func test_saveToast_success() {
        let toast = GIFExportPlan.saveToast(frames: 12, duration: 3.0, success: true,
                                            fileName: "GIF 2026-11-07 12.34.56.gif")
        XCTAssertTrue(toast.contains("已保存"), "成功提示必须明确：\(toast)")
        XCTAssertTrue(toast.contains("12 帧"))
        XCTAssertTrue(toast.contains("3 秒"))
    }

    func test_saveToast_noFramesFailure() {
        let toast = GIFExportPlan.saveToast(frames: 0, duration: 2.0, success: false,
                                            fileName: "")
        XCTAssertTrue(toast.contains("失败"), "零帧/编码失败必须显式报错而非静默：\(toast)")
    }

    func test_saveToast_encodeFailure() {
        let toast = GIFExportPlan.saveToast(frames: 5, duration: 1.25, success: false,
                                            fileName: "")
        XCTAssertTrue(toast.contains("失败"))
    }
}
