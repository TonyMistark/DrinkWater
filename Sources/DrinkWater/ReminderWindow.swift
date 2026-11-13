import AppKit
import SwiftUI

/// 无边框窗口默认不能成为 key window，按钮点击会没反应
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 提醒卡片

struct ReminderCard: View {
    let title: String
    let message: String
    let progressText: String
    var fullScreen: Bool = false
    let onDrink: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        ZStack {
            if fullScreen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
            }

            VStack(spacing: fullScreen ? 20 : 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: fullScreen ? 62 : 34, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: fullScreen ? 30 : 17, weight: .semibold, design: .rounded))
                    Text(message)
                        .font(fullScreen ? .title3 : .callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
                    Button(t("Snooze 10 min")) { onSnooze() }
                        .buttonStyle(.bordered)
                    Button(t("I drank")) { onDrink() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                }
                .controlSize(fullScreen ? .large : .regular)
            }
            .padding(fullScreen ? 44 : 22)
            .frame(maxWidth: fullScreen ? 540 : nil)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
            )
            .padding(fullScreen ? 40 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 窗口展示

final class ReminderPresenter {
    private var panel: NSWindow?
    private var overlay: NSWindow?
    private var autoCloseTimer: Timer?

    var onDrink: (() -> Void)?
    var onSnooze: (() -> Void)?

    func showPanel(title: String, body: String, progress: String) {
        closeOverlay()

        let width: CGFloat = 400
        let height: CGFloat = 268
        let window = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        let hosting = NSHostingController(rootView: card(title: title, body: body, progress: progress, fullScreen: false))
        // 不让 SwiftUI 反推窗口尺寸，窗口大小以这里为准
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        // 不抢焦点，避免打断正在打字的用户
        window.orderFrontRegardless()

        panel?.orderOut(nil)
        panel = window
        scheduleAutoClose(60)
    }

    func showOverlay(title: String, body: String, progress: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        closeOverlay()
        let window = KeyableWindow(contentRect: screen.frame,
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = NSHostingController(rootView: card(title: title, body: body, progress: progress, fullScreen: true))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        overlay = window
        scheduleAutoClose(45)
    }

    func dismissAll() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        panel?.orderOut(nil)
        panel = nil
        closeOverlay()
    }

    // MARK: - 私有

    private func closeOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func card(title: String, body: String, progress: String, fullScreen: Bool) -> some View {
        ReminderCard(title: title,
                     message: body,
                     progressText: progress,
                     fullScreen: fullScreen,
                     onDrink: { [weak self] in self?.onDrink?() },
                     onSnooze: { [weak self] in self?.onSnooze?() })
    }

    private func scheduleAutoClose(_ seconds: TimeInterval) {
        autoCloseTimer?.invalidate()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismissAll()
        }
    }
}
