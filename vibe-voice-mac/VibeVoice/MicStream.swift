import Foundation
import WhisperKit

// 即時麥克風串流：用 WhisperKit 的 AudioProcessor 邊錄邊累積 16kHz mono Float 樣本。
// 每次錄音建立一個全新的 AudioProcessor，確保樣本緩衝是乾淨的（不沾上一段）。
final class MicStream {
    private var processor: AudioProcessor?

    func start() throws {
        let p = AudioProcessor()
        try p.startRecordingLive(inputDeviceID: nil, callback: nil)
        processor = p
    }

    func stop() {
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
