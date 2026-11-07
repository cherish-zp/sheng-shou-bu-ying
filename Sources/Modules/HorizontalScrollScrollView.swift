import AppKit

/// 横向卡片流共享滚动视图：纵向滚轮（|deltaY| > |deltaX|）转为横向浏览，
/// 横向滚动照常透传 super。scroll(to:) 自带 documentView 边界夹持，滚到头自然停；
/// 惯性沿用合成滚轮的 momentum 事件，不做额外动量。
/// 剪贴板面板与文件中转站共用（一处实现，两处复用）。
public final class HorizontalScrollScrollView: NSScrollView {
    override public func scrollWheel(with event: NSEvent) {
        // contentView 为非可选；无内容文档时透传 super 即可
        guard abs(event.deltaY) > abs(event.deltaX), documentView != nil else {
            super.scrollWheel(with: event)
            return
        }
        // 向下滑 = 向右看内容：origin.x += deltaY（macOS delta 符号惯例，真机验证手感）
        let clip = contentView
        let origin = clip.bounds.origin
        clip.scroll(to: NSPoint(x: origin.x + event.deltaY, y: origin.y))
        reflectScrolledClipView(clip)
    }
}
