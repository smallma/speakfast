import Foundation
import WhisperKit

// WhisperKit 封裝：本地 Core ML 推論，跑在 M1 的 ANE/GPU 上。
// 首次 load() 會自動從 Hugging Face 下載 large-v3-turbo 的 Core ML 模型。
//
// 隱私：辨識全程在本地，唯一的網路行為是「首次下載模型」。
// 本檔刻意「不把辨識出來的文字寫進 log」——避免敏感口述內容落到系統日誌。
final class Transcriber {
    private var pipe: WhisperKit?

    // Whisper 對靜音 / 極短音常吐出的「幻覺」字句；短音時若整段等於這些就丟掉。
    private static let hallucinations: Set<String> = [
        "謝謝", "謝謝大家", "謝謝觀看", "請不吝點贊", "請訂閱", "字幕由", "下次再見",
        "thank you", "thanks for watching", "thank you for watching", "you", "bye",
        "please subscribe", "字幕志愿者",
    ]

    func load() async {
        do {
            // 模型名會做模糊比對，解析到 turbo 變體。想更省記憶體可改 "base" 先測流程。
            let config = WhisperKitConfig(model: "large-v3-turbo")
            pipe = try await WhisperKit(config)
        } catch {
            NSLog("WhisperKit 載入失敗") // 不印 error 細節，保守一點
        }
    }

    // duration：這次錄音長度（秒），用來判斷是否該套用幻覺過濾。
    func transcribe(fileURL: URL, durationSec: Double) async -> String {
        defer { try? FileManager.default.removeItem(at: fileURL) } // 保證刪掉暫存錄音
        guard let pipe else { return "" }
        do {
            // 熱詞注入：把術語清單用 tokenizer 編成 promptTokens（濾掉特殊 token），
            // 當成解碼前置上下文，提升 useEffect / pnpm 這類技術詞的辨識。
            var promptTokens: [Int] = []
            if let tokenizer = pipe.tokenizer {
                let begin = tokenizer.specialTokens.specialTokenBegin
                promptTokens = tokenizer.encode(text: " " + Vocabulary.promptText())
                    .filter { $0 < begin }
            }

            let options = DecodingOptions(
                task: .transcribe,
                language: nil,            // 自動偵測，中英混雜可用
                temperature: 0.0,
                usePrefillPrompt: true,
                promptTokens: promptTokens.isEmpty ? nil : promptTokens
            )
            let results = try await pipe.transcribe(audioPath: fileURL.path, decodeOptions: options)
            let text = results.map { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 幻覺過濾：很短的錄音 + 輸出剛好是已知幻覺字句 → 視為雜訊丟掉
            if durationSec < 1.5 {
                let norm = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if Self.hallucinations.contains(norm) { return "" }
            }
            return text
        } catch {
            NSLog("辨識失敗")
            return ""
        }
    }
}
