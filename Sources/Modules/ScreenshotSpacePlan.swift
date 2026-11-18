import Foundation

/// ⌥A 截图「按了没反应」的 Space 合成竞态规格（纯逻辑，TDD）。
/// 背景（2026-11-18 diag.log 实证）：11 次取消集中在三个密集重试段，
/// 每次按下后 2-3 秒内即 ESC——overlay 窗口创建成功（日志齐全）但用户看不见。
/// 根因：setActivationPolicy(.accessory) 异步生效，overlay 紧接着 orderFront
/// 时 policy 未被 WindowServer 接受，窗口按 .regular 应用的 fullScreenAuxiliary
/// 处理，在其他应用的全屏 Space 上不合成。App 层按本规格执行两道防线：
/// ①显示前轮询确认 policy 生效（再创建/orderFront overlay）；
/// ②显示后 occlusionState 自检，不可见时逐级自愈并落日志。
public enum ScreenshotSpacePlan {

    /// policy 生效确认轮询：最多 20 次 × 10ms = 200ms（呼出必须跟手）。
    public static let policyWaitMaxAttempts = 20
    public static let policyWaitInterval: TimeInterval = 0.01

    /// overlay 显示后可见性自检延迟（给合成器留时间，又不拖慢用户）。
    public static let visibilityCheckDelay: TimeInterval = 0.6

    /// 可见性自检的处置动作（defense-in-depth：轻修复 → 重修复 → 显式退出）。
    public enum VisibilityAction: Equatable {
        case keep                   // 可见，不干预
        case reorderFront           // 首次不可见：重新 orderFront
        case rebuildMoveActiveSpace // 仍不可见：放弃 canJoinAllSpaces，跟随当前 Space 重建
        case cancelWithNotice       // 修复无效：结束会话并提示（用户得到明确反馈而非无响应）
    }

    /// 可见性自检决策：attempt 为本轮会话内自检轮次（0 起）。
    public static func visibilityAction(isVisible: Bool, attempt: Int) -> VisibilityAction {
        if isVisible { return .keep }
        switch attempt {
        case 0: return .reorderFront
        case 1: return .rebuildMoveActiveSpace
        default: return .cancelWithNotice
        }
    }

    /// 自愈失败时的用户提示（说明发生了什么 + 怎么办）。
    public static let invisibleNotice = "截图覆盖层未能显示（Space 合成受限），请再按 ⌥A 重试"
}
