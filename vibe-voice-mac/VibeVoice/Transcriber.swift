import Foundation
import WhisperKit

// WhisperKit 封裝：本地 Core ML 推論，跑在 M1 的 ANE/GPU 上。
// 首次 load() 會自動從 Hugging Face 下載 large-v3-turbo 的 Core ML 模型。
final class Transcriber {
    private var pipe: WhisperKit?

    func load() async {
        do {
            // 模型名會做模糊比對，解析到 turbo 變體。想更省記憶體可改 "base" 先測流程。
            let config = WhisperKitConfig(model: "large-v3-turbo")
            pipe = try await WhisperKit(config)
        } catch {
            NSLog("WhisperKit 載入失敗: \(error)")
        }
    }

    func transcribe(fileURL: URL) async -> String {
        guard let pipe else { return "" }
        do {
            // language: nil → 自動偵測（中英混雜可用）。
            // 想鎖定可改 language: "zh"。
            let options = DecodingOptions(
                task: .transcribe,
                language: nil,
                temperature: 0.0,
                usePrefillPrompt: true
            )
            let results = try await pipe.transcribe(audioPath: fileURL.path, decodeOptions: options)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            return results.map { $0.text }.joined()
        } catch {
            NSLog("辨識失敗: \(error)")
            return ""
        }
    }
}
