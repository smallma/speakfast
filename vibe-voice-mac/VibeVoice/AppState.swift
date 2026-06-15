import SwiftUI
import Foundation
import AVFoundation
import ApplicationServices

enum AppStatus {
    case loading, idle, recording, transcribing
    var label: String {
        switch self {
        case .loading: return "載入模型中"
        case .idle: return "閒置（按住 Cmd 說話，左右皆可）"
        case .recording: return "聆聽中…（放開鍵入，Esc 取消）"
        case .transcribing: return "定稿中…"
        }
    }
    var symbolName: String {
        switch self {
        case .loading: return "hourglass"
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .loading
    @Published var modelReady = false

    // 輔助使用（Accessibility）權限：CGEvent 鍵入需要它，否則按鍵被靜默丟棄
    @Published var accessibilityTrusted = AXIsProcessTrusted()

    // 設定（持久化到 UserDefaults）
    @Published var pressEnterAfterPaste: Bool {
        didSet { UserDefaults.standard.set(pressEnterAfterPaste, forKey: "pressEnter") }
    }
    @Published var useDirectTyping: Bool {
        didSet { UserDefaults.standard.set(useDirectTyping, forKey: "directTyping") }
    }

    @Published var hotwordCount = 0

    // 太短的錄音視為誤觸（手滑按一下 Cmd），直接忽略。
    // 0.3s 對「按一下就放」太嚴格 → 一句快話會被整段丟掉。降到 0.2s。
    private let minDurationSec = 0.2
    // 串流預覽的取樣間隔
    private let pollIntervalNs: UInt64 = 400_000_000 // 0.4s

    private let mic = MicStream()
    private let transcriber = Transcriber()
    private let hotkey = HotKeyManager()

    private var pollTask: Task<Void, Never>?
    private var liveText = ""

    init() {
        let d = UserDefaults.standard
        // directTyping 預設 true（安全：不碰剪貼簿）
        pressEnterAfterPaste = d.bool(forKey: "pressEnter")
        useDirectTyping = d.object(forKey: "directTyping") as? Bool ?? true

        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        Task {
            await transcriber.load()
            self.modelReady = true
            self.hotwordCount = Vocabulary.load().count
            if self.status == .loading { self.status = .idle }
        }

        hotkey.onPress = { [weak self] in Task { @MainActor in self?.startRecording() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.stopAndFinalize() } }
        hotkey.onCancel = { [weak self] in Task { @MainActor in self?.cancel() } }
        hotkey.start()

        refreshAccessibilityStatus()
        NSLog("[VibeVoice][Flow] init done · AXIsProcessTrusted=\(accessibilityTrusted)")
    }

    /// 重新查詢輔助使用權限並更新到 menu 的旗標。
    func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        NSLog("[VibeVoice][Flow] accessibilityTrusted=\(trusted)")
    }

    private func startRecording() {
        NSLog("[VibeVoice][Flow] press→startRecording · status=\(status) modelReady=\(modelReady)")
        guard status == .idle, modelReady else {
            NSLog("[VibeVoice][Flow] startRecording SKIPPED (status=\(status), modelReady=\(modelReady))")
            return
        }
        do {
            try mic.start()
        } catch {
            NSLog("[VibeVoice][Flow] mic.start() FAILED: \(error.localizedDescription)")
            return
        }
        status = .recording
        liveText = ""
        HUD.shared.setListening(true)
        HUD.shared.update(text: "")
        HUD.shared.show()
        startPolling()
    }

    // 串流預覽：每隔一段時間就把目前累積的音訊重新辨識，更新 HUD 泡泡。
    // 刻意「不」把字鍵入前景 app——Whisper 串流會修正前文，避免在編輯器裡倒退刪字。
    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollIntervalNs ?? 400_000_000)
                guard let self, !Task.isCancelled else { return }
                let samples = self.mic.samples
                let dur = Double(samples.count) / 16000.0
                if dur < 0.4 { continue }
                let text = await self.transcriber.transcribe(
                    samples: samples, durationSec: dur, filterHallucinations: false
                )
                if Task.isCancelled { return }
                if !text.isEmpty {
                    self.liveText = text
                    HUD.shared.update(text: text)
                    NSLog("[VibeVoice][Flow] poll preview len=\(text.count) dur=\(String(format: "%.2f", dur))s")
                }
            }
        }
    }

    private func cancel() {
        guard status == .recording else { return }
        pollTask?.cancel(); pollTask = nil
        mic.stop()
        HUD.shared.hide()
        status = .idle
    }

    private func stopAndFinalize() {
        guard status == .recording else {
            NSLog("[VibeVoice][Flow] release→finalize SKIPPED (status=\(status), not recording)")
            return
        }
        pollTask?.cancel(); pollTask = nil
        mic.stop()

        let samples = mic.samples
        let dur = Double(samples.count) / 16000.0
        NSLog("[VibeVoice][Flow] release→finalize · dur=\(String(format: "%.3f", dur))s samples=\(samples.count)")

        // 誤觸保護：太短直接丟
        if dur < minDurationSec {
            NSLog("[VibeVoice][Flow] recording DISCARDED — too short (dur=\(String(format: "%.3f", dur))s < min=\(minDurationSec)s). 提示：請『按住』Command 說完整句再放開，不要點一下就放。")
            HUD.shared.hide()
            status = .idle
            return
        }

        status = .transcribing
        HUD.shared.setListening(false)
        HUD.shared.update(text: liveText)

        Task {
            // 定稿：對完整音訊再跑一次（最完整、最準），並套用幻覺過濾
            let text = await transcriber.transcribe(
                samples: samples, durationSec: dur, filterHallucinations: true
            )
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("[VibeVoice][Flow] finalize done · finalLen=\(clean.count) dur=\(String(format: "%.3f", dur))s")

            // 每次定稿前重新確認權限（使用者可能剛在系統設定打開）
            refreshAccessibilityStatus()

            if clean.isEmpty {
                NSLog("[VibeVoice][Flow] insert SKIPPED — empty transcription (模型未辨識到內容)")
            } else if !accessibilityTrusted {
                NSLog("[VibeVoice][Flow] insert called BUT 輔助使用權限未授權 — 按鍵會被靜默丟棄，文字不會出現。請到 系統設定→隱私權與安全性→輔助使用 授權 VibeVoice。len=\(clean.count)")
                TextInserter.insert(
                    clean,
                    mode: useDirectTyping ? .directType : .clipboardPaste,
                    pressEnter: pressEnterAfterPaste
                )
            } else {
                NSLog("[VibeVoice][Flow] insert called · len=\(clean.count) mode=\(useDirectTyping ? "directType" : "clipboardPaste")")
                TextInserter.insert(
                    clean,
                    mode: useDirectTyping ? .directType : .clipboardPaste,
                    pressEnter: pressEnterAfterPaste
                )
            }
            HUD.shared.hide()
            self.status = .idle
        }
    }
}
