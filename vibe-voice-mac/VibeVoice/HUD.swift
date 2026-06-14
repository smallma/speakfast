import AppKit
import SwiftUI
import Combine

// 螢幕下方的浮動預覽泡泡：講話時即時顯示辨識中的文字（不碰你的編輯器）。
// 用 NSPanel + .nonactivatingPanel：顯示時不會搶走前景 app 的焦點，
// 所以你按住右 Cmd 對著編輯器講話時，焦點仍在編輯器，放開才鍵入。
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private let model = HUDModel()

    func show() {
        if panel == nil { build() }
        reposition()
        panel?.orderFrontRegardless()
    }

    func update(text: String) { model.text = text }
    func setListening(_ on: Bool) { model.listening = on }

    func hide() { panel?.orderOut(nil) }

    private func build() {
        let hosting = NSHostingView(rootView: HUDView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 72),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w: CGFloat = 460
        let h: CGFloat = 72
        panel.setFrame(
            NSRect(x: f.midX - w / 2, y: f.minY + 90, width: w, height: h),
            display: true
        )
    }
}

final class HUDModel: ObservableObject {
    @Published var text: String = ""
    @Published var listening: Bool = true
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.listening ? "waveform" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.listening ? .red : .green)
            Text(displayText)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(6)
    }

    private var displayText: String {
        if model.text.isEmpty {
            return model.listening ? "聆聽中…" : "辨識中…"
        }
        return model.text
    }
}
