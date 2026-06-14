import AVFoundation

// 用 AVAudioRecorder 直接錄成 16kHz / mono / 16-bit PCM WAV，
// 正好是 Whisper 要的格式，WhisperKit 載入時不必再重採樣。
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

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
        } catch {
            NSLog("AudioRecorder 啟動失敗: \(error)")
        }
    }

    // 停止並回傳錄好的檔案；沒錄到東西回 nil
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentURL
    }
}
