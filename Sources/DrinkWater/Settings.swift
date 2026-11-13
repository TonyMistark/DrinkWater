import Foundation

// MARK: - 推送方式

enum PushProvider: String, Codable, CaseIterable, Identifiable {
    case none
    case bark
    case ntfy
    case pushover
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return t("Off")
        case .bark: return "Bark"
        case .ntfy: return "ntfy"
        case .pushover: return "Pushover"
        case .custom: return t("Custom Webhook")
        }
    }

    var hint: String {
        switch self {
        case .none:
            return t("Local reminders only.")
        case .bark:
            return t("Install Bark on iPhone and paste its device key below. When iPhone is locked, notifications mirror to Apple Watch automatically.")
        case .ntfy:
            return t("Install the ntfy app on iPhone and subscribe to the same topic. You can also point this at your own server.")
        case .pushover:
            return t("Create an application on the Pushover website to get a token and user key. Apple Watch is supported.")
        case .custom:
            return t("Use {title} and {body} placeholders in the URL. Works with chat bots, Slack, or your own service.")
        }
    }
}

// MARK: - 设置

struct AppSettings: Codable, Equatable {
    // 提醒节奏
    var enabled: Bool = true
    var intervalMinutes: Int = 45
    var activeStartMinutes: Int = 9 * 60
    var activeEndMinutes: Int = 21 * 60
    var dailyGoalML: Int = 2000
    var cupML: Int = 250

    // Mac 本机通知方式
    var systemBanner: Bool = true
    var reminderPanel: Bool = false
    var fullscreenOverlay: Bool = false
    var soundEnabled: Bool = true
    var soundName: String = "Glass"
    var speechEnabled: Bool = false
    var menuBarPulse: Bool = true

    // 手机 / 手表推送
    var pushProvider: PushProvider = .none
    var barkServer: String = "https://api.day.app"
    var barkKey: String = ""
    var ntfyServer: String = "https://ntfy.sh"
    var ntfyTopic: String = ""
    var pushoverToken: String = ""
    var pushoverUser: String = ""
    var customURL: String = ""
    var customMethod: String = "POST"

    init() {}

    // 逐字段容错解码：以后加字段也不会读崩旧配置文件
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        activeStartMinutes = try c.decodeIfPresent(Int.self, forKey: .activeStartMinutes) ?? d.activeStartMinutes
        activeEndMinutes = try c.decodeIfPresent(Int.self, forKey: .activeEndMinutes) ?? d.activeEndMinutes
        dailyGoalML = try c.decodeIfPresent(Int.self, forKey: .dailyGoalML) ?? d.dailyGoalML
        cupML = try c.decodeIfPresent(Int.self, forKey: .cupML) ?? d.cupML
        systemBanner = try c.decodeIfPresent(Bool.self, forKey: .systemBanner) ?? d.systemBanner
        reminderPanel = try c.decodeIfPresent(Bool.self, forKey: .reminderPanel) ?? d.reminderPanel
        fullscreenOverlay = try c.decodeIfPresent(Bool.self, forKey: .fullscreenOverlay) ?? d.fullscreenOverlay
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? d.soundName
        speechEnabled = try c.decodeIfPresent(Bool.self, forKey: .speechEnabled) ?? d.speechEnabled
        menuBarPulse = try c.decodeIfPresent(Bool.self, forKey: .menuBarPulse) ?? d.menuBarPulse
        pushProvider = try c.decodeIfPresent(PushProvider.self, forKey: .pushProvider) ?? d.pushProvider
        barkServer = try c.decodeIfPresent(String.self, forKey: .barkServer) ?? d.barkServer
        barkKey = try c.decodeIfPresent(String.self, forKey: .barkKey) ?? d.barkKey
        ntfyServer = try c.decodeIfPresent(String.self, forKey: .ntfyServer) ?? d.ntfyServer
        ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? d.ntfyTopic
        pushoverToken = try c.decodeIfPresent(String.self, forKey: .pushoverToken) ?? d.pushoverToken
        pushoverUser = try c.decodeIfPresent(String.self, forKey: .pushoverUser) ?? d.pushoverUser
        customURL = try c.decodeIfPresent(String.self, forKey: .customURL) ?? d.customURL
        customMethod = try c.decodeIfPresent(String.self, forKey: .customMethod) ?? d.customMethod
    }
}

// MARK: - 记录

struct DrinkRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var ml: Int
}

struct DayTotal: Identifiable {
    let id: Date
    let date: Date
    let total: Int
}

// MARK: - 小工具

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TimeText {
    static func minutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    static func countdown(_ seconds: Int) -> String {
        if seconds <= 0 { return t("Reminder imminent") }
        if seconds < 60 { return t("in {}s", seconds) }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? t("in {}m", m) : t("in {}m {}s", m, s)
    }
}
