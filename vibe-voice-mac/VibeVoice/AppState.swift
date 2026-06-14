import SwiftUI
import AVFoundation

enum AppStatus {
    case loading, idle, recording, transcribing
    var label: String {
        switch self {
        case .loading: return "載入模型中"
        case .idle: return "閒置（按住右 Cmd 說話）"
        case .recording: return "錄音中…（放開辨識，Esc 取消）"
        case .transcribing: return "辨識中…"
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

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkey = HotKeyManager()

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
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.stopAndTranscribe() } }
        hotkey.onCancel = { [weak self] in Task { @MainActor in self?.cancel() } }
        hotkey.start()
    }

    private func startRecording() {
        guard status == .idle, modelReady else { return }
        status = .recording
        recorder.start()
    }

    private func cancel() {
        guard status == .recording else { return }
        recorder.cancel()
        status = .idle
    }

    private func stopAndTranscribe() {
        guard status == .recording else { return }
        guard let (url, duration) = recorder.stop() else { status = .idle; return }

        // 誤觸保護：太短直接丟，連模型都不跑
        if duration < minDurationSec {
            try? FileManager.default.removeItem(at: url)
            status = .idle
            return
        }

        status = .transcribing
        Task {
            let text = await transcriber.transcribe(fileURL: url, durationSec: duration)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                TextInserter.insert(
                    clean,
                    mode: useDirectTyping ? .directType : .clipboardPaste,
                    pressEnter: pressEnterAfterPaste
                )
            }
            self.status = .idle
        }
    }
}
