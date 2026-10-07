import Foundation
import AppKit

/// 条目副标题纯逻辑（第二棒 UI ②）：
/// 1) 相对时间：刚刚 / N 分钟前 / HH:mm（时钟注入可测）；
/// 2) 文件大小：B/KB/MB/GB，1 位小数去尾零。
public enum TransferItemRelativeTime {

    /// 相对时间文案：<1 分钟「刚刚」，<1 小时「N 分钟前」，更早回退 HH:mm 本地时间。
    /// 时钟回拨/边界误差（now < date）按「刚刚」处理，不产生负数分钟。
    public static func string(from date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 60 else { return "刚刚" }
        let minutes = Int(elapsed / 60)
        guard minutes < 60 else { return clockString(from: date) }
        return "\(minutes) 分钟前"
    }

    private static func clockString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

public enum TransferItemFileSize {

    /// 人类可读文件大小：B/KB/MB/GB，1 位小数并去尾零（1024 → "1 KB"、1536 → "1.5 KB"）。
    public static func string(bytes: Int64) -> String {
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024
        let value = Double(bytes)
        switch value {
        case ..<kb:
            return "\(bytes) B"
        case ..<mb:
            return formatted(value / kb, unit: "KB")
        case ..<gb:
            return formatted(value / mb, unit: "MB")
        default:
            return formatted(value / gb, unit: "GB")
        }
    }

    /// 1 位小数四舍五入后去尾零（"1.0" → "1"）；边界值进位（1023.999 KB → "1024 KB"）。
    private static func formatted(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) \(unit)"
        }
        return String(format: "%.1f \(unit)", rounded)
    }
}

/// Quick Look 数据源纯逻辑（第二棒功能 1）：
/// QL 序列只含 file 条目（text/image/link 没有可预览文件），起始索引按 hover 定位。
public enum TransferShelfQuickLookIndex {

    /// 文件条目的可预览 URL 序列（保持暂存顺序）。
    public static func previewURLs(for items: [TransferItem]) -> [URL] {
        items.filter { $0.kind == .file }.map(\.url)
    }

    /// hover 条目在 QL 序列中的起始索引；hover 非 file 条目或无 hover 时返回 nil
    /// （调用方据此不打开 QL）。
    public static func startIndex(for items: [TransferItem], hovered: UUID?) -> Int? {
        guard let hovered = hovered else { return nil }
        guard let item = items.first(where: { $0.id == hovered }), item.kind == .file else { return nil }
        let fileItems = items.filter { $0.kind == .file }
        return fileItems.firstIndex(where: { $0.id == item.id })
    }
}

/// F2 手动呼出位置记忆（第二棒功能 3）：UserDefaults 注入可测 + 越界 clamp。
public enum TransferShelfManualPosition {

    private static let originXKey = "transferShelf.manualPosition.x"
    private static let originYKey = "transferShelf.manualPosition.y"

    /// 上次手动呼出的面板左上原点；无记录返回 nil。
    public static func savedOrigin(in defaults: UserDefaults) -> NSPoint? {
        guard defaults.object(forKey: originXKey) != nil,
              defaults.object(forKey: originYKey) != nil else { return nil }
        return NSPoint(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey)
        )
    }

    /// 记录手动呼出位置（仅手动路径调用，拖拽呼出维持顶部热区逻辑）。
    public static func save(origin: NSPoint, in defaults: UserDefaults) {
        defaults.set(Double(origin.x), forKey: originXKey)
        defaults.set(Double(origin.y), forKey: originYKey)
    }

    /// 把记忆的 origin clamp 回目标屏可见区内（分辨率变化/拔屏兜底）。
    /// 面板比可见区还大时收敛到可见区原点（max/min 混合兜底）。
    public static func clampedOrigin(_ origin: NSPoint, visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }
}
