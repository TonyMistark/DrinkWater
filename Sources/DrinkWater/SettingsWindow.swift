import AppKit
import SwiftUI

// MARK: - 设置窗口

/// 菜单栏应用没有 `Settings` 场景，这里自己开一个窗口，
/// 把基础建设那两页（个人信息 / 应用）收进去。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(services: AppServices) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsShell()
            .environmentObject(services.updates)
            .environmentObject(services.installer)
            .environmentObject(services.crashes)
            .environmentObject(services.profile)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let win = NSWindow(contentViewController: hosting)
        win.title = t("Settings")
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 700, height: 480))
        win.center()

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - 设置侧栏

struct SettingsShell: View {
    enum Section: String, CaseIterable, Identifiable {
        case profile
        case app

        var id: String { rawValue }

        var title: String {
            switch self {
            case .profile: return t("Profile")
            case .app: return t("App")
            }
        }

        var icon: String {
            switch self {
            case .profile: return "person.crop.circle"
            case .app: return "gearshape"
            }
        }
    }

    @State private var section: Section = .profile

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch section {
                case .profile: ProfileSettingsView()
                case .app: AppSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .frame(width: 18)
                        Text(item.title)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(section == item ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 168)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}

// MARK: - 崩溃报告窗口

/// 启动时如果账本里还有没看过的报告，把现场摊开给用户看。
@MainActor
final class CrashWindowController {
    static let shared = CrashWindowController()

    private var window: NSWindow?

    func presentIfNeeded(store: CrashStore) {
        guard store.hasPending else { return }
        guard let report = store.pending.first else { return }

        let extraCount = max(0, store.pending.count - 1)
        let root = CrashPanel(
            report: report,
            extraCount: extraCount,
            copy: { store.copyToPasteboard($0) },
            reveal: { store.reveal($0) },
            openIssue: { _ = store.openIssue(for: $0) },
            dismiss: { [weak self] in
                store.markAllSeen()
                self?.close()
            }
        )

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let win = NSWindow(contentViewController: hosting)
        win.title = t("Problem report")
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 760, height: 560))
        win.center()

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
