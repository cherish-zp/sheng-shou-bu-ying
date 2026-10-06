import XCTest
import CoreGraphics

/// TDD: 滚动截图拼接器 v2 — 打分制重叠检测 + 自适应窗口 + 固定带排除 + 失败边界外推/丢帧。
///
/// 断言清单对应定量审计结论（/tmp/stitch_audit/result.txt）：
/// a. 噪声页全重叠档位精确检出（@1x / @2x）
/// b. 瞬态差异（光标/悬浮物）不再导致整边界判失败
/// c. 周期纹理：返回真值或 nil（歧义拒绝），严禁错误大值
/// d. 渐变页精确检出
/// e. 吸顶固定带：检测 + 排除匹配 + 成图带只出现一次
/// f. 稀疏页：不返回大于真值的偏移
/// g. contentChanged：网格块采样 + 面积比阈值
/// i. stitch 失败边界：dropped / extrapolated / 顺序堆叠 / 空输入
/// 回归：真实感文档逐字节精确、变速滚动、全同帧
final class ScrollStitcherTests: XCTestCase {

    // MARK: - a. 噪声页精确检出

    func test_findOverlap_噪声页_全档位精确检出_1x() {
        for o in [3, 20, 33, 34, 200, 800] {
            let pair = noisePair(w: 600, h: 900, overlap: o, seed: 0x5EED)
            XCTAssertEqual(ScrollStitcher.findOverlap(top: pair.top, bottom: pair.bottom), o, "真重叠 \(o)")
        }
    }

    func test_findOverlap_噪声页_全档位精确检出_2x() {
        for o in [40, 400, 1600] {
            let pair = noisePair(w: 1200, h: 1800, overlap: o, seed: 0x5EED)
            XCTAssertEqual(ScrollStitcher.findOverlap(top: pair.top, bottom: pair.bottom), o, "真重叠 \(o)（Retina 2x）")
        }
    }

    func test_findOverlap_全同帧返回帧高() {
        let pair = noisePair(w: 200, h: 120, overlap: 120, seed: 7)
        XCTAssertEqual(ScrollStitcher.findOverlap(top: pair.top, bottom: pair.top), 120)
    }

    // MARK: - b. 瞬态差异容忍

    func test_findOverlap_真重叠处瞬态差异行不判失败_1x() {
        // 真重叠 200，bottom 帧顶部 7 行有 8px 宽光标块（旧行匹配阈值制直接判 0）
        let w = 600, h = 900, o = 200
        let pair = noisePair(w: w, h: h, overlap: o, seed: 0x9999)
        var bBuf = decodeTopDown(pair.bottom)
        for r in 3..<10 {
            fillRect(&bBuf, w: w, x0: 100, y0: r, x1: 108, y1: r + 1, c: (0, 0, 0))
        }
        let detected = ScrollStitcher.findOverlap(top: pair.top, bottom: makeImage(bBuf, w: w, h: h))
        XCTAssertEqual(detected, o)
    }

    func test_findOverlap_真重叠处瞬态差异行不判失败_2x() {
        let w = 1200, h = 1800, o = 400
        let pair = noisePair(w: w, h: h, overlap: o, seed: 0x9999)
        var bBuf = decodeTopDown(pair.bottom)
        for r in 6..<20 {
            fillRect(&bBuf, w: w, x0: 200, y0: r, x1: 216, y1: r + 1, c: (0, 0, 0))
        }
        XCTAssertEqual(ScrollStitcher.findOverlap(top: pair.top, bottom: makeImage(bBuf, w: w, h: h)), o)
    }

    func test_findOverlap_瞬态差异在top帧底部同样容忍() {
        // 对称性：光标出现在上一帧的重叠区（底部）也不判失败
        let w = 600, h = 900, o = 300
        let page = noiseBuffer(w: w, h: h + (h - o), seed: 0x77)
        var aBuf = Array(page[0..<(h * w * 4)])
        for r in (h - o + 5)..<(h - o + 14) {
            fillRect(&aBuf, w: w, x0: 300, y0: r, x1: 310, y1: r + 1, c: (255, 255, 0))
        }
        let a = makeImage(aBuf, w: w, h: h)
        let b = frame(from: page, w: w, top: h - o, height: h)
        XCTAssertEqual(ScrollStitcher.findOverlap(top: a, bottom: b), o)
    }

    // MARK: - c. 周期纹理：真值或 nil，严禁错误大值

    func test_findOverlap_等距条纹_返回真值或歧义拒绝() {
        let w = 600, h = 900, period = 40
        for o in [200, 210] {
            let page = stripeBuffer(w: w, h: h + (h - o), period: period, darkRows: 8)
            let detected = ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                      bottom: frame(from: page, w: w, top: h - o, height: h))
            XCTAssertTrue(detected == nil || detected == o,
                          "P=\(period) 真值 \(o)：应返回真值或 nil（歧义拒绝），实际 \(String(describing: detected))")
        }
    }

    func test_findOverlap_重复文本行_返回真值或歧义拒绝() {
        let w = 600, h = 900, o = 200
        let page = textBuffer(w: w, h: h + (h - o), tileRows: 28, seed: 42, identicalTiles: true)
        let detected = ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                  bottom: frame(from: page, w: w, top: h - o, height: h))
        XCTAssertTrue(detected == nil || detected == o,
                      "行高 28 完全相同的表格页：应返回真值或 nil，实际 \(String(describing: detected))")
    }

    func test_findOverlap_非重复文本行_精确检出() {
        // 对照：每行文本不同 → 无并列歧义，必须精确检出（旧行匹配阈值制的对照场景）
        let w = 600, h = 900, o = 200
        let page = textBuffer(w: w, h: h + (h - o), tileRows: 28, seed: 42, identicalTiles: false)
        XCTAssertEqual(ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                  bottom: frame(from: page, w: w, top: h - o, height: h)), o)
    }

    // MARK: - d. 渐变页

    func test_findOverlap_渐变页精确检出_1x() {
        // 单调缓变内容：旧行匹配阈值制被 ±N 行混乱带带偏（检测 642），打分制取唯一最小
        let w = 600, h = 900, o = 400
        let page = gradientBuffer(w: w, h: h + (h - o))
        XCTAssertEqual(ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                  bottom: frame(from: page, w: w, top: h - o, height: h)), o)
    }

    func test_findOverlap_渐变页精确检出_2x() {
        let w = 1200, h = 1800, o = 800
        let page = gradientBuffer(w: w, h: h + (h - o))
        XCTAssertEqual(ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                  bottom: frame(from: page, w: w, top: h - o, height: h)), o)
    }

    // MARK: - e. 吸顶固定带

    func test_detectFixedTopBand_检出顶部固定带高度_1x() {
        let frames = stickyBandFrames(scale: 1)
        XCTAssertEqual(ScrollStitcher.detectFixedTopBand(frames: frames.frames), 60)
    }

    func test_detectFixedTopBand_检出顶部固定带高度_2x() {
        let frames = stickyBandFrames(scale: 2)
        XCTAssertEqual(ScrollStitcher.detectFixedTopBand(frames: frames.frames), 120)
    }

    func test_detectFixedTopBand_少于2帧返回0() {
        let pair = noisePair(w: 100, h: 100, overlap: 20, seed: 1)
        XCTAssertEqual(ScrollStitcher.detectFixedTopBand(frames: [pair.top]), 0)
        XCTAssertEqual(ScrollStitcher.detectFixedTopBand(frames: []), 0)
    }

    func test_stitch_固定带只出现一次且正文逐字节对齐() {
        let case1x = stickyBandFrames(scale: 1)
        assertStitchedBandOnce(case1x)
        let case2x = stickyBandFrames(scale: 2)
        assertStitchedBandOnce(case2x)
    }

    func test_findOverlap_显式excludeRows参数排除固定带() {
        // excludeRows 直连验证：2 帧带页传 0..<60 → 精确检出
        let w = 600, h = 900, o = 400
        let page = gradientBuffer(w: w, h: h + (h - o))
        let top = stickyOverlay(frame(from: page, w: w, top: 0, height: h), w: w, bandRows: 60)
        let bottom = stickyOverlay(frame(from: page, w: w, top: h - o, height: h), w: w, bandRows: 60)
        XCTAssertEqual(ScrollStitcher.findOverlap(top: top, bottom: bottom, config: .standard, excludeRows: 0..<60), o)
    }

    // MARK: - f. 稀疏页

    func test_findOverlap_稀疏页_不返回大于真值的偏移() {
        let w = 600, h = 900, o = 200
        let page = sparseBuffer(w: w, h: h + (h - o), textPeriod: 200)
        let detected = ScrollStitcher.findOverlap(top: frame(from: page, w: w, top: 0, height: h),
                                                  bottom: frame(from: page, w: w, top: h - o, height: h))
        if let detected {
            XCTAssertLessThanOrEqual(detected, o, "稀疏页任何偏移都可能局部匹配，绝不允许高估")
        }
    }

    // MARK: - g. contentChanged

    func test_contentChanged_全同帧false() {
        let img = docFrame(w: 600, h: 900, seed: 31_415)
        XCTAssertFalse(ScrollStitcher.contentChanged(img, img))
    }

    func test_contentChanged_光标8x16_居中与跨块角点都false() {
        let base = docFrame(w: 600, h: 900, seed: 31_415)
        var baseBuf = decodeTopDown(base)
        for (x, y) in [(296, 442), (20, 70)] {
            var buf = baseBuf
            fillRect(&buf, w: 600, x0: x, y0: y, x1: x + 8, y1: y + 16, c: (0, 0, 0))
            XCTAssertFalse(ScrollStitcher.contentChanged(base, makeImage(buf, w: 600, h: 900)),
                           "光标位于 (\(x), \(y))：面积 < 阈值不应误报")
        }
        baseBuf = []
    }

    func test_contentChanged_随机位置光标_零误报抽样() {
        // 位置无关性抽样（脚本全量 100 位置的子集）
        let w = 600, h = 900
        var doc = [UInt8](repeating: 255, count: w * h * 4)
        var r = LCG(seed: 5)
        for _ in 0..<30 {
            let bx = Int(r.next() % UInt64(w - 80)), by = Int(r.next() % UInt64(h - 20))
            fillRect(&doc, w: w, x0: bx, y0: by, x1: bx + 60, y1: by + 14, c: (50, 50, 55))
        }
        let base = makeImage(doc, w: w, h: h)
        for t in 0..<10 {
            var rr = LCG(seed: UInt64(t) &+ 900)
            let x = Int(rr.next() % UInt64(w - 8)), y = Int(rr.next() % UInt64(h - 16))
            var d2 = doc
            fillRect(&d2, w: w, x0: x, y0: y, x1: x + 8, y1: y + 16, c: (0, 0, 0))
            XCTAssertFalse(ScrollStitcher.contentChanged(base, makeImage(d2, w: w, h: h)), "t=\(t) 位置 (\(x), \(y))")
        }
    }

    func test_contentChanged_动画40x40_true() {
        // 加载动画红→蓝翻转：灰度均值不变，验证分通道比较
        let w = 600, h = 900
        let base = docFrame(w: w, h: h, seed: 31_415)
        var a = decodeTopDown(base)
        var b = decodeTopDown(base)
        fillRect(&a, w: w, x0: 280, y0: 700, x1: 320, y1: 740, c: (200, 60, 60))
        fillRect(&b, w: w, x0: 280, y0: 700, x1: 320, y1: 740, c: (60, 60, 200))
        XCTAssertTrue(ScrollStitcher.contentChanged(makeImage(a, w: w, h: h), makeImage(b, w: w, h: h)))
    }

    func test_contentChanged_真实角标64x64_true() {
        let w = 600, h = 900
        let base = docFrame(w: w, h: h, seed: 31_415)
        var buf = decodeTopDown(base)
        fillRect(&buf, w: w, x0: 100, y0: 300, x1: 164, y1: 364, c: (30, 30, 30))
        XCTAssertTrue(ScrollStitcher.contentChanged(base, makeImage(buf, w: w, h: h)))
    }

    // MARK: - i. stitch 失败边界

    func test_stitch_边界1失败_丢后帧并记录dropped() {
        let a = frame(from: noiseBuffer(w: 600, h: 900, seed: 1), w: 600, top: 0, height: 900)
        let b = frame(from: noiseBuffer(w: 600, h: 900, seed: 2), w: 600, top: 0, height: 900)  // 与 a 无重叠
        let outcome = ScrollStitcher.stitch(images: [a, b])
        XCTAssertEqual(outcome.failures, [ScrollStitchFailure(frameIndex: 1, kind: .dropped, usedOffset: 0)])
        XCTAssertEqual(outcome.image?.height, 900, "首帧保留，后帧丢弃（绝不 0 重叠静默堆叠）")
        XCTAssertTrue(outcome.requiresAttention)
        XCTAssertTrue(outcome.issues.contains(.noReliableOverlap(frameIndex: 1)))
    }

    func test_stitch_中间边界失败_按上次滚动量外推() {
        let w = 600, h = 900, o = 200, s = h - o
        let page = noiseBuffer(w: w, h: s + h, seed: 7)
        let a = frame(from: page, w: w, top: 0, height: h)
        let b = frame(from: page, w: w, top: s, height: h)
        let c = frame(from: noiseBuffer(w: w, h: h, seed: 8), w: w, top: 0, height: h)  // 与 b 无重叠
        let outcome = ScrollStitcher.stitch(images: [a, b, c])
        XCTAssertEqual(outcome.failures, [ScrollStitchFailure(frameIndex: 2, kind: .extrapolated, usedOffset: s)])
        XCTAssertEqual(outcome.image?.height, 2 * s + h)
        XCTAssertTrue(outcome.requiresAttention)
    }

    func test_stitch_外推连续失败2次_降级丢帧() {
        let w = 600, h = 900, o = 200, s = h - o
        let page = noiseBuffer(w: w, h: s + h, seed: 7)
        let a = frame(from: page, w: w, top: 0, height: h)
        let b = frame(from: page, w: w, top: s, height: h)
        let c = frame(from: noiseBuffer(w: w, h: h, seed: 8), w: w, top: 0, height: h)
        let d = frame(from: noiseBuffer(w: w, h: h, seed: 9), w: w, top: 0, height: h)
        let outcome = ScrollStitcher.stitch(images: [a, b, c, d])
        XCTAssertEqual(outcome.failures, [ScrollStitchFailure(frameIndex: 2, kind: .extrapolated, usedOffset: s),
                                          ScrollStitchFailure(frameIndex: 3, kind: .dropped, usedOffset: 0)])
        XCTAssertEqual(outcome.image?.height, 2 * s + h, "帧 3 丢弃")
    }

    func test_stitch_周期纹理边界_歧义拒绝并降级() {
        // 条纹页端到端：边界歧义 → 首边界丢帧（诚实降级），绝不锁到错误大偏移
        let w = 600, h = 900, o = 200, s = h - o
        let page = stripeBuffer(w: w, h: s + h, period: 40, darkRows: 8)
        let outcome = ScrollStitcher.stitch(images: [frame(from: page, w: w, top: 0, height: h),
                                                     frame(from: page, w: w, top: s, height: h)])
        XCTAssertEqual(outcome.failures, [ScrollStitchFailure(frameIndex: 1, kind: .dropped, usedOffset: 0)])
        XCTAssertTrue(outcome.issues.contains(.ambiguousPattern(frameIndex: 1)))
        XCTAssertEqual(outcome.image?.height, h)
    }

    func test_stitchSequential_零重叠逐帧堆叠() {
        let images = [solidImage(10, w: 60, h: 100), solidImage(60, w: 60, h: 80), solidImage(110, w: 60, h: 60)]
        XCTAssertEqual(ScrollStitcher.stitchSequential(images: images)?.height, 240)
        XCTAssertEqual(ScrollStitcher.stitchSequential(images: images)?.width, 60)
    }

    func test_stitch_空输入_image为nil() {
        XCTAssertNil(ScrollStitcher.stitch(images: []).image)
        XCTAssertNil(ScrollStitcher.stitchSequential(images: []))
    }

    func test_stitch_单帧_原样返回() {
        let img = solidImage(10, w: 40, h: 50)
        let outcome = ScrollStitcher.stitch(images: [img])
        XCTAssertEqual(outcome.image?.height, 50)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertFalse(outcome.requiresAttention)
    }

    // MARK: - 回归：真实感文档 / 变速滚动 / 纯色平台

    func test_stitch_真实感文档_逐字节精确() {
        let w = 600, h = 900, o = 400, s = h - o, n = 5
        let pageH = (n - 1) * s + h
        let page = docBuffer(w: w, h: pageH, seed: 0xD0C)
        let frames = (0..<n).map { frame(from: page, w: w, top: $0 * s, height: h) }
        let outcome = ScrollStitcher.stitch(images: frames)
        XCTAssertEqual(outcome.image?.height, pageH)
        XCTAssertTrue(outcome.failures.isEmpty && outcome.issues.isEmpty)
        if let image = outcome.image {
            XCTAssertEqual(byteDiff(decodeTopDown(image), page), 0, "拼接结果必须与源页面逐字节一致")
        }
    }

    func test_stitch_变速滚动_自适应窗口逐字节精确() {
        let w = 600, h = 900
        let overlaps = [200, 300, 250, 400]
        var tops = [0]
        for o in overlaps { tops.append(tops.last! + h - o) }
        let pageH = tops.last! + h
        let page = noiseBuffer(w: w, h: pageH, seed: 0x51CE)
        let frames = tops.map { frame(from: page, w: w, top: $0, height: h) }
        let outcome = ScrollStitcher.stitch(images: frames)
        XCTAssertEqual(outcome.image?.height, pageH)
        if let image = outcome.image {
            XCTAssertEqual(byteDiff(decodeTopDown(image), page), 0)
        }
    }

    func test_stitch_大幅变速_窗口回退全幅结果一致() {
        // 滚动量 [750, 280, 600]：窗口回退路径覆盖
        let w = 600, h = 900
        let overlaps = [150, 620, 300]
        var tops = [0]
        for o in overlaps { tops.append(tops.last! + h - o) }
        let pageH = tops.last! + h
        let page = noiseBuffer(w: w, h: pageH, seed: 0x9)
        let frames = tops.map { frame(from: page, w: w, top: $0, height: h) }
        let narrowed = ScrollStitcher.stitch(images: frames)
        let full = ScrollStitcher.stitch(images: frames, config: ScrollStitchConfig(searchWindowRatio: 0, minMargin: 0.0015, maxReliableDiff: 0.08))
        XCTAssertEqual(narrowed.image?.height, pageH)
        XCTAssertEqual(narrowed.failures, full.failures)
    }

    func test_findOverlap_纯色平台_歧义拒绝返回nil() {
        // 蓝色 vs 蓝(245/255)：纯色区域任何偏移等价 → 诚实拒绝（v1 硬凑 50 的行为已废弃）
        let w = 100, h = 100
        var aBuf = [UInt8](repeating: 0, count: w * h * 4)
        var bBuf = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: aBuf.count, by: 4) { aBuf[i + 2] = 255; aBuf[i + 3] = 255 }
        for i in stride(from: 0, to: bBuf.count, by: 4) { bBuf[i + 2] = 245; bBuf[i + 3] = 255 }
        XCTAssertNil(ScrollStitcher.findOverlap(top: makeImage(aBuf, w: w, h: h), bottom: makeImage(bBuf, w: w, h: h)))
    }

    func test_findOverlap_完全不同内容_返回nil() {
        let a = frame(from: noiseBuffer(w: 600, h: 900, seed: 1), w: 600, top: 0, height: 900)
        let b = frame(from: noiseBuffer(w: 600, h: 900, seed: 2), w: 600, top: 0, height: 900)
        XCTAssertNil(ScrollStitcher.findOverlap(top: a, bottom: b))
    }

    // MARK: - 性能

    func test_性能_2560x3200单对检测_量级达标() {
        let pair = noisePair(w: 2560, h: 3200, overlap: 200, seed: 0xF00D)
        let start = DispatchTime.now()
        let detected = ScrollStitcher.findOverlap(top: pair.top, bottom: pair.bottom)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        XCTAssertEqual(detected, 200)
        // Release 优化下实测 ≈35ms（v1 为 108ms）；测试 target 以 Debug(-Onone) 跑为 0.7s 左右，
        // 上限 1.5s 只作复杂度量级护栏（复杂度退化会在 Debug 下 >10s），不衡量 Release 精确耗时
        XCTAssertLessThan(elapsed, 1.5, "单对全幅首搜耗时 \(elapsed)s")
    }

    // MARK: - Helpers: 页面合成

    private struct LCG {
        var s: UInt64
        init(seed: UInt64) { s = seed &* 26_858_216_577_363_38717 &+ 1 }
        mutating func next() -> UInt64 {
            s = s &* 6_364_136_223_846_793005 &+ 1_442_695_040_888_963_407
            return s >> 17
        }
    }

    /// top-down RGBA 页面 buffer（row 0 = 视觉顶行）。
    private func noiseBuffer(w: Int, h: Int, seed: UInt64) -> [UInt8] {
        var r = LCG(seed: seed)
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        var i = 0
        while i + 3 < buf.count {
            buf[i] = UInt8(truncatingIfNeeded: r.next())
            buf[i + 1] = UInt8(truncatingIfNeeded: r.next())
            buf[i + 2] = UInt8(truncatingIfNeeded: r.next())
            i += 4
        }
        return buf
    }

    private func stripeBuffer(w: Int, h: Int, period: Int, darkRows: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let c: (UInt8, UInt8, UInt8) = (y % period) < darkRows ? (60, 60, 70) : (235, 235, 240)
            fillRect(&buf, w: w, x0: 0, y0: y, x1: w, y1: y + 1, c: c)
        }
        return buf
    }

    private func textBuffer(w: Int, h: Int, tileRows: Int, seed: UInt64, identicalTiles: Bool) -> [UInt8] {
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        for k in 0..<(h / tileRows) {
            var r = LCG(seed: identicalTiles ? seed : seed &+ UInt64(k) &* 7919)
            let y0 = k * tileRows
            for _ in 0..<(4 + Int(r.next() % 5)) {
                let bx = 16 + Int(r.next() % UInt64(w - 120))
                let bw = 24 + Int(r.next() % 70)
                let gray = UInt8(35 + r.next() % 50)
                fillRect(&buf, w: w, x0: bx, y0: y0 + 6, x1: min(w, bx + bw), y1: y0 + tileRows - 8,
                         c: (gray, gray, UInt8(Int(gray) + 12)))
            }
        }
        return buf
    }

    private func gradientBuffer(w: Int, h: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let v = UInt8(45 + (225 - 45) * y / max(1, h - 1))
            fillRect(&buf, w: w, x0: 0, y0: y, x1: w, y1: y + 1, c: (v, v, v))
        }
        return buf
    }

    private func sparseBuffer(w: Int, h: Int, textPeriod: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        var y = 60
        while y < h - 20 {
            let x0 = 40 + (y * 37) % 200
            fillRect(&buf, w: w, x0: x0, y0: y, x1: min(w, x0 + 260), y1: y + 14, c: (40, 40, 45))
            y += textPeriod
        }
        return buf
    }

    private func docBuffer(w: Int, h: Int, seed: UInt64) -> [UInt8] {
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        fillRect(&buf, w: w, x0: 16, y0: 8, x1: w / 2, y1: 40, c: (30, 30, 34))
        for y in 120..<min(380, h) {
            let v = UInt8(50 + (y - 120) * 160 / 260)
            fillRect(&buf, w: w, x0: 40, y0: y, x1: w - 40, y1: y + 1, c: (v, UInt8(255 - Int(v) / 2), v))
        }
        var y = 420
        var r = LCG(seed: seed)
        while y + 28 < h {
            for _ in 0..<(3 + Int(r.next() % 6)) {
                let bx = 16 + Int(r.next() % UInt64(w - 140))
                let bw = 24 + Int(r.next() % 90)
                let gray = UInt8(35 + r.next() % 60)
                fillRect(&buf, w: w, x0: bx, y0: y + 5, x1: min(w, bx + bw), y1: y + 22, c: (gray, gray, gray))
            }
            y += 28
        }
        return buf
    }

    private func fillRect(_ buf: inout [UInt8], w: Int, x0: Int, y0: Int, x1: Int, y1: Int, c: (UInt8, UInt8, UInt8)) {
        let h = buf.count / (w * 4)
        for y in max(0, y0)..<min(h, y1) {
            var i = y * w * 4 + x0 * 4
            for _ in x0..<x1 {
                buf[i] = c.0; buf[i + 1] = c.1; buf[i + 2] = c.2; buf[i + 3] = 255
                i += 4
            }
        }
    }

    /// 从 top-down 页面 buffer 切出帧（top = 页面内起始行）。
    private func frame(from page: [UInt8], w: Int, top: Int, height: Int) -> CGImage {
        let start = top * w * 4
        return makeImage(Array(page[start..<(start + height * w * 4)]), w: w, h: height)
    }

    private func makeImage(_ buf: [UInt8], w: Int, h: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(buf) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// CGImage → top-down buffer（row 0 = 视觉顶行；CG 位图不翻转绘制时内存 row 0 即视觉顶行）。
    private func decodeTopDown(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height, bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: bpr * h)
        let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }

    private func byteDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        var bad = 0
        for i in 0..<n where a[i] != b[i] { bad += 1 }
        return bad
    }

    private func solidImage(_ v: UInt8, w: Int, h: Int) -> CGImage {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: buf.count, by: 4) {
            buf[i] = v; buf[i + 1] = v; buf[i + 2] = v; buf[i + 3] = 255
        }
        return makeImage(buf, w: w, h: h)
    }

    /// 同一页面上按 overlap 滚动的一对噪声帧。
    private func noisePair(w: Int, h: Int, overlap: Int, seed: UInt64) -> (top: CGImage, bottom: CGImage) {
        let page = noiseBuffer(w: w, h: h + (h - overlap), seed: seed)
        return (frame(from: page, w: w, top: 0, height: h),
                frame(from: page, w: w, top: h - overlap, height: h))
    }

    /// 帧顶部覆盖吸顶带（灰 128 × (band-4) 行 + 深 88 × 4 行）。
    private func stickyOverlay(_ image: CGImage, w: Int, bandRows: Int) -> CGImage {
        var buf = decodeTopDown(image)
        fillRect(&buf, w: w, x0: 0, y0: 0, x1: w, y1: bandRows - 4, c: (128, 128, 128))
        fillRect(&buf, w: w, x0: 0, y0: bandRows - 4, x1: w, y1: bandRows, c: (88, 88, 88))
        return makeImage(buf, w: w, h: image.height)
    }

    private struct BandCase {
        var frames: [CGImage]
        var page: [UInt8]
        var w: Int
        var pageH: Int
        var band: Int
    }

    /// 渐变页 + 每帧顶部吸顶带的 5 帧序列（真重叠 = 400×scale，滚动 s = 500×scale）。
    private func stickyBandFrames(scale: Int) -> BandCase {
        let w = 600 * scale, h = 900 * scale, o = 400 * scale, s = h - o, n = 5, band = 60 * scale
        let pageH = (n - 1) * s + h
        let page = gradientBuffer(w: w, h: pageH)
        let frames = (0..<n).map { k in
            stickyOverlay(frame(from: page, w: w, top: k * s, height: h), w: w, bandRows: band)
        }
        return BandCase(frames: frames, page: page, w: w, pageH: pageH, band: band)
    }

    /// 断言：固定带检测结果正确、成图带只出现一次、正文与源页面逐字节对齐。
    private func assertStitchedBandOnce(_ bc: BandCase) {
        let outcome = ScrollStitcher.stitch(images: bc.frames)
        XCTAssertEqual(outcome.image?.height, bc.pageH)
        XCTAssertTrue(outcome.issues.contains(.fixedBandExcluded(height: bc.band)), "issues=\(outcome.issues)")
        XCTAssertTrue(outcome.failures.isEmpty, "failures=\(outcome.failures)")
        guard let image = outcome.image else { return XCTFail("无成图") }
        let outBuf = decodeTopDown(image)
        // 带签名行：RGB=(128,128,128)（fillRect 写入的实心灰）
        var sig = [UInt8](repeating: 128, count: bc.w * 4)
        for i in stride(from: 3, to: bc.w * 4, by: 4) { sig[i] = 255 }
        // minRun=40：2x 渐变页（5800 行分 180 级灰度）经整数舍入会出现 ≈33 行同色量化平台，
        // 门槛必须大于平台宽度；真带 1x=56 / 2x=116 行均远大于 40
        XCTAssertEqual(countBands(outBuf, w: bc.w, sig: sig, minRun: 40), 1, "吸顶带必须只出现一次")
        // 真值：row [0, band) = 带内容；row [band, pageH) = page[band, pageH)
        var expect = [UInt8](repeating: 0, count: bc.pageH * bc.w * 4)
        fillRect(&expect, w: bc.w, x0: 0, y0: 0, x1: bc.w, y1: bc.band - 4, c: (128, 128, 128))
        fillRect(&expect, w: bc.w, x0: 0, y0: bc.band - 4, x1: bc.w, y1: bc.band, c: (88, 88, 88))
        expect.replaceSubrange((bc.band * bc.w * 4)..<(bc.pageH * bc.w * 4),
                               with: bc.page[(bc.band * bc.w * 4)..<(bc.pageH * bc.w * 4)])
        XCTAssertEqual(byteDiff(outBuf, expect), 0, "正文必须逐字节对齐")
    }

    /// 统计与签名行一致、长度 ≥ minRun 的连续行带数（吸顶带计数）。
    private func countBands(_ buf: [UInt8], w: Int, sig: [UInt8], minRun: Int) -> Int {
        let bpr = w * 4
        let rows = buf.count / bpr
        var bands = 0, run = 0
        for y in 0..<rows {
            let s = y * bpr
            var eq = true
            for i in 0..<bpr where buf[s + i] != sig[i] { eq = false; break }
            if eq { run += 1 } else {
                if run >= minRun { bands += 1 }
                run = 0
            }
        }
        if run >= minRun { bands += 1 }
        return bands
    }

    private func docFrame(w: Int, h: Int, seed: UInt64) -> CGImage {
        frame(from: docBuffer(w: w, h: h, seed: seed), w: w, top: 0, height: h)
    }
}
