import AVFoundation

// 用 AVAudioRecorder 直接錄成 16kHz / mono / 16-bit PCM WAV，
// 正好是 Whisper 要的格式，WhisperKit 載入時不必再重採樣。
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var startedAt: Date?

    func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibevoice-\(UUID().uuidString).wav")
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            startedAt = Date()
        } catch {
            NSLog("AudioRecorder 啟動失敗")
        }
    }

    // 停止並回傳（檔案, 錄音長度秒）；沒錄到回 nil
    func stop() -> (url: URL, duration: Double)? {
        recorder?.stop()
        recorder = nil
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        guard let url = currentURL else { return nil }
        return (url, duration)
    }

    // 取消：停止並刪掉暫存檔（Esc 取消用）
    func cancel() {
        recorder?.stop()
        recorder = nil
        startedAt = nil
        if let url = currentURL { try? FileManager.default.removeItem(at: url) }
        currentURL = nil
    }
}
