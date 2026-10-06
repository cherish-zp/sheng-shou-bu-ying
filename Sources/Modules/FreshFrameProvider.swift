import CoreGraphics

/// 新鲜屏幕帧捕获 + 选区裁剪组件：延时截图与「重复上次区域」共用。
/// 捕获闭包可注入（默认 CGDisplayCreateImage），裁剪为纯函数（y 翻转 + Retina 缩放），可单测。
public final class FreshFrameProvider {

    /// 捕获指定显示器整屏画面（像素图）。注入点：测试传已知图，运行时用 CGDisplayCreateImage。
    public var capture: (CGDirectDisplayID) -> CGImage?

    public init(capture: @escaping (CGDirectDisplayID) -> CGImage? = { CGDisplayCreateImage($0) }) {
        self.capture = capture
    }

    /// 捕获 displayID 屏整屏新鲜帧，并按视图点坐标选区裁剪。
    /// - Parameters:
    ///   - selection: 选区 rect（覆盖层视图坐标，屏幕本地、左下原点）。
    ///   - displayID: 选区所在显示器 ID。
    ///   - screenPointSize: 该屏视图尺寸（覆盖层 bounds，点）。
    /// - Returns: 选区内容像素图；捕获失败返回 nil。
    public func captureCropped(selection: CGRect, displayID: CGDirectDisplayID,
                               screenPointSize: CGSize) -> CGImage? {
        guard let full = capture(displayID) else { return nil }
        return cropped(selection: selection, fullFrame: full, screenPointSize: screenPointSize)
    }

    /// 对已有整屏帧按视图点坐标选区裁剪（纯函数）。
    /// 坐标换算与既有渲染管线一致：SelectionRect.cropRectPixels 负责翻转 y 轴与 Retina 缩放。
    public func cropped(selection: CGRect, fullFrame: CGImage, screenPointSize: CGSize) -> CGImage? {
        let cropRect = SelectionRect.cropRectPixels(
            selection: selection,
            imageSize: CGSize(width: fullFrame.width, height: fullFrame.height),
            viewSize: screenPointSize
        )
        return fullFrame.cropping(to: cropRect)
    }
}
