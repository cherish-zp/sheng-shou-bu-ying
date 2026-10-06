import CoreGraphics
import Foundation

// MARK: - 配置与结果类型

/// 滚动截图拼接配置（v2 打分制）。
public struct ScrollStitchConfig {
    /// 以上一边界滚动量为中心的收窄窗口比例，默认 0.5（±50%）；<=0 表示全幅搜索。
    public var searchWindowRatio: Double
    /// 最优与次优（间距 ≥ 歧义最小间距）归一化差异得分的最小差值要求（防周期纹理歧义）。
    /// 默认 0.0015：约为噪声页真值与错误偏移得分差（≈0.33）的 1/200，
    /// 低于渐变页 ±16 行偏移的得分增量（≈0.004~0.015），可放行缓变内容、拒绝周期并列。
    public var minMargin: Double
    /// 最优得分（归一化平均差异 0~1）高于此值 → 判「无可靠重叠」。
    /// 默认 0.08：真实截图真值处得分 ≤ ≈0.02（瞬态行摊薄），留 4 倍余量；
    /// 完全不匹配的自然内容得分 ≥ 0.15，可稳定拒绝。
    public var maxReliableDiff: Double

    public init(searchWindowRatio: Double = 0.5,
                minMargin: Double = 0.0015,
                maxReliableDiff: Double = 0.08) {
        self.searchWindowRatio = searchWindowRatio
        self.minMargin = minMargin
        self.maxReliableDiff = maxReliableDiff
    }

    /// 默认配置。
    public static let standard = ScrollStitchConfig()
}

/// 拼接过程中的非致命问题（诊断用）。
public enum ScrollStitchIssue: Equatable {
    /// 边界无可靠重叠（已外推或丢帧）。
    case noReliableOverlap(frameIndex: Int)
    /// 打分歧义（周期并列等），拒绝该边界。
    case ambiguousPattern(frameIndex: Int)
    /// 检出顶部固定带并已从匹配中排除。
    case fixedBandExcluded(height: Int)
}

/// 失败边界的处理方式。
public enum ScrollStitchFailureKind: Equatable { case extrapolated, dropped }

/// 失败边界记录。
public struct ScrollStitchFailure: Equatable {
    /// 边界序号 >=1：第 frameIndex 帧与其前一帧之间。
    public let frameIndex: Int
    public let kind: ScrollStitchFailureKind
    /// extrapolated 时为外推 offset；dropped 为 0。
    public let usedOffset: Int

    public init(frameIndex: Int, kind: ScrollStitchFailureKind, usedOffset: Int) {
        self.frameIndex = frameIndex
        self.kind = kind
        self.usedOffset = usedOffset
    }
}

// MARK: - 冻结契约类型

/// 单个拼接边界的状态。
public enum ScrollStitchBoundaryStatus: Equatable {
    /// 检测成功；confidence ∈ [0, 1]，1 = 重叠区逐像素一致。
    case matched(confidence: Double)
    /// 检测失败，按上一次成功边界的滚动量外推落位。
    case extrapolated
    /// 检测失败且无外推依据，该帧被丢弃（绝不按 0 重叠静默堆叠）。
    case dropped
}

/// 拼接边界：描述第 i+1 帧相对已保留内容的落位。
/// offset = 后一帧顶边在输出画布中的 y 坐标；status == .dropped 时该帧不在输出中，offset == -1。
public struct ScrollStitchBoundary: Equatable {
    public let offset: Int
    public let status: ScrollStitchBoundaryStatus

    public init(offset: Int, status: ScrollStitchBoundaryStatus) {
        self.offset = offset
        self.status = status
    }
}

/// 冻结契约结果类型：与 `ScrollStitchOutcome` 同一（后者是携带诊断信息的超集）。
public typealias ScrollStitchResult = ScrollStitchOutcome

/// 拼接结果：成图 + 诊断信息 + 逐边界落位。
public struct ScrollStitchOutcome {
    /// 成图（含外推结果）；frames 空时 nil。
    public let image: CGImage?
    public let issues: [ScrollStitchIssue]
    public let failures: [ScrollStitchFailure]
    /// 顶部固定带高度（像素）；0=无。
    public let fixedTopBandHeight: Int
    /// 冻结契约：逐边界落位，count == max(0, frames.count - 1)，boundaries[i] 描述第 i+1 帧。
    public let boundaries: [ScrollStitchBoundary]
    /// failures 非空 → 需要用户关注。
    public var requiresAttention: Bool { !failures.isEmpty }
    /// 冻结契约：status != .matched 的边界数（外推 + 丢弃）。
    public var failedBoundaryCount: Int {
        boundaries.lazy.filter { boundary in
            if case .matched = boundary.status { return false }
            return true
        }.count
    }

    public init(image: CGImage?,
                issues: [ScrollStitchIssue] = [],
                failures: [ScrollStitchFailure] = [],
                fixedTopBandHeight: Int = 0,
                boundaries: [ScrollStitchBoundary] = []) {
        self.image = image
        self.issues = issues
        self.failures = failures
        self.fixedTopBandHeight = fixedTopBandHeight
        self.boundaries = boundaries
    }
}

// MARK: - 帧签名

/// 帧签名：top-down 解码后按相对均匀列位置采样得到的每行 RGB 特征。
/// 行 r、列 c、通道 ch 存于 values[(r * columns + c) * 3 + ch]。
/// 只保留采样特征（约 height×192 字节），解码后的像素缓冲即取即弃，控制内存峰值。
struct StitchFrameSignature {
    let width: Int
    let height: Int
    let columns: Int
    var values: [UInt8]

    /// 列采样数上限：64 列均匀覆盖全宽（旧实现只取 5 列且集中左侧，是漏检根因之一）。
    static let maxColumns = 64

    init?(image: CGImage, columns requestedColumns: Int) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let k = max(1, min(requestedColumns, w))
        let bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: bpr * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // 不翻转绘制：CG 位图内存第 0 行即视觉顶行（top-down）。
        // 旧 rgbaBuffer 的 translate+flip 得到的是 bottom-up，这里语义统一为 top-down。
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var xs = [Int](repeating: 0, count: k)
        for c in 0..<k {
            xs[c] = ((2 * c + 1) * w) / (2 * k)
        }
        var values = [UInt8](repeating: 0, count: h * k * 3)
        for y in 0..<h {
            let rowStart = y * bpr
            let dst = y * k * 3
            for c in 0..<k {
                let src = rowStart + xs[c] * 4
                values[dst + c * 3] = buffer[src]
                values[dst + c * 3 + 1] = buffer[src + 1]
                values[dst + c * 3 + 2] = buffer[src + 2]
            }
        }
        self.width = w
        self.height = h
        self.columns = k
        self.values = values
    }
}

// MARK: - 拼接器

/// 滚动截图拼接器 v2：打分选优 + 自适应搜索窗口 + 固定带匹配排除 + 失败边界外推/丢帧。
///
/// 与 v1 的差异（对应定量审计结论）：
/// 1. 重叠检测从「≥97% 行匹配阈值制」改为归一化差异打分选全局最优——瞬态差异只摊薄得分，
///    不再一票否决；周期纹理在真值处 diff≈0，打分制自然取真值。
/// 2. 检测失败绝不回退「0 重叠整帧堆叠」，而是外推（有 prev）或丢帧，并记录 failure。
/// 3. contentChanged 改为二维网格块采样 + 差异块面积比阈值，消除单字节抽样的位置依赖。
/// 4. 行/列比较覆盖全宽均匀采样（64 列），不再只用左侧 5 列。
/// 5. 每帧顶部固定带（吸顶元素）先检测后从匹配中排除，不再破坏匹配。
/// 6. 会话层用字节预算取代帧数硬上限（见 ScrollCaptureSession）。
public enum ScrollStitcher {

    /// 歧义判定的最小候选间距（行）：次优解需与最优解相距至少该行数才构成「并列歧义」。
    /// 取 16：小于测试覆盖的最小周期（文本行 28、条纹 40），周期并列必然在 ≥16 行外重复出现；
    /// 又大于渐变页得分曲线的近邻尺度，避免把缓变内容的近邻低分误判为歧义。
    private static let ambiguityMinSeparation = 16
    /// 小重叠候选的证据量置信惩罚：调整分 = 原始分 + 该权重 / 重叠行数。
    /// 重叠越小参与比较的行越少，空白页面上越容易撞出 0 分假最优（实测文档页
    /// 单行空白巧合压过真值 400）。权重 0.02 的依据：
    /// - 拉开小 O 巧合：O=1 惩罚 0.02，与真值（惩罚≈0）的差 ≈ 0.02 > minMargin(0.0015) 13 倍；
    /// - 不误伤小真值：O=3 真值调整分 0.0067 ≪ 错误候选得分（≈0.33）与 maxReliableDiff(0.08)；
    /// - 不破坏周期歧义判定：相邻倍周期的惩罚差 ≈ λ·P/O² ≤ 0.02×40/200² ≈ 2e-5 ≪ minMargin，
    ///   周期并列仍被歧义门拒绝。
    private static let smallOverlapEvidenceWeight = 0.02
    /// 粗筛阶段保留精算候选的得分容差。
    private static let coarseKeepEpsilon = 0.02
    /// 精算候选数上限（防止病态稀疏页保留过多近零候选）。
    private static let fineCandidateCap = 32
    /// 固定带行判「静止」的通道容差（容忍色彩管理的 ±1~2 抖动）。
    private static let bandStaticTolerance = 5

    /// v2 主入口：打分选优 + 自适应搜索窗口 + 固定带匹配排除 + 失败边界外推/丢帧
    /// （绝不 0 重叠静默堆叠）。
    public static func stitch(images: [CGImage], config: ScrollStitchConfig = .standard) -> ScrollStitchOutcome {
        guard let first = images.first else {
            return ScrollStitchOutcome(image: nil, issues: [], failures: [], fixedTopBandHeight: 0)
        }
        guard images.count > 1 else {
            return ScrollStitchOutcome(image: first, issues: [], failures: [], fixedTopBandHeight: 0)
        }

        // 统一列数（取最窄帧宽），一次解码建签名，固定带检测与边界探测共用。
        let minWidth = images.map { $0.width }.min() ?? 1
        let columns = min(StitchFrameSignature.maxColumns, max(1, minWidth))
        let signatures = images.compactMap { StitchFrameSignature(image: $0, columns: columns) }
        guard signatures.count == images.count else {
            let dropped = (1..<images.count).map { _ in ScrollStitchBoundary(offset: -1, status: .dropped) }
            return ScrollStitchOutcome(image: nil, issues: [], failures: [],
                                       fixedTopBandHeight: 0, boundaries: dropped)
        }

        // 1. 固定带：检出后从所有边界的匹配比较中排除（不改输出像素）。
        let band = detectFixedTopBand(signatures: signatures)
        let excludeRows: Range<Int>? = band > 0 ? 0..<band : nil
        var issues: [ScrollStitchIssue] = []
        if band > 0 { issues.append(.fixedBandExcluded(height: band)) }

        // 2. 逐边界检测 + 失败处理。
        var offsets = [Int](repeating: 0, count: images.count)
        var kept = [Bool](repeating: false, count: images.count)
        kept[0] = true
        var lastKept = 0
        var prevScroll: Int? = nil          // 上一次成功边界的滚动量（帧高 - 重叠）
        var consecutiveExtrapolations = 0
        var failures: [ScrollStitchFailure] = []
        var boundaries: [ScrollStitchBoundary] = []

        for i in 1..<images.count {
            let top = signatures[lastKept]
            let bottom = signatures[i]

            // 自适应窗口：以上一边界滚动量 prevScroll 为中心 ±searchWindowRatio 收窄；
            // 重叠 O = h_top - scroll → O ∈ [h - s(1+r), h - s(1-r)]。首对全幅。
            var range: ClosedRange<Int>? = nil
            var narrowed = false
            if let s = prevScroll, config.searchWindowRatio > 0 {
                let hTop = images[lastKept].height
                let lo = Int((Double(hTop) - Double(s) * (1 + config.searchWindowRatio)).rounded(.up))
                let hi = Int((Double(hTop) - Double(s) * (1 - config.searchWindowRatio)).rounded(.down))
                let clampedLo = max(1, lo)
                if clampedLo <= hi {
                    range = clampedLo...hi
                    narrowed = true
                }
            }

            var probe = detectOverlap(top: top, bottom: bottom, config: config,
                                      excludeRows: excludeRows, overlapRange: range)
            if narrowed, !probe.isMatched {
                // 窗口内无解 → 回退全幅再判。
                probe = detectOverlap(top: top, bottom: bottom, config: config,
                                      excludeRows: excludeRows, overlapRange: nil)
            }

            if case .matched(let overlap, let score) = probe {
                offsets[i] = offsets[lastKept] + images[lastKept].height - overlap
                kept[i] = true
                prevScroll = images[lastKept].height - overlap
                lastKept = i
                consecutiveExtrapolations = 0
                // confidence ∈ [0,1]：得分 0 → 1；达到 maxReliableDiff 上限 → 0。
                let confidence = max(0, min(1, 1 - score / 0.05))
                boundaries.append(ScrollStitchBoundary(offset: offsets[i], status: .matched(confidence: confidence)))
            } else {
                // 记录问题类型（无可靠重叠 / 打分歧义）。
                issues.append(probe == .ambiguousPattern
                              ? .ambiguousPattern(frameIndex: i)
                              : .noReliableOverlap(frameIndex: i))
                if let s = prevScroll, consecutiveExtrapolations < 1 {
                    // 后续边界失败：按上一次滚动量 s 外推该帧位置（连续失败 ≥2 次降级丢帧）。
                    offsets[i] = offsets[lastKept] + s
                    kept[i] = true
                    lastKept = i
                    failures.append(ScrollStitchFailure(frameIndex: i, kind: .extrapolated, usedOffset: s))
                    consecutiveExtrapolations += 1
                    boundaries.append(ScrollStitchBoundary(offset: offsets[i], status: .extrapolated))
                } else {
                    // 首对失败（无 prev 可外推）或外推连续 ≥2 次：丢该帧。
                    failures.append(ScrollStitchFailure(frameIndex: i, kind: .dropped, usedOffset: 0))
                    kept[i] = false
                    consecutiveExtrapolations = 0
                    boundaries.append(ScrollStitchBoundary(offset: -1, status: .dropped))
                }
            }
        }

        // 3. 绘制输出：只画保留的帧；重叠区保留先帧像素（后帧仅补新内容）。
        let width = first.width
        guard let lastKeptIndex = kept.lastIndex(where: { $0 }) else {
            return ScrollStitchOutcome(image: nil, issues: issues, failures: failures,
                                       fixedTopBandHeight: band, boundaries: boundaries)
        }
        let totalHeight = offsets[lastKeptIndex] + images[lastKeptIndex].height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ScrollStitchOutcome(image: nil, issues: issues, failures: failures,
                                       fixedTopBandHeight: band, boundaries: boundaries)
        }
        // 位图上下文内存 row 0 = 上下文 y=0（视觉底），画在 y = totalHeight - offset - h
        // 使帧的视觉顶行恰好落在输出行 offset（绘制语义已由逐字节回归验证）。
        for i in kept.indices.reversed() where kept[i] {
            let yInContext = totalHeight - offsets[i] - images[i].height
            ctx.draw(images[i], in: CGRect(x: 0, y: CGFloat(yInContext),
                                           width: CGFloat(width), height: CGFloat(images[i].height)))
        }
        return ScrollStitchOutcome(image: ctx.makeImage(), issues: issues,
                                   failures: failures, fixedTopBandHeight: band,
                                   boundaries: boundaries)
    }

    /// 强制顺序堆叠（0 重叠逐帧堆叠，含第一帧）——结果窗「强制堆叠」选项用。
    public static func stitchSequential(images: [CGImage]) -> CGImage? {
        guard let first = images.first else { return nil }
        if images.count == 1 { return first }
        let totalHeight = images.reduce(0) { $0 + $1.height }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: first.width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var yTop = 0
        for img in images {
            ctx.draw(img, in: CGRect(x: 0, y: CGFloat(totalHeight - yTop - img.height),
                                     width: CGFloat(img.width), height: CGFloat(img.height)))
            yTop += img.height
        }
        return ctx.makeImage()
    }

    /// 两帧可靠重叠检测：返回重叠像素行数；无可靠重叠返回 nil。
    /// - Parameters:
    ///   - config: 打分制参数。
    ///   - excludeRows: bottom 帧顶部需从比较中排除的行范围（如固定带 0..<bandHeight）。
    public static func findOverlap(top: CGImage, bottom: CGImage,
                                   config: ScrollStitchConfig = .standard,
                                   excludeRows: Range<Int>? = nil) -> Int? {
        guard let topSig = StitchFrameSignature(image: top, columns: StitchFrameSignature.maxColumns),
              let bottomSig = StitchFrameSignature(image: bottom, columns: StitchFrameSignature.maxColumns) else {
            return nil
        }
        if case .matched(let overlap, _) = detectOverlap(top: topSig, bottom: bottomSig, config: config,
                                                         excludeRows: excludeRows, overlapRange: nil) {
            return overlap
        }
        return nil
    }

    // MARK: - 冻结契约入口

    /// 冻结契约主入口：打分选优拼接，等价 `stitch(images:config: .standard)`。
    /// 失败边界：优先用上一成功边界的滚动量外推，无历史则丢弃后帧；绝不按 0 重叠静默堆叠。
    public static func stitch(images: [CGImage]) -> ScrollStitchResult {
        stitch(images: images, config: .standard)
    }

    /// 冻结契约：强制顺序堆叠（0 重叠逐帧堆叠），等价 `stitchSequential`。
    public static func forceStack(images: [CGImage]) -> CGImage? {
        stitchSequential(images: images)
    }

    /// 冻结契约：单边界检测。nil = 检测失败（含歧义拒绝）。
    /// - previousDelta: 上一成功边界的滚动量（帧高 - 重叠）。非 nil 时先在
    ///   重叠窗口 [0.5×(H-d), 1.5×(H-d)] 内搜索，未命中再全幅扫描。
    public static func detectOverlap(top: CGImage, bottom: CGImage, previousDelta: Int?) -> Int? {
        guard let topSig = StitchFrameSignature(image: top, columns: StitchFrameSignature.maxColumns),
              let bottomSig = StitchFrameSignature(image: bottom, columns: StitchFrameSignature.maxColumns) else {
            return nil
        }
        var range: ClosedRange<Int>? = nil
        if let s = previousDelta, s > 0, s < top.height {
            let hTop = Double(top.height)
            let lo = max(1, Int((hTop - Double(s) * 1.5).rounded(.up)))
            let hi = min(min(top.height, bottom.height), Int((hTop - Double(s) * 0.5).rounded(.down)))
            if lo <= hi { range = lo...hi }
        }
        if case .matched(let overlap, _) = detectOverlap(top: topSig, bottom: bottomSig, config: .standard,
                                                         excludeRows: nil, overlapRange: range) {
            return overlap
        }
        if range != nil,
           case .matched(let overlap, _) = detectOverlap(top: topSig, bottom: bottomSig, config: .standard,
                                                         excludeRows: nil, overlapRange: nil) {
            return overlap
        }
        return nil
    }

    /// 逐行时序方差检测帧序列「顶部固定行带」高度（像素）；<2 帧或无固定带 → 0。
    /// 只检测顶部连续行带：某行在所有帧中逐像素近似一致（吸顶元素）则属于带。
    public static func detectFixedTopBand(frames: [CGImage]) -> Int {
        guard frames.count >= 2 else { return 0 }
        let minWidth = frames.map { $0.width }.min() ?? 1
        let columns = min(StitchFrameSignature.maxColumns, max(1, minWidth))
        let signatures = frames.compactMap { StitchFrameSignature(image: $0, columns: columns) }
        guard signatures.count == frames.count else { return 0 }
        return detectFixedTopBand(signatures: signatures)
    }

    /// 帧内容是否变化：二维网格采样（24×24 网格取块均值）+ 差异块面积比阈值。
    ///
    /// 参数依据（对应审计场景 D）：
    /// - 块差异阈值 25/255：8×16 光标对所在块（25×37.5 像素）的均值位移 ≤ 17（跨块角点摆放）
    ///   或单块 35（居中摆放，仅 1 块），均不构成「差异块」或低于 3 块门槛 → 判 false；
    /// - 面积比阈值 0.005（576 块 → ≥3 块）：40×40 动画稳定影响 4 块且均值位移 37~82 → 判 true；
    ///   64×64 真实角标影响 ≥6 块 → true。小面积瞬态（光标）不再既可能漏报又可能误报。
    public static func contentChanged(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return true }
        let w = a.width, h = a.height
        guard w > 0, h > 0 else { return false }
        guard let bufA = decodeTopDown(a), let bufB = decodeTopDown(b) else { return true }

        let grid = 24
        let cols = min(grid, w), rows = min(grid, h)
        let totalBlocks = cols * rows
        // 面积比阈值 0.005，向上取整（576 块 → 3 块）。
        let blockThreshold = max(1, Int((Double(totalBlocks) * 0.005).rounded(.up)))
        let blockDiffThreshold = 25
        var changedBlocks = 0

        for cy in 0..<rows {
            let y0 = cy * h / rows, y1 = (cy + 1) * h / rows
            let cellH = max(1, y1 - y0)
            let stepY = max(1, cellH / 8)
            for cx in 0..<cols {
                let x0 = cx * w / cols, x1 = (cx + 1) * w / cols
                let cellW = max(1, x1 - x0)
                let stepX = max(1, cellW / 8)
                var sumA = [0, 0, 0]
                var sumB = [0, 0, 0]
                var pixelSamples = 0
                var y = y0
                while y < y1 {
                    var x = x0
                    let rowOffset = y * w * 4
                    while x < x1 {
                        let idx = rowOffset + x * 4
                        sumA[0] += Int(bufA[idx]); sumA[1] += Int(bufA[idx + 1]); sumA[2] += Int(bufA[idx + 2])
                        sumB[0] += Int(bufB[idx]); sumB[1] += Int(bufB[idx + 1]); sumB[2] += Int(bufB[idx + 2])
                        pixelSamples += 1
                        x += stepX
                    }
                    y += stepY
                }
                guard pixelSamples > 0 else { continue }
                // 分通道比较：色相翻转（如红→蓝加载动画）的灰度均值可能不变，必须逐通道判差异。
                let maxChannelDiff = (0...2).map { abs(sumA[$0] - sumB[$0]) / pixelSamples }.max() ?? 0
                if maxChannelDiff > blockDiffThreshold {
                    changedBlocks += 1
                    if changedBlocks >= blockThreshold { return true }
                }
            }
        }
        return false
    }

    // MARK: - 内部：重叠探测

    /// 边界探测结果。
    private enum OverlapProbe: Equatable {
        case matched(offset: Int, score: Double)
        case unreliable
        case ambiguousPattern

        var isMatched: Bool {
            if case .matched = self { return true }
            return false
        }
    }

    /// 候选重叠 O 的归一化平均差异得分（0~1，越小越好）。
    /// top 的底部 O 行与 bottom 的顶部 O 行按页面坐标对齐，全行（可按行距抽样）、
    /// 全宽均匀采样列、RGB 三通道参与；excludeRows 为 bottom 顶部跳过的行（固定带）。
    /// 返回 nil 表示该候选无可评估样本（如重叠全部落在排除带内）。
    private static func meanDiffScore(top: StitchFrameSignature, bottom: StitchFrameSignature,
                                      overlap: Int, rowStride: Int, colStride: Int,
                                      excludeRows: Range<Int>?) -> Double? {
        let o = overlap
        guard o >= 1, o <= top.height, o <= bottom.height else { return nil }
        let columns = min(top.columns, bottom.columns)
        guard columns > 0 else { return nil }
        let exLow = excludeRows?.lowerBound ?? 0
        let exHigh = min(excludeRows?.upperBound ?? 0, o)
        let tv = top.values
        let bv = bottom.values
        let topRowBase = top.height - o
        var total = 0
        var samples = 0
        var r = 0
        while r < o {
            // 固定带行排除：bottom 顶部 [exLow, exHigh) 落在重叠内的行不参与匹配。
            let skipRow = exHigh > exLow && r >= exLow && r < exHigh
            if !skipRow {
                let tBase = (topRowBase + r) * top.columns
                let bBase = r * bottom.columns
                var c = 0
                while c < columns {
                    let ti = (tBase + c) * 3
                    let bi = (bBase + c) * 3
                    total += abs(Int(tv[ti]) - Int(bv[bi]))
                        + abs(Int(tv[ti + 1]) - Int(bv[bi + 1]))
                        + abs(Int(tv[ti + 2]) - Int(bv[bi + 2]))
                    samples += 3
                    c += colStride
                }
            }
            r += rowStride
        }
        guard samples > 0 else { return nil }
        return Double(total) / (Double(samples) * 255.0)
    }

    /// 打分选优：粗筛全候选（行/列双重抽样）→ 精算近零候选 + 远簇代表 →
    /// maxReliableDiff 门（无可靠重叠）+ minMargin 歧义门（周期并列）。
    private static func detectOverlap(top: StitchFrameSignature, bottom: StitchFrameSignature,
                                      config: ScrollStitchConfig, excludeRows: Range<Int>?,
                                      overlapRange: ClosedRange<Int>?) -> OverlapProbe {
        let maxOverlap = min(top.height, bottom.height)
        guard maxOverlap >= 1 else { return .unreliable }
        let lo = max(1, overlapRange?.lowerBound ?? 1)
        let hi = min(maxOverlap, overlapRange?.upperBound ?? maxOverlap)
        guard lo <= hi else { return .unreliable }

        // —— 粗筛：行距随帧高放大（3200 行帧 → 16），列距 4（64 列 → 16 列），
        //    像素级精确内容在粗筛下得分同样为 0，真值峰不会漏。
        let coarseRowStride = max(2, maxOverlap / 200)
        let coarseColStride = top.columns >= 8 ? 4 : 1
        var coarse = [Double](repeating: .infinity, count: hi - lo + 1)
        var coarseMin = Double.infinity
        var coarseArgmin = -1
        for o in lo...hi {
            if let s = meanDiffScore(top: top, bottom: bottom, overlap: o,
                                     rowStride: coarseRowStride, colStride: coarseColStride,
                                     excludeRows: excludeRows) {
                coarse[o - lo] = s
                if s < coarseMin {
                    coarseMin = s
                    coarseArgmin = o
                }
            }
        }
        guard coarseMin.isFinite, coarseArgmin > 0 else { return .unreliable }

        // —— 精算候选：粗得分接近最优者（真值峰 + 周期并列簇），另加「远离最优的最优者」
        //    作为歧义判定的次优代表。按粗得分升序限量，防止稀疏页保留过多候选。
        var candidates = (lo...hi).filter { coarse[$0 - lo] <= coarseMin + coarseKeepEpsilon }
        var farBest: Int? = nil
        var farBestScore = Double.infinity
        for o in lo...hi where abs(o - coarseArgmin) >= ambiguityMinSeparation {
            if coarse[o - lo] < farBestScore {
                farBestScore = coarse[o - lo]
                farBest = o
            }
        }
        candidates.sort {
            let sa = coarse[$0 - lo], sb = coarse[$1 - lo]
            return sa == sb ? $0 < $1 : sa < sb
        }
        if candidates.count > fineCandidateCap {
            candidates = Array(candidates.prefix(fineCandidateCap))
        }
        if let fb = farBest, !candidates.contains(fb) {
            candidates.append(fb)
        }

        // —— 精算：行距 1、全列，得分即最终得分。
        // 调整分 = 原始分 + 证据量惩罚（小重叠比较行少，空白巧合风险高）。
        var fine: [(offset: Int, score: Double)] = []
        fine.reserveCapacity(candidates.count)
        for o in candidates {
            if let s = meanDiffScore(top: top, bottom: bottom, overlap: o,
                                     rowStride: 1, colStride: 1, excludeRows: excludeRows) {
                fine.append((o, s + smallOverlapEvidenceWeight / Double(o)))
            }
        }
        guard let best = fine.min(by: { $0.score == $1.score ? $0.offset < $1.offset : $0.score < $1.score }) else {
            return .unreliable
        }
        if best.score > max(0, config.maxReliableDiff) { return .unreliable }

        // 歧义：与最优相距 ≥ ambiguityMinSeparation 的候选中，存在得分差 < minMargin 者
        // （周期并列 / 纯色平台），拒绝该边界而非瞎给偏移。
        let margin = max(0, config.minMargin)
        if let second = fine.filter({ abs($0.offset - best.offset) >= ambiguityMinSeparation })
            .min(by: { $0.score < $1.score }),
            second.score - best.score < margin {
            return .ambiguousPattern
        }
        return .matched(offset: best.offset, score: best.score)
    }

    // MARK: - 内部：固定带检测

    /// 基于签名的固定带检测：行 r 在所有帧中逐采样通道差 ≤ bandStaticTolerance 视为静止，
    /// 取顶部最大连续静止前缀；全帧静止（无滚动）不视为固定带，返回 0。
    private static func detectFixedTopBand(signatures: [StitchFrameSignature]) -> Int {
        guard signatures.count >= 2 else { return 0 }
        let minHeight = signatures.map { $0.height }.min() ?? 0
        let columns = signatures.map { $0.columns }.min() ?? 0
        guard minHeight > 0, columns > 0 else { return 0 }
        var band = 0
        for r in 0..<minHeight {
            let refBase = r * signatures[0].columns * 3
            var isStatic = true
            for f in 1..<signatures.count {
                let base = r * signatures[f].columns * 3
                var ch = 0
                while ch < columns * 3 {
                    if abs(Int(signatures[f].values[base + ch]) - Int(signatures[0].values[refBase + ch])) > bandStaticTolerance {
                        isStatic = false
                        break
                    }
                    ch += 1
                }
                if !isStatic { break }
            }
            if isStatic {
                band = r + 1
            } else {
                break
            }
        }
        if band >= minHeight { return 0 }  // 整帧静止 = 无滚动，不是固定带
        return band
    }

    // MARK: - 内部：解码

    /// top-down 解码（内存 row 0 = 视觉顶行），供 contentChanged 使用。
    private static func decodeTopDown(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: bpr * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }
}
