import Foundation

/// 录屏帧率档位（v1 仅 30/60）。
public enum RecordingFrameRate: Int, Codable, CaseIterable {
    case fps30 = 30
    case fps60 = 60
}

/// 录屏配置：系统声音开关、麦克风开关、帧率。Codable 便于持久化到用户偏好。
public struct RecordingConfig: Codable, Equatable {
    /// 录制系统声音（ScreenCaptureKit capturesAudio）。默认开。
    public var systemAudioEnabled: Bool
    /// 录制麦克风（AVAudioEngine input tap）。默认关。
    public var microphoneEnabled: Bool
    /// 帧率。默认 30fps。
    public var frameRate: RecordingFrameRate

    public init(
        systemAudioEnabled: Bool = true,
        microphoneEnabled: Bool = false,
        frameRate: RecordingFrameRate = .fps30
    ) {
        self.systemAudioEnabled = systemAudioEnabled
        self.microphoneEnabled = microphoneEnabled
        self.frameRate = frameRate
    }

    /// 默认保存目录：~/Movies/Recordings（不存在时由保存链路创建）。
    public static let defaultSaveDirectory: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        return movies?.appendingPathComponent("Recordings", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }()
}

/// 录屏配置存储：JSON 编码到 UserDefaults，跨启动保留。
public struct RecordingConfigStore {

    static let storageKey = "recordingConfig"

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> RecordingConfig {
        guard let data = defaults.data(forKey: Self.storageKey),
              let config = try? JSONDecoder().decode(RecordingConfig.self, from: data) else {
            return RecordingConfig()
        }
        return config
    }

    public func save(_ config: RecordingConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
