import XCTest

/// TDD: 录屏状态机 - 全迁移矩阵 + 非法迁移拒绝。
/// 流转：idle → selecting → armed → recording ⇄ paused → stopped →（cancel）→ idle。
final class RecordingStateMachineTests: XCTestCase {

    // MARK: - 合法迁移矩阵

    func test_idle_beginSelection_goesSelecting() {
        let sm = RecordingStateMachine()
        XCTAssertTrue(sm.handle(.beginSelection))
        XCTAssertEqual(sm.state, .selecting)
    }

    func test_selecting_regionConfirmed_goesArmed() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        XCTAssertTrue(sm.handle(.regionConfirmed))
        XCTAssertEqual(sm.state, .armed)
    }

    func test_selecting_cancelSelection_backsIdle() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        XCTAssertTrue(sm.handle(.cancelSelection))
        XCTAssertEqual(sm.state, .idle)
    }

    func test_armed_start_goesRecording() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        XCTAssertTrue(sm.handle(.start))
        XCTAssertEqual(sm.state, .recording)
    }

    func test_armed_cancelSelection_backsIdle() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        XCTAssertTrue(sm.handle(.cancelSelection))
        XCTAssertEqual(sm.state, .idle)
    }

    func test_recording_pause_resume_roundTrip() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        sm.handle(.start)
        XCTAssertTrue(sm.handle(.pause))
        XCTAssertEqual(sm.state, .paused)
        XCTAssertTrue(sm.handle(.resume))
        XCTAssertEqual(sm.state, .recording)
    }

    func test_recording_stop_goesStopped() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        sm.handle(.start)
        XCTAssertTrue(sm.handle(.stop))
        XCTAssertEqual(sm.state, .stopped)
    }

    func test_paused_stop_goesStopped() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        sm.handle(.start)
        sm.handle(.pause)
        XCTAssertTrue(sm.handle(.stop))
        XCTAssertEqual(sm.state, .stopped)
    }

    func test_stopped_cancel_backsIdle() {
        let sm = RecordingStateMachine()
        sm.handle(.beginSelection)
        sm.handle(.regionConfirmed)
        sm.handle(.start)
        sm.handle(.stop)
        XCTAssertTrue(sm.handle(.cancel))
        XCTAssertEqual(sm.state, .idle)
    }

    func test_cancel_fromEveryActiveState_backsIdle() {
        // selecting / armed / recording / paused 四个活动态 cancel 均回 idle
        let paths: [[RecordingEvent]] = [
            [.beginSelection],
            [.beginSelection, .regionConfirmed],
            [.beginSelection, .regionConfirmed, .start],
            [.beginSelection, .regionConfirmed, .start, .pause],
        ]
        for path in paths {
            let sm = RecordingStateMachine()
            for event in path { _ = sm.handle(event) }
            XCTAssertTrue(sm.handle(.cancel), "路径 \(path) 后应可 cancel")
            XCTAssertEqual(sm.state, .idle, "路径 \(path) 后 cancel 应回 idle")
        }
    }

    // MARK: - 非法迁移拒绝

    func test_illegalTransitions_rejectedAndStateKept() {
        // (迁移序列, 非法事件, 期望保持的状态)
        let cases: [(path: [RecordingEvent], illegal: RecordingEvent, expected: RecordingState)] = [
            ([], .regionConfirmed, .idle),                          // idle 不能直接确认选区
            ([], .start, .idle),                                    // idle 不能直接开始
            ([], .pause, .idle),
            ([], .stop, .idle),
            ([.beginSelection], .start, .selecting),                // 选区中不能直接开始
            ([.beginSelection], .pause, .selecting),
            ([.beginSelection, .regionConfirmed], .pause, .armed),  // 待录不能暂停
            ([.beginSelection, .regionConfirmed], .regionConfirmed, .armed),
            ([.beginSelection, .regionConfirmed, .start], .start, .recording),   // 重复 start
            ([.beginSelection, .regionConfirmed, .start], .beginSelection, .recording),
            ([.beginSelection, .regionConfirmed, .start, .pause], .pause, .paused), // 重复 pause
            ([.beginSelection, .regionConfirmed, .start, .pause, .resume], .resume, .recording), // 重复 resume
            ([.beginSelection, .regionConfirmed, .start, .stop], .pause, .stopped), // stopped 终态
            ([.beginSelection, .regionConfirmed, .start, .stop], .stop, .stopped),
        ]
        for testCase in cases {
            let sm = RecordingStateMachine()
            for event in testCase.path { _ = sm.handle(event) }
            let before = sm.state
            XCTAssertFalse(sm.handle(testCase.illegal),
                           "路径 \(testCase.path) 下事件 \(testCase.illegal) 应被拒绝")
            XCTAssertEqual(sm.state, before, "非法事件 \(testCase.illegal) 后状态不得变化")
        }
    }

    func test_resume_onlyValidFromPaused() {
        let sm = RecordingStateMachine()
        XCTAssertFalse(sm.handle(.resume), "idle 不能 resume")
        sm.handle(.beginSelection)
        XCTAssertFalse(sm.handle(.resume), "selecting 不能 resume")
    }

    // MARK: - F4 按键表（perform 幂等分支的纯函数映射）

    func test_f4Action_keyTable() {
        XCTAssertEqual(RecordingKeyAction.action(for: .idle), .beginSelection)
        XCTAssertEqual(RecordingKeyAction.action(for: .selecting), .cancelSelection)
        XCTAssertEqual(RecordingKeyAction.action(for: .armed), .cancelSelection)
        XCTAssertEqual(RecordingKeyAction.action(for: .recording), .stop)
        XCTAssertEqual(RecordingKeyAction.action(for: .paused), .stop)
        XCTAssertNil(RecordingKeyAction.action(for: .stopped), "预览展示期 F4 不干预")
    }

    func test_acceptsCancel_onlyActiveStates() {
        XCTAssertTrue(RecordingStateMachine.acceptsCancel(.selecting))
        XCTAssertTrue(RecordingStateMachine.acceptsCancel(.armed))
        XCTAssertTrue(RecordingStateMachine.acceptsCancel(.recording))
        XCTAssertTrue(RecordingStateMachine.acceptsCancel(.paused))
        XCTAssertTrue(RecordingStateMachine.acceptsCancel(.stopped))
        XCTAssertFalse(RecordingStateMachine.acceptsCancel(.idle))
    }
}
