import SwiftUI
import Foundation
import AVFoundation

enum AppStatus {
    case loading, idle, recording, transcribing
    var label: String {
        switch self {
        case .loading: return "載入模型中"
        case .idle: return "閒置（按住右 Cmd 說話）"
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

    // 設定（持久化到 UserDefaults）
    @Published var pressEnterAfterPaste: Bool {
        didSet { UserDefaults.standard.set(pressEnterAfterPaste, forKey: "pressEnter") }
    }
    @Published var useDirectTyping: Bool {
        didSet { UserDefaults.standard.set(useDirectTyping, forKey: "directTyping") }
    }

    @Published var hotwordCount = 0

    // 太短的錄音視為誤觸（手滑按一下右 Cmd），直接忽略
    private let minDurationSec = 0.3
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
    }

    private func startRecording() {
        guard status == .idle, modelReady else { return }
        do {
            try mic.start()
        } catch {
            NSLog("麥克風啟動失敗")
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
        guard status == .recording else { return }
        pollTask?.cancel(); pollTask = nil
        mic.stop()

        let samples = mic.samples
        let dur = Double(samples.count) / 16000.0

        // 誤觸保護：太短直接丟
        if dur < minDurationSec {
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
            if !clean.isEmpty {
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
