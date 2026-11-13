import AppKit
import AVFoundation
import UserNotifications

final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let soundNames = [
        "Glass", "Ping", "Purr", "Submarine", "Tink", "Pop",
        "Bottle", "Blow", "Frog", "Funk", "Hero", "Morse", "Sosumi", "Basso"
    ]

    private let store: Store
    private let presenter = ReminderPresenter()
    private let synthesizer = AVSpeechSynthesizer()
    private var pulseTimer: Timer?

    weak var statusButton: NSStatusBarButton?

    var onDrink: (() -> Void)?
    var onSnooze: (() -> Void)?

    private let messages: [(String, String)] = [
        (t("Time for water"), t("Stand up, grab a glass, and give your shoulders a stretch.")),
        (t("Hydration check"), t("A few sips will keep your head clear.")),
        (t("Don't wait until you're thirsty"), t("One glass now makes the rest of the day easier.")),
        (t("Your glass is waiting"), t("Put down what you're doing and take a sip.")),
        (t("Small sips work best"), t("150–250 ml at a time beats one big gulp.")),
        (t("You're almost there"), t("One more glass to get closer to today's goal.")),
        (t("Quick reminder"), t("Sitting still plus dehydration is the fastest way to feel sleepy."))
    ]

    init(store: Store) {
        self.store = store
        super.init()
        presenter.onDrink = { [weak self] in self?.onDrink?() }
        presenter.onSnooze = { [weak self] in self?.onSnooze?() }
    }

    // MARK: - 初始化

    func setUp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let drinkAction = UNNotificationAction(identifier: "WATER_DRINK", title: t("I drank"), options: [])
        let snoozeAction = UNNotificationAction(identifier: "WATER_SNOOZE", title: t("In 10 minutes"), options: [])
        let category = UNNotificationCategory(identifier: "WATER_REMINDER",
                                              actions: [drinkAction, snoozeAction],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.store.systemNotificationDenied = !granted
            }
        }
    }

    func refreshAuthorizationStatus() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.store.systemNotificationDenied = (settings.authorizationStatus == .denied)
            }
        }
    }

    // MARK: - 触发提醒

    func notify(isTest: Bool = false) {
        let settings = store.settings
        let sample = messages.randomElement() ?? (t("Time for water"), t("Stand up, grab a glass, and give your shoulders a stretch."))
        let title = isTest ? t("Water reminder test") : sample.0
        let body = isTest ? t("If you can see this, the notification channel works.") : sample.1
        let progress = t("Today {} / {} ml · {}/{} cups",
                         store.todayTotal,
                         settings.dailyGoalML,
                         store.todayCups,
                         store.cupsGoal)

        let panelOnlyFallback = store.systemNotificationDenied && !settings.reminderPanel && !settings.fullscreenOverlay

        if settings.systemBanner {
            post(title: title, body: "\(body) · \(progress)")
        }
        if settings.reminderPanel || panelOnlyFallback {
            presenter.showPanel(title: title, body: body, progress: progress)
        }
        if settings.fullscreenOverlay {
            presenter.showOverlay(title: title, body: body, progress: progress)
        }
        if settings.soundEnabled {
            playSound()
        }
        if settings.speechEnabled {
            speak(t("{} {} You have had {} ml of water today.", title, body, store.todayTotal))
        }
        if settings.menuBarPulse {
            pulseMenuBar()
        }
        if settings.pushProvider != .none, !isTest {
            sendRemote(title: title, body: "\(body) \(progress)")
        }
    }

    func sendTestPush() {
        guard store.settings.pushProvider != .none else {
            store.pushStatus = t("Choose a push method in Sync first")
            return
        }
        store.pushStatus = t("Sending…")
        RemotePush.send(settings: store.settings,
                        title: t("Water reminder · Test"),
                        body: t("Seeing this on your phone means push is working.")) { [weak self] result in
            switch result {
            case .success(let message):
                self?.store.pushStatus = "✓ " + message
            case .failure(let error):
                self?.store.pushStatus = "✗ " + t("Push failed: {}", error.localizedDescription)
            }
        }
    }

    func previewSound() {
        playSound()
    }

    func dismissWindows() {
        presenter.dismissAll()
    }

    // MARK: - 各通道

    private func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = "WATER_REMINDER"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func playSound() {
        let name = NSSound.Name(store.settings.soundName)
        NSSound(named: name)?.play()
    }

    private func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    private func pulseMenuBar() {
        guard let button = statusButton else { return }
        pulseTimer?.invalidate()

        let filled = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil)
        let outline = NSImage(systemSymbolName: "drop", accessibilityDescription: nil)
        filled?.isTemplate = true
        outline?.isTemplate = true

        var count = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self, weak button] timer in
            guard let button else {
                timer.invalidate()
                return
            }
            count += 1
            button.image = (count % 2 == 0) ? filled : outline
            if count >= 16 {
                timer.invalidate()
                button.image = filled
                self?.pulseTimer = nil
            }
        }
    }

    private func sendRemote(title: String, body: String) {
        RemotePush.send(settings: store.settings, title: title, body: body) { [weak self] result in
            switch result {
            case .success:
                self?.store.pushStatus = t("Synced to phone: {}", title)
            case .failure(let error):
                self?.store.pushStatus = t("Phone push failed: {}", error.localizedDescription)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async { [weak self] in
            switch action {
            case "WATER_DRINK":
                self?.onDrink?()
            case "WATER_SNOOZE":
                self?.onSnooze?()
            default:
                break
            }
            completionHandler()
        }
    }
}
