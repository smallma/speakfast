import Foundation
import WhisperKit

// WhisperKit 封裝：本地 Core ML 推論，跑在 M1 的 ANE/GPU 上。
// 首次 load() 會自動從 Hugging Face 下載 large-v3-turbo 的 Core ML 模型。
//
// 隱私：辨識全程在本地，唯一的網路行為是「首次下載模型」。
// 本檔刻意「不把辨識出來的文字寫進 log」——避免敏感口述內容落到系統日誌。
//
// 並行安全：WhisperKit 對同一實例不可重入。串流預覽與定稿（甚至跨兩次錄音）
// 都可能搶著呼叫 transcribe，因此用一條「任務鏈」把每次辨識排隊，保證永不重疊。
// 整個類別標 @MainActor：tail 只在主執行緒被改，沒有資料競爭；重運算仍在
// WhisperKit 內部的背景執行緒跑（我們只是 await）。
@MainActor
final class Transcriber {
    private var pipe: WhisperKit?
    private var tail: Task<String, Never> = Task { "" }

    func load() async {
        do {
            // 模型名會做模糊比對，解析到 turbo 變體。想更省記憶體可改 "base" 先測流程。
            let config = WhisperKitConfig(model: "large-v3-turbo")
            pipe = try await WhisperKit(config)
        } catch {
            NSLog("WhisperKit 載入失敗") // 不印 error 細節，保守一點
        }
    }

    var isReady: Bool { pipe != nil }

    // 串流／定稿共用。每次呼叫都排在前一次之後，序列化執行。
    // - filterHallucinations：定稿時才開（短音 + 已知幻覺 → 丟掉）；串流預覽時關，避免閃爍。
    func transcribe(samples: [Float], durationSec: Double, filterHallucinations: Bool) async -> String {
        let previous = tail
        let job = Task { @MainActor [weak self] () -> String in
            _ = await previous.value   // 等前一次辨識做完，保證不重疊
            guard let self else { return "" }
            return await self.run(samples: samples, durationSec: durationSec,
                                  filterHallucinations: filterHallucinations)
        }
        tail = job
        return await job.value
    }

    private func run(samples: [Float], durationSec: Double, filterHallucinations: Bool) async -> String {
        guard let pipe, !samples.isEmpty else { return "" }
        do {
            let options = buildOptions(pipe: pipe)
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if filterHallucinations, durationSec < 1.5 {
                let norm = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if Self.hallucinations.contains(norm) { return "" }
            }
            return text
        } catch {
            NSLog("辨識失敗")
            return ""
        }
    }

    // 熱詞注入：把術語清單用 tokenizer 編成 promptTokens（濾掉特殊 token），
    // 當成解碼前置上下文，提升 useEffect / pnpm 這類技術詞的辨識。
    private func buildOptions(pipe: WhisperKit) -> DecodingOptions {
        var promptTokens: [Int] = []
        if let tokenizer = pipe.tokenizer {
            let begin = tokenizer.specialTokens.specialTokenBegin
            promptTokens = tokenizer.encode(text: " " + Vocabulary.promptText())
                .filter { $0 < begin }
        }
        return DecodingOptions(
            task: .transcribe,
            language: nil,            // 自動偵測，中英混雜可用
            temperature: 0.0,
            usePrefillPrompt: true,
            promptTokens: promptTokens.isEmpty ? nil : promptTokens
        )
    }

    // Whisper 對靜音 / 極短音常吐出的「幻覺」字句；短音時若整段等於這些就丟掉。
    private static let hallucinations: Set<String> = [
        "謝謝", "謝謝大家", "謝謝觀看", "請不吝點贊", "請訂閱", "字幕由", "下次再見",
        "thank you", "thanks for watching", "thank you for watching", "you", "bye",
        "please subscribe", "字幕志愿者",
    ]
}
