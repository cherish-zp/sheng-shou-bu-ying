import XCTest
import AppKit

/// TDD: 剪贴板图片条目必须能看到实际内容（缩略图），而不是只有「图片 W×H」文字。
/// 此前图片行高 34 且只渲染文本，用户看不到图片内容——回归网：缩略图生成 + 行高度量。
final class ClipboardThumbnailTests: XCTestCase {

    // MARK: - 测试素材

    /// 生成纯色 PNG（指定像素尺寸）。
    private func pngData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: - 缩略图生成

    func test_makeThumbnail_decodesAtNativePixelSize() throws {
        // 缩放职责在渲染层（卡片式按宽高比缩放）；make 只负责解码出原始像素尺寸
        let thumb = try XCTUnwrap(ClipboardThumbnail.make(fromPNG: pngData(width: 200, height: 100)))
        XCTAssertEqual(thumb.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(thumb.size.height, 100, accuracy: 0.5)
    }

    func test_makeThumbnail_smallImageNotUpscaled() throws {
        let thumb = try XCTUnwrap(ClipboardThumbnail.make(fromPNG: pngData(width: 40, height: 20)))
        XCTAssertEqual(thumb.size.width, 40, accuracy: 0.5, "小图不得放大")
        XCTAssertEqual(thumb.size.height, 20, accuracy: 0.5)
    }

    func test_makeThumbnail_invalidDataReturnsNil() {
        XCTAssertNil(ClipboardThumbnail.make(fromPNG: Data("not an image".utf8)))
        XCTAssertNil(ClipboardThumbnail.make(fromPNG: Data()))
    }

    // MARK: - 行高度量

    func test_rowHeight_textIsCompact() {
        XCTAssertEqual(ClipboardThumbnail.rowHeight(for: .text), 34)
        XCTAssertEqual(ClipboardThumbnail.rowHeight(for: .files), 34)
    }

    func test_rowHeight_imageUsesAspectRatioWithinBounds() {
        // 方图 256×256、可用宽 400：高度按比例 = min(400, 上限 140)
        let height = ClipboardThumbnail.rowHeight(for: .image, pixelWidth: 256, pixelHeight: 256,
                                                  availableWidth: 400)
        XCTAssertEqual(height, 140 + ClipboardThumbnail.imageRowTextBand
                       + ClipboardThumbnail.imageRowVerticalInset * 2, accuracy: 0.5)
    }

    func test_rowHeight_ultraWideImageClampedToMinimum() {
        // 超宽图 4000×100：400 宽 × 0.025 = 10pt 太细 → 夹到下限 44
        let height = ClipboardThumbnail.rowHeight(for: .image, pixelWidth: 4000, pixelHeight: 100,
                                                  availableWidth: 400)
        XCTAssertEqual(height, 44 + ClipboardThumbnail.imageRowTextBand
                       + ClipboardThumbnail.imageRowVerticalInset * 2, accuracy: 0.5)
    }

    func test_rowHeight_mediumWideImageKeepsAspectRatio() {
        // 3615×674（宽扁截图）：400 宽 × 674/3615 ≈ 74.6 → 处于 [44,140] 内保持比例
        let size = ClipboardThumbnail.thumbnailSize(pixelWidth: 3615, pixelHeight: 674,
                                                    availableWidth: 400)
        XCTAssertEqual(size.height, 400 * 674 / 3615, accuracy: 0.5, "普通宽扁图应保持宽高比")
    }

    func test_rowHeight_unknownSizeFallsBackToSquare() {
        let height = ClipboardThumbnail.rowHeight(for: .image, pixelWidth: 0, pixelHeight: 0,
                                                  availableWidth: 400)
        XCTAssertEqual(height, 140 + ClipboardThumbnail.imageRowTextBand
                       + ClipboardThumbnail.imageRowVerticalInset * 2, accuracy: 0.5)
    }

    func test_rowHeight_imageAccommodatesThumbnail() {
        let height = ClipboardThumbnail.rowHeight(for: .image, pixelWidth: 256, pixelHeight: 256,
                                                  availableWidth: 400)
        XCTAssertGreaterThanOrEqual(height, ClipboardThumbnail.maxThumbnailPixel,
                                    "图片行必须容纳缩略图")
        XCTAssertGreaterThan(height, ClipboardThumbnail.rowHeight(for: .text),
                             "图片行必须比文本行高，否则缩略图被压扁")
    }
}
