import Foundation
import WhisperKit

// 即時麥克風串流：用 WhisperKit 的 AudioProcessor 邊錄邊累積 16kHz mono Float 樣本。
// 每次錄音建立一個全新的 AudioProcessor，確保樣本緩衝是乾淨的（不沾上一段）。
final class MicStream {
    private var processor: AudioProcessor?

    func start() throws {
        let p = AudioProcessor()
        // startRecordingLive 真正啟動 AVAudioEngine 並開始往 audioSamples 累積。
        // callback 傳 nil：我們不需要逐塊回呼，只在 stop 時讀整段 audioSamples 快照。
        try p.startRecordingLive(inputDeviceID: nil, callback: nil)
        processor = p
        NSLog("[VibeVoice][ASR] mic start: startRecordingLive returned, initialSamples=\(p.audioSamples.count)")
    }

    func stop() {
        let count = processor?.audioSamples.count ?? 0
        NSLog("[VibeVoice][ASR] mic stop: capturedSamples=\(count) (durationSec=\(String(format: "%.2f", Double(count) / 16000.0)))")
        if count == 0 {
            NSLog("[VibeVoice][ASR] WARNING: 0 samples captured — mic permission denied or capture never started")
        }
        processor?.stopRecording()
    }

    // 目前為止累積的樣本快照（給 Whisper 用的 [Float]，16kHz）。
    var samples: [Float] {
        guard let processor else { return [] }
        return Array(processor.audioSamples)
    }

    // 樣本數 → 秒數（16kHz）
    var durationSec: Double {
        Double(samples.count) / 16000.0
    }
}
