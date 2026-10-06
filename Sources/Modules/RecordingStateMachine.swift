import Foundation

/// 录屏会话状态。
/// 流转：idle → selecting → armed → recording ⇄ paused → stopped →（cancel）→ idle。
public enum RecordingState: Equatable {
    case idle       // 空闲
    case selecting  // 选区中（覆盖层已显示）
    case armed      // 已框选待录（红框 + 控制条已显示，等待开始）
    case recording  // 录制中
    case paused     // 已暂停
    case stopped    // 已停止（预览窗展示中）
}

/// 状态机事件（事件式 API）。
public enum RecordingEvent: Equatable {
    case beginSelection   // 呼出选区
    case regionConfirmed  // 选区确认（拖拽完成/点选窗口/整屏）
    case cancelSelection  // 放弃当前选区（selecting/armed → idle）
    case start            // 开始录制（armed → recording）
    case pause            // 暂停（recording → paused）
    case resume           // 恢复（paused → recording）
    case stop             // 停止并进入预览（recording/paused → stopped）
    case cancel           // 整体取消/丢弃（活动态与 stopped → idle）
}

/// 录屏状态机：纯逻辑，非法迁移拒绝（返回 false 且状态不变）。
public final class RecordingStateMachine {

    public private(set) var state: RecordingState = .idle

    public init() {}

    /// 处理事件。返回是否接受（非法迁移返回 false，状态保持不变）。
    @discardableResult
    public func handle(_ event: RecordingEvent) -> Bool {
        let next: RecordingState?
        switch (state, event) {
        // 合法迁移
        case (.idle, .beginSelection):        next = .selecting
        case (.selecting, .regionConfirmed):  next = .armed
        case (.selecting, .cancelSelection):  next = .idle
        case (.armed, .start):                next = .recording
        case (.armed, .cancelSelection):      next = .idle
        case (.recording, .pause):            next = .paused
        case (.paused, .resume):              next = .recording
        case (.recording, .stop):             next = .stopped
        case (.paused, .stop):                next = .stopped
        case (.selecting, .cancel),
             (.armed, .cancel),
             (.recording, .cancel),
             (.paused, .cancel),
             (.stopped, .cancel):             next = .idle
        // 其余全部拒绝
        default:                              next = nil
        }
        guard let next = next else { return false }
        state = next
        return true
    }

    /// 当前状态是否接受 cancel 事件（模块判 ESC 是否消费用）。
    public static func acceptsCancel(_ state: RecordingState) -> Bool {
        switch state {
        case .idle: return false
        case .selecting, .armed, .recording, .paused, .stopped: return true
        }
    }
}

/// F4 按键语义表：呼出 / 取消选区 / 停止。stopped（预览展示期）不干预。
public enum RecordingKeyAction: Equatable {
    case beginSelection
    case cancelSelection
    case stop

    public static func action(for state: RecordingState) -> RecordingKeyAction? {
        switch state {
        case .idle:       return .beginSelection
        case .selecting:  return .cancelSelection
        case .armed:      return .cancelSelection
        case .recording:  return .stop
        case .paused:     return .stop
        case .stopped:    return nil
        }
    }
}
