import XCTest
import CoreGraphics

/// TDD: 滚动截图会话状态机 — ready/capturing/done + auto/manual 模式；
/// v2 契约：字节预算（budgetRejected）、终止原因 stopReason、到底判定 isAtBottom。
final class ScrollCaptureSessionTests: XCTestCase {

    // MARK: - 初始状态

    func test_initialState_isReady() {
        let session = ScrollCaptureSession(maxFrames: 30)
        XCTAssertEqual(session.state, .ready)
        XCTAssertNil(session.mode)
        XCTAssertEqual(session.count, 0)
        XCTAssertEqual(session.stopReason, .none)
        XCTAssertEqual(session.bufferBytes, 0)
        XCTAssertFalse(session.isAtBottom)
    }

    // MARK: - 模式启动

    func test_startAuto_setsCapturingAndAutoMode() {
        var session = ScrollCaptureSession(maxFrames: 30)
        session.startAuto()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertEqual(session.mode, .auto)
    }

    func test_startManual_setsCapturingAndManualMode() {
        var session = ScrollCaptureSession(maxFrames: 30)
        session.startManual()
        XCTAssertEqual(session.state, .capturing)
        XCTAssertEqual(session.mode, .manual)
    }

    func test_startAuto_whenAlreadyCapturing_doesNothing() {
        var session = ScrollCaptureSession(maxFrames: 30)
        session.startManual()
        session.startAuto()
        XCTAssertEqual(session.mode, .manual)
    }

    // MARK: - 截帧（FrameAddResult 契约）

    func test_tryAdd_inReadyState_returnsUnchanged() {
        // 非 capturing 状态不添加帧（返回 .unchanged，无 "invalid" 枚举项）
        var session = ScrollCaptureSession(maxFrames: 30)
        XCTAssertEqual(session.tryAdd(makeImage(red: 1.0)), .unchanged)
        XCTAssertEqual(session.count, 0)
    }

    func test_tryAdd_firstFrameInCapturing_alwaysAdded() {
        var session = ScrollCaptureSession(maxFrames: 5)
        session.startManual()
        XCTAssertEqual(session.tryAdd(makeImage(red: 1.0)), .added)
        XCTAssertEqual(session.count, 1)
    }

    func test_tryAdd_identicalFrameNotAdded() {
        var session = ScrollCaptureSession(maxFrames: 5)
        session.startManual()
        let frame = makeImage(red: 0.33)
        session.tryAdd(frame)
        XCTAssertEqual(session.tryAdd(frame), .unchanged)
        XCTAssertEqual(session.count, 1)
    }

    func test_tryAdd_changedFrameAdded() {
        var session = ScrollCaptureSession(maxFrames: 5)
        session.startManual()
        session.tryAdd(makeImage(red: 1.0))
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.66)), .added)
        XCTAssertEqual(session.count, 2)
    }

    func test_tryAdd_maxFramesSetsDone() {
        // 既有语义保留：显式 maxFrames 上限触顶 → done
        var session = ScrollCaptureSession(maxFrames: 3)
        session.startAuto()
        session.tryAdd(makeImage(red: 1.0))
        session.tryAdd(makeImage(red: 0.66))
        session.tryAdd(makeImage(red: 0.33))
        XCTAssertEqual(session.count, 3)
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.15)), .unchanged)
    }

    func test_bufferBytes_累计已接收帧字节() {
        var session = ScrollCaptureSession()
        session.startManual()
        session.tryAdd(makeImage(red: 1.0, width: 40, height: 40))   // 6400B
        session.tryAdd(makeImage(red: 0.66, width: 40, height: 50))  // 8000B
        session.tryAdd(makeImage(red: 0.66, width: 40, height: 50))  // 与上一帧完全相同 → unchanged 不计
        XCTAssertEqual(session.bufferBytes, 6400 + 8000)
    }

    // MARK: - h. 字节预算

    func test_tryAdd_预算触顶_budgetRejected并终止() {
        // 40×40×4 = 6400B/帧；预算 16000B → 前两帧可加，第三帧拒绝
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 16_000,
                                                                              bottomStillFrames: 3))
        session.startManual()
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.1)), .added)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.4)), .added)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.7)), .budgetRejected)
        XCTAssertEqual(session.stopReason, .budgetReached)
        XCTAssertEqual(session.state, .done)
        XCTAssertTrue(session.isDone)
        XCTAssertEqual(session.bufferBytes, 12_800, "被拒绝的帧不计入缓冲")
    }

    func test_tryAdd_单帧超预算_直接拒绝() {
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 1000))
        session.startManual()
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.5, width: 40, height: 40)), .budgetRejected)
        XCTAssertEqual(session.count, 0)
        XCTAssertEqual(session.stopReason, .budgetReached)
    }

    // MARK: - h. 到底判定

    func test_tryAdd_auto模式连续3次unchanged_isAtBottom并自动终止() {
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 512 * 1024 * 1024,
                                                                              bottomStillFrames: 3))
        session.startAuto()
        session.tryAdd(makeImage(red: 0.1))
        session.tryAdd(makeImage(red: 0.4))
        session.tryAdd(makeImage(red: 0.7))
        session.tryAdd(makeImage(red: 0.9))       // 内容变化 → added，计数清零
        XCTAssertEqual(session.count, 4)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.9)), .unchanged)
        XCTAssertFalse(session.isAtBottom)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.9)), .unchanged)
        XCTAssertFalse(session.isAtBottom, "连续 2 次 < bottomStillFrames(3)")
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.9)), .unchanged)
        XCTAssertTrue(session.isAtBottom, "连续 3 次无新增 → 判到底")
        XCTAssertEqual(session.stopReason, .bottomReached)
        XCTAssertEqual(session.state, .done)
    }

    func test_tryAdd_auto模式内容更新后计数清零() {
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 512 * 1024 * 1024,
                                                                              bottomStillFrames: 3))
        session.startAuto()
        session.tryAdd(makeImage(red: 0.1))
        session.tryAdd(makeImage(red: 0.9))
        session.tryAdd(makeImage(red: 0.9))
        session.tryAdd(makeImage(red: 0.9))       // 2 次 unchanged
        session.tryAdd(makeImage(red: 0.2))       // added → 清零
        XCTAssertFalse(session.isAtBottom)
        session.tryAdd(makeImage(red: 0.2))
        session.tryAdd(makeImage(red: 0.2))
        XCTAssertFalse(session.isAtBottom, "清零后重新累计，仅 2 次")
    }

    func test_tryAdd_manual模式unchanged多次_isAtBottom恒false() {
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 512 * 1024 * 1024,
                                                                              bottomStillFrames: 3))
        session.startManual()
        session.tryAdd(makeImage(red: 0.1))
        for _ in 0..<5 {
            session.tryAdd(makeImage(red: 0.1))
        }
        XCTAssertFalse(session.isAtBottom, "manual 模式无自动到底语义")
        XCTAssertEqual(session.stopReason, .none)
        XCTAssertEqual(session.count, 1)
    }

    func test_tryAdd_bottomStillFrames配置生效() {
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 512 * 1024 * 1024,
                                                                              bottomStillFrames: 2))
        session.startAuto()
        session.tryAdd(makeImage(red: 0.1))
        session.tryAdd(makeImage(red: 0.9))
        session.tryAdd(makeImage(red: 0.9))
        XCTAssertFalse(session.isAtBottom, "首次 unchanged")
        session.tryAdd(makeImage(red: 0.9))
        XCTAssertTrue(session.isAtBottom)
    }

    // MARK: - h. 停止原因

    func test_stop_setsUserRequested() {
        var session = ScrollCaptureSession(maxFrames: 5)
        session.startManual()
        session.tryAdd(makeImage(red: 1.0))
        session.stop()
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(session.stopReason, .userRequested)
        XCTAssertEqual(session.tryAdd(makeImage(red: 0.5)), .unchanged)
    }

    func test_stop_whenReady_setsDoneAndUserRequested() {
        var session = ScrollCaptureSession(maxFrames: 5)
        session.stop()
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(session.stopReason, .userRequested)
    }

    func test_stop_已自动终止的会话保留原终止原因() {
        // 预算触顶后再调 stop() 不应覆盖 budgetReached（终止原因只记录首次）
        var session = ScrollCaptureSession(config: ScrollCaptureSessionConfig(maxBufferBytes: 1000))
        session.startManual()
        session.tryAdd(makeImage(red: 0.5))
        session.stop()
        XCTAssertEqual(session.stopReason, .budgetReached)
    }

    // MARK: - 坐标转换（既有语义保留）

    func test_displayCaptureRect_flipsY() {
        let viewRect = CGRect(x: 100, y: 200, width: 300, height: 400)
        let display = ScrollCaptureSession.displayCaptureRect(viewRect: viewRect, screenHeight: 1080)
        XCTAssertEqual(display.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(display.origin.y, 480, accuracy: 0.001)
        XCTAssertEqual(display.width, 300, accuracy: 0.001)
        XCTAssertEqual(display.height, 400, accuracy: 0.001)
    }

    func test_globalCaptureRect_singleDisplay() {
        let displayRect = CGRect(x: 100, y: 200, width: 300, height: 400)
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let global = ScrollCaptureSession.globalCaptureRect(displayRect: displayRect, displayBounds: displayBounds)
        XCTAssertEqual(global.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(global.origin.y, 200, accuracy: 0.001)
    }

    func test_globalCaptureRect_multiDisplay() {
        let displayRect = CGRect(x: 100, y: 200, width: 300, height: 400)
        let displayBounds = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let global = ScrollCaptureSession.globalCaptureRect(displayRect: displayRect, displayBounds: displayBounds)
        XCTAssertEqual(global.origin.x, -1820, accuracy: 0.001)
    }

    // MARK: - 自动滚动方向

    func test_autoScrollDelta_isNegative_forDownwardScroll() {
        // 长截图应向下滚动（内容上移、新内容出现在底部），
        // CGEvent wheel1 负值 = 向下滚动
        XCTAssertLessThan(ScrollCaptureSession.autoScrollDelta, 0,
                          "自动滚动 delta 应为负值（向下滚动）")
    }

    // MARK: - Helpers

    private func makeImage(red: CGFloat, width: Int = 40, height: Int = 40) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: red, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
