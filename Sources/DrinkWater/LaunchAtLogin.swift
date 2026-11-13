import AppKit
import Foundation
import Intents
import ServiceManagement

/// 登录时自动启动。系统的 `SMAppService` 是唯一真相，不在设置文件里另存一份——
/// 用户可能在「系统设置 › 通用 › 登录项」里关掉，App 得跟着变。
enum LaunchAtLogin {
    /// `swift run` 出来的可执行文件没有 bundle，注册会失败；打包后的 .app 才支持。
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 用户把开关打开了，但还需要在系统设置里手动允许一次。
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 成功返回 nil；失败返回给用户看的理由。
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        guard isSupported else { return t("Only available in the packaged app.") }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 专注模式状态。用系统公开的 Focus Status API（Intents），不读 `DoNotDisturb`
/// 私有数据库——那条路要「完全磁盘访问」，一个喝水提醒没理由要这个权限。
///
/// 未授权或读不到时 `isFocused` 为 nil（未知）：**宁可不禁用提醒，也不误吞**。
final class FocusMonitor: ObservableObject {
    enum Authorization {
        case unknown
        case notDetermined
        case restricted
        case denied
        case authorized
    }

    @Published private(set) var isFocused: Bool?
    @Published private(set) var authorization: Authorization = .unknown

    private var timer: Timer?

    /// 只有「已授权 + 专注确实开着」才算数。
    var isFocusActive: Bool {
        authorization == .authorized && isFocused == true
    }

    var needsPermission: Bool {
        authorization == .notDetermined || authorization == .denied
    }

    /// 20 秒轮询一次：Focus 没有变更通知，API 只能问。
    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let center = INFocusStatusCenter.default
        authorization = Authorization(center.authorizationStatus)
        isFocused = center.focusStatus.isFocused
    }

    /// 第一次打开「专注静音」时才问，不在启动时弹权限框。
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
                completion?(self?.authorization == .authorized)
            }
        }
    }
}

private extension FocusMonitor.Authorization {
    init(_ status: INFocusStatusAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        @unknown default: self = .unknown
        }
    }
}
