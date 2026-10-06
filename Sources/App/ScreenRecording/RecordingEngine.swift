import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// 录制引擎：ScreenCaptureKit 采集（屏幕帧 + 系统声音）→ AVAssetWriter 编码 MP4（H.264 + AAC）。
/// - 暂停语义：停止向 writer 追加 sample 但保留 stream；恢复后继续追加，
///   文件时间轴出现跳变（跳剪效果），v1 可接受。
/// - 麦克风：AVAudioEngine input tap → 手工打包 CMSampleBuffer 追加到独立 AAC input；
///   时间同步策略：以最近一帧屏幕视频的 PTS 为锚（视频 PTS 与宿主机钟同速率、未知常量偏移），
///   麦克风 buffer 的 hostTime 经 mach timebase 换算为宿主机钟 CMTime 后加偏移 Δ。
final class RecordingEngine: NSObject {

    // MARK: - 错误与参数

    enum EngineError: LocalizedError {
        case screenPermissionDenied
        case displayNotFound
        case noVideoFrames
        case cancelled
        case micUnavailable

        var errorDescription: String? {
            switch self {
            case .screenPermissionDenied: return "未授予屏幕录制权限，请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许"
            case .displayNotFound: return "未找到目标显示器"
            case .noVideoFrames: return "未捕获到任何画面"
            case .cancelled: return "录制已取消"
            case .micUnavailable: return "麦克风不可用"
            }
        }
    }

    struct StartParams {
        let displayID: CGDirectDisplayID
        /// SCKit sourceRect（点，显示器左上原点）
        let sourceRectPoints: CGRect
        /// 输出视频像素尺寸（偶数）
        let outputPixelSize: CGSize
        let frameRate: Int
        let systemAudioEnabled: Bool
        let microphoneEnabled: Bool
        let outputURL: URL
    }

    // MARK: - 回调（主线程）

    /// 结束回调：success = 成品文件 URL；failure = 失败/取消。
    var onFinished: ((Result<URL, Error>) -> Void)?
    /// 首帧写入回调（可用于 UI 确认真正开录）。
    var onFirstFrameWritten: (() -> Void)?

    // MARK: - 状态

    private var params: StartParams?
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var audioEngine: AVAudioEngine?
    /// 麦克风 tap 实际采样格式（引擎成功启动后才有值）；writer 须在 startWriting 前按它预建 input。
    private var micTapFormat: AVAudioFormat?

    /// 锁保护的可变状态（stream/mic 回调队列与主线程并发访问）。
    private let stateLock = NSLock()
    private var isPaused = false
    private var isFinishing = false
    private var sessionStarted = false
    private var didReportFirstFrame = false
    /// 麦克风时间锚：最近一帧视频的 (PTS, 宿主机钟时刻)。
    private var anchorVideoPTS = CMTime.invalid
    private var anchorHostTime = CMTime.invalid
    private var machTimebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    private var droppedVideoFrames = 0
    private var pendingError: Error?
    private var finishReported = false

    /// 追加串行队列（video/audio/mic 的 append 全部经此排序）。
    private let writerQueue = DispatchQueue(label: "com.zp.mac-tool-pro.recording.append")

    // MARK: - 生命周期

    /// 启动采集与写入。异步完成；失败经 onFinished(.failure) 上报。
    func start(_ params: StartParams) {
        self.params = params
        DiagLog.write("RecordingEngine.start: rect=\(params.sourceRectPoints) size=\(params.outputPixelSize) fps=\(params.frameRate) sysAudio=\(params.systemAudioEnabled) mic=\(params.microphoneEnabled)")

        // 残留临时文件清理（AVAssetWriter 要求目标文件不存在）
        try? FileManager.default.removeItem(at: params.outputURL)

        guard CGPreflightScreenCaptureAccess() else {
            DiagLog.write("RecordingEngine.start: screen permission denied")
            report(.failure(EngineError.screenPermissionDenied))
            return
        }

        Task { [weak self] in
            await self?.setupAndStart(params)
        }
    }

    private func setupAndStart(_ params: StartParams) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == params.displayID }) else {
                throw EngineError.displayNotFound
            }
            // 排除自身窗口（红色边框、悬浮控制条等），避免被录进视频
            let ownWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            DiagLog.write("RecordingEngine: excluding \(ownWindows.count) own window(s)")

            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            // 麦克风先于 writer 启动：writer 需要在 startWriting 前按实际采样格式建好全部 input
            //（AVAssetWriter 运行中 add(input:) 会抛异常，音频 buffer 又只在 sessionStarted 后到达）
            if params.microphoneEnabled {
                startMicrophone()
            }
            // 先建 writer（含全部音频 input，首帧到达即可追加），失败直接上报
            guard self.makeWriter(params: params) != nil else {
                throw EngineError.noVideoFrames
            }
            let scConfig = SCStreamConfiguration()
            scConfig.width = Int(params.outputPixelSize.width)
            scConfig.height = Int(params.outputPixelSize.height)
            scConfig.sourceRect = params.sourceRectPoints
            scConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(params.frameRate))
            scConfig.queueDepth = 8
            scConfig.showsCursor = true
            scConfig.capturesAudio = params.systemAudioEnabled
            if params.systemAudioEnabled {
                scConfig.sampleRate = 48000
                scConfig.channelCount = 2
            }

            let stream = SCStream(filter: filter, configuration: scConfig, delegate: self)
            self.stream = stream
            let outputQueue = DispatchQueue(label: "com.zp.mac-tool-pro.recording.stream")
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            if params.systemAudioEnabled {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            }
            try await stream.startCapture()
            DiagLog.write("RecordingEngine: capture started")
        } catch {
            DiagLog.write("RecordingEngine.start failed: \(error)")
            stopMicrophone()
            stream = nil
            report(.failure(error))
        }
    }

    /// 暂停：停止向 writer 追加 sample（stream 保持运行）。
    func pause() {
        stateLock.lock()
        let changed = !isPaused
        isPaused = true
        stateLock.unlock()
        if changed { DiagLog.write("RecordingEngine.pause") }
    }

    /// 恢复：继续追加（文件时间轴出现跳变 = 跳剪）。
    func resume() {
        stateLock.lock()
        let changed = isPaused
        isPaused = false
        stateLock.unlock()
        if changed { DiagLog.write("RecordingEngine.resume") }
    }

    /// 停止并收尾。discard = true 时删除成品（取消录制）。
    func finish(discard: Bool) {
        stateLock.lock()
        guard !isFinishing else {
            stateLock.unlock()
            return
        }
        isFinishing = true
        isPaused = true
        stateLock.unlock()
        DiagLog.write("RecordingEngine.finish(discard=\(discard)) droppedVideo=\(droppedVideoFrames)")

        stopMicrophone()
        let stream = self.stream
        self.stream = nil
        Task { [weak self] in
            try? await stream?.stopCapture()
            await MainActor.run {
                self?.finalizeWriter(discard: discard)
            }
        }
    }

    // MARK: - Writer 收尾

    private func finalizeWriter(discard: Bool) {
        guard let params = params else { return }
        let outputURL = params.outputURL
        guard !discard else {
            try? FileManager.default.removeItem(at: outputURL)
            report(.failure(EngineError.cancelled))
            return
        }
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let started = self.sessionStarted
            let writer = self.writer
            let videoInput = self.videoInput
            let systemAudioInput = self.systemAudioInput
            let micInput = self.micInput
            let pendingError = self.pendingError
            self.stateLock.unlock()

            guard started, let writer = writer else {
                // 从未写入任何帧（例如权限瞬间被吊销）
                try? FileManager.default.removeItem(at: outputURL)
                self.report(.failure(pendingError ?? EngineError.noVideoFrames))
                return
            }
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            micInput?.markAsFinished()
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                let status = writer.status
                let writerError = writer.error
                DiagLog.write("RecordingEngine.writer finished: status=\(status.rawValue) error=\(writerError.map(String.init(describing:)) ?? "nil")")
                if status == .completed {
                    self.report(.success(outputURL))
                } else {
                    try? FileManager.default.removeItem(at: outputURL)
                    self.report(.failure(writerError ?? pendingError ?? EngineError.noVideoFrames))
                }
            }
        }
    }

    /// 上报结束结果（主线程，仅一次）。
    private func report(_ result: Result<URL, Error>) {
        stateLock.lock()
        let already = finishReported
        finishReported = true
        stateLock.unlock()
        guard !already else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFinished?(result)
            self?.onFinished = nil
        }
    }

    // MARK: - 采样处理（stream 输出队列回调）

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        // 过滤未完成帧（SCK 会投递 blank/idle 状态帧）
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 更新麦克风时间锚（无论是否暂停都更新，保证恢复后锚点新鲜）
        let nowHost = CMClockGetTime(CMClockGetHostTimeClock())
        stateLock.lock()
        anchorVideoPTS = pts
        anchorHostTime = nowHost
        stateLock.unlock()

        stateLock.lock()
        if isPaused || isFinishing { stateLock.unlock(); return }
        stateLock.unlock()

        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let writer = self.writer
            let videoInput = self.videoInput
            let started = self.sessionStarted
            self.stateLock.unlock()
            guard let writer = writer, let videoInput = videoInput else { return }

            if !started {
                writer.startWriting()
                writer.startSession(atSourceTime: pts)
                self.stateLock.lock()
                self.sessionStarted = true
                let first = !self.didReportFirstFrame
                self.didReportFirstFrame = true
                self.stateLock.unlock()
                DiagLog.write("RecordingEngine: writer session started at \(pts.seconds)")
                if first {
                    DispatchQueue.main.async { self.onFirstFrameWritten?() }
                }
            }
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            } else {
                self.droppedVideoFrames += 1
                if self.droppedVideoFrames % 30 == 1 {
                    DiagLog.write("RecordingEngine: video input busy, dropped total=\(self.droppedVideoFrames)")
                }
            }
        }
    }

    private func handleSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        stateLock.lock()
        if isPaused || isFinishing || !sessionStarted { stateLock.unlock(); return }
        stateLock.unlock()

        writerQueue.async { [weak self] in
            guard let self = self else { return }
            // input 已在 makeWriter 阶段（startWriting 前）创建；此处为 nil 说明配置异常，静默丢弃
            guard let audioInput = self.systemAudioInput else { return }
            if audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        }
    }

    // MARK: - 麦克风（AVAudioEngine input tap）

    private func startMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            DiagLog.write("RecordingEngine: mic not authorized (status=\(status.rawValue)), recording continues without mic")
            return
        }
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
            DiagLog.write("RecordingEngine: mic input format unavailable, skip mic")
            return
        }
        // 强制交错的 Float32 格式：payload 连续，便于打包单个 CMBlockBuffer
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hwFormat.sampleRate,
            channels: hwFormat.channelCount,
            interleaved: true
        ) ?? hwFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, when in
            self?.handleMicBuffer(buffer, hostTime: when.hostTime)
        }
        engine.prepare()
        do {
            try engine.start()
            audioEngine = engine
            micTapFormat = tapFormat
            DiagLog.write("RecordingEngine: mic tap started rate=\(tapFormat.sampleRate) ch=\(tapFormat.channelCount)")
        } catch {
            DiagLog.write("RecordingEngine: mic engine start failed: \(error)")
        }
    }

    private func stopMicrophone() {
        guard let engine = audioEngine else { return }
        audioEngine = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        DiagLog.write("RecordingEngine: mic stopped")
    }

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        stateLock.lock()
        if isPaused || isFinishing || !sessionStarted {
            stateLock.unlock()
            return
        }
        let anchorPTS = anchorVideoPTS
        let anchorHost = anchorHostTime
        stateLock.unlock()

        // 首帧视频未到（锚点未建立）时丢弃，通常 < 100ms
        guard anchorPTS.isValid, anchorHost.isValid else { return }

        // hostTime(mach ticks) → 宿主机钟 CMTime（纳秒纪元 = mach_absolute_time）
        let hostNanos = UInt64(Float64(hostTime) * Float64(machTimebase.numer) / Float64(machTimebase.denom))
        let micHostTime = CMTime(value: CMTimeValue(hostNanos), timescale: 1_000_000_000)
        // Δ = 视频PTS - 锚点宿主机钟；micPTS = micHostTime + Δ（同速率、常量偏移）
        let delta = CMTimeSubtract(anchorPTS, anchorHost)
        let pts = CMTimeAdd(micHostTime, delta)
        guard pts.seconds.isFinite else { return }

        writerQueue.async { [weak self] in
            guard let self = self else { return }
            // input 已在 makeWriter 阶段（startWriting 前）按 micTapFormat 预创建
            guard let micInput = self.micInput else { return }
            guard micInput.isReadyForMoreMediaData,
                  let sampleBuffer = Self.makeCMSampleBuffer(from: buffer, pts: pts) else { return }
            micInput.append(sampleBuffer)
        }
    }

    // MARK: - Writer 创建

    private func makeWriter(params: StartParams) -> AVAssetWriter? {
        let width = Int(params.outputPixelSize.width)
        let height = Int(params.outputPixelSize.height)
        // 码率：像素率 × 0.15 bit/px，夹取 [4, 60] Mbps
        let bitrate = min(60_000_000, max(4_000_000, width * height * params.frameRate * 15 / 100))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: params.frameRate * 2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard let writer = try? AVAssetWriter(outputURL: params.outputURL, fileType: .mp4) else {
            DiagLog.write("RecordingEngine: AVAssetWriter init failed at \(params.outputURL.path)")
            return nil
        }
        writer.add(input)
        self.writer = writer
        self.videoInput = input

        // 音频 input 必须在 startWriting 之前全部 add：AVAssetWriter 一旦开始写入，
        // 再 add(input:) 会抛 NSException（曾导致录制数秒后崩溃）。
        // 系统声音按 SCKit 配置固定 48kHz/2ch；麦克风按引擎启动时记录的实际采样格式。
        if params.systemAudioEnabled {
            let sysInput = makeAudioInput(sampleRate: 48000, channels: 2, maxBitrate: 256_000)
            writer.add(sysInput)
            self.systemAudioInput = sysInput
            DiagLog.write("RecordingEngine: system audio input pre-created 48kHz/2ch")
        }
        if params.microphoneEnabled, let format = micTapFormat {
            let micInput = makeAudioInput(
                sampleRate: format.sampleRate,
                channels: Int(format.channelCount),
                maxBitrate: 192_000
            )
            writer.add(micInput)
            self.micInput = micInput
            DiagLog.write("RecordingEngine: mic input pre-created rate=\(format.sampleRate) ch=\(format.channelCount)")
        } else if params.microphoneEnabled {
            DiagLog.write("RecordingEngine: mic enabled but tap format unavailable, recording without mic input")
        }

        DiagLog.write("RecordingEngine: writer ready \(width)x\(height)@\(params.frameRate) bitrate=\(bitrate)")
        return writer
    }

    /// 构造 AAC 编码的音频 writer input（格式固定的场合）。
    private func makeAudioInput(sampleRate: Double, channels: Int, maxBitrate: Int) -> AVAssetWriterInput {
        let ch = max(1, channels)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: ch,
            AVEncoderBitRateKey: min(maxBitrate, max(64_000, 64_000 * ch)),
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    // MARK: - 打包 PCM → CMSampleBuffer

    private static func makeCMSampleBuffer(from buffer: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        var asbd = buffer.format.streamDescription.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var formatDescription: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &formatDescription) == noErr,
              let desc = formatDescription else { return nil }

        // 交错格式下 payload 连续：mBuffers[0] 覆盖全部帧数据
        let audioBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let first = audioBufferList.first, let mData = first.mData else { return nil }
        let payloadSize = Int(asbd.mBytesPerFrame) * frameLength

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payloadSize,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: payloadSize,
            flags: 0, blockBufferOut: &blockBuffer) == noErr,
              let block = blockBuffer else { return nil }
        guard CMBlockBufferReplaceDataBytes(with: mData, blockBuffer: block,
                                            offsetIntoDestination: 0, dataLength: payloadSize) == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        let duration = CMTime(value: CMTimeValue(frameLength), timescale: CMTimeScale(asbd.mSampleRate))
        // PTS 经显式 timing 数组携带（全部 sample 同时长连续，1 条 timing 覆盖整段）
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts,
                                        decodeTimeStamp: CMTime.invalid)
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: desc,
            sampleCount: CMItemCount(frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer) == noErr else { return nil }
        return sampleBuffer
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

extension RecordingEngine: SCStreamOutput, SCStreamDelegate {

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleVideoSample(sampleBuffer)
        case .audio:
            handleSystemAudioSample(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DiagLog.write("RecordingEngine.stream didStopWithError: \(error)")
        stateLock.lock()
        let alreadyFinishing = isFinishing
        if !alreadyFinishing {
            isFinishing = true
            pendingError = error
        }
        stateLock.unlock()
        guard !alreadyFinishing else { return }
        stopMicrophone()
        finalizeWriter(discard: false)
    }
}
