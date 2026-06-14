import SwiftUI
import AVFoundation

enum AppStatus {
    case loading, idle, recording, transcribing
    var label: String {
        switch self {
        case .loading: return "載入模型中"
        case .idle: return "閒置（按住右 Cmd 說話）"
        case .recording: return "錄音中…"
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
    @Published var lastText: String = ""
    @Published var modelReady = false
    @Published var pressEnterAfterPaste = false

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkey = HotKeyManager()

    init() {
        // 1) 請求麥克風權限
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // 2) 背景載入 WhisperKit 模型（首次會自動下載 Core ML 模型，約幾百 MB）
        Task {
            await transcriber.load()
            self.modelReady = true
            if self.status == .loading { self.status = .idle }
        }

        // 3) push-to-talk：按住右 Cmd 開始錄音，放開停止並辨識
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndTranscribe() }
        hotkey.start()
    }

    private func startRecording() {
        guard status == .idle, modelReady else { return }
        status = .recording
        recorder.start()
    }

    private func stopAndTranscribe() {
        guard status == .recording else { return }
        status = .transcribing
        guard let url = recorder.stop() else { status = .idle; return }

        Task {
            let text = await transcriber.transcribe(fileURL: url)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                self.lastText = clean
                Paster.paste(clean, pressEnter: self.pressEnterAfterPaste)
            }
            self.status = .idle
        }
    }
}
