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

    // 最近一次 load() 的錯誤訊息（成功則為 nil）。UI 可讀取顯示。
    private(set) var lastError: String?

    // 是否把熱詞清單注入成 prompt token。熱詞都是英文，注入英文 prompt 可能
    // 把自動語言偵測往英文拉、進而壓抑中文輸出，因此預設關閉以保護中文辨識。
    var injectHotwordPrompt: Bool = false

    func load() async {
        // 先試主模型，失敗再退回較小、較穩、下載快的 "base"，讓 App 至少能動。
        if await tryLoad(model: "large-v3-turbo") { return }
        NSLog("[VibeVoice][ASR] large-v3-turbo load failed, falling back to base")
        _ = await tryLoad(model: "base")
    }

    // 嘗試載入指定模型；成功回 true 並清空 lastError，失敗回 false 並記錄錯誤。
    private func tryLoad(model: String) async -> Bool {
        do {
            let config = WhisperKitConfig(model: model)
            pipe = try await WhisperKit(config)
            lastError = nil
            NSLog("[VibeVoice][ASR] load OK model=\(model)")
            return true
        } catch {
            let msg = "\(error)"
            lastError = msg
            // 印出確切錯誤（這是載入錯誤，不含使用者口述內容，可安全記錄）。
            NSLog("[VibeVoice][ASR] load FAILED model=\(model) error=\(msg)")
            return false
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
        guard let pipe else {
            NSLog("[VibeVoice][ASR] transcribe skipped: pipe is nil (model not loaded)")
            return ""
        }
        guard !samples.isEmpty else {
            NSLog("[VibeVoice][ASR] transcribe skipped: 0 input samples")
            return ""
        }
        NSLog("[VibeVoice][ASR] transcribe start inputSamples=\(samples.count) durationSec=\(String(format: "%.2f", durationSec))")
        do {
            let options = buildOptions(pipe: pipe)
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map { $0.text }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 只記錄輸出長度，不記錄實際辨識內容（隱私）。
            NSLog("[VibeVoice][ASR] transcribe done outputLength=\(text.count)")

            // 幻覺過濾：只在「極短音(<1.0s)」且「整段文字精確等於」已知幻覺時才丟。
            // 用精確比對（不再做 lowercased/去標點的模糊正規化），避免誤刪真實的短中文。
            if filterHallucinations, durationSec < 1.0 {
                if Self.hallucinations.contains(text) {
                    NSLog("[VibeVoice][ASR] dropped exact hallucination match (len=\(text.count))")
                    return ""
                }
            }
            return text
        } catch {
            // 載入/推論錯誤不含使用者內容，可安全記錄確切錯誤。
            NSLog("[VibeVoice][ASR] transcribe error=\(error)")
            return ""
        }
    }

    // 熱詞注入：把術語清單用 tokenizer 編成 promptTokens（濾掉特殊 token），
    // 當成解碼前置上下文，提升 useEffect / pnpm 這類技術詞的辨識。
    private func buildOptions(pipe: WhisperKit) -> DecodingOptions {
        var promptTokens: [Int] = []
        // 預設不注入英文熱詞 prompt，以免把語言偵測拉向英文、壓抑中文輸出。
        // 需要技術詞強化時可由呼叫端開啟 injectHotwordPrompt。
        if injectHotwordPrompt, let tokenizer = pipe.tokenizer {
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
