import XCTest

/// TDD: 录屏配置 - 默认值（系统声音开/麦克风关/30fps）、Codable 往返、UserDefaults 持久化。
final class RecordingConfigTests: XCTestCase {

    func test_defaultConfig_systemAudioOn_micOff_30fps() {
        let config = RecordingConfig()
        XCTAssertTrue(config.systemAudioEnabled, "系统声音默认开")
        XCTAssertFalse(config.microphoneEnabled, "麦克风默认关")
        XCTAssertEqual(config.frameRate, .fps30, "默认 30fps")
    }

    func test_defaultSaveDirectory_moviesRecordings() {
        XCTAssertTrue(RecordingConfig.defaultSaveDirectory.path.hasSuffix("Movies/Recordings"))
    }

    func test_codableRoundTrip() throws {
        var config = RecordingConfig()
        config.systemAudioEnabled = false
        config.microphoneEnabled = true
        config.frameRate = .fps60
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(RecordingConfig.self, from: data)
        XCTAssertEqual(back, config)
    }

    func test_frameRateCaseIterable_has30And60() {
        XCTAssertEqual(RecordingFrameRate.allCases, [.fps30, .fps60])
        XCTAssertEqual(RecordingFrameRate.fps30.rawValue, 30)
        XCTAssertEqual(RecordingFrameRate.fps60.rawValue, 60)
    }

    func test_store_roundTrip_withInjectedDefaults() {
        let suite = "RecordingConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RecordingConfigStore(defaults: defaults)
        XCTAssertEqual(store.load(), RecordingConfig(), "无持久化数据时返回默认配置")

        var config = RecordingConfig()
        config.microphoneEnabled = true
        config.frameRate = .fps60
        store.save(config)

        let reloaded = RecordingConfigStore(defaults: defaults).load()
        XCTAssertEqual(reloaded, config)
    }

    func test_store_corruptedData_fallsBackToDefault() {
        let suite = "RecordingConfigTests.Corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "recordingConfig")
        let store = RecordingConfigStore(defaults: defaults)
        XCTAssertEqual(store.load(), RecordingConfig())
    }
}
