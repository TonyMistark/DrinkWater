import Foundation
import Combine

// MARK: - 工作时段计算

enum WorkWindow {
    static func contains(minuteOfDay: Int, start: Int, end: Int) -> Bool {
        if start == end { return true }          // 起止相同视为全天
        if start < end { return minuteOfDay >= start && minuteOfDay < end }
        return minuteOfDay >= start || minuteOfDay < end  // 跨零点
    }

    static func nextStart(after date: Date, startMinutes: Int) -> Date {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        guard let startToday = calendar.date(byAdding: .minute, value: startMinutes, to: todayStart) else {
            return date
        }
        if startToday > date { return startToday }
        return calendar.date(byAdding: .day, value: 1, to: startToday) ?? date
    }

    /// 把时间点收拢进工作时段；落在时段外就顺延到下一次开始
    static func clamp(_ date: Date, settings: AppSettings) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if contains(minuteOfDay: minuteOfDay, start: settings.activeStartMinutes, end: settings.activeEndMinutes) {
            return date
        }
        return nextStart(after: date, startMinutes: settings.activeStartMinutes)
    }
}

// MARK: - 调度器

final class ReminderScheduler: ObservableObject {
    @Published private(set) var nextFireAt: Date?
    @Published private(set) var remainingSeconds: Int = 0
    /// 手动「稍后提醒 / 暂停」设置的覆盖时间点
    @Published private(set) var isSnoozed = false

    private let store: Store
    private var timer: Timer?
    private var overrideNext: Date?

    var onFire: (() -> Void)?

    init(store: Store) {
        self.store = store
    }

    func start() {
        recompute()
        timer?.invalidate()
        // .common 模式：菜单弹出、窗口拖动时也照常走
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 喝水 / 跳过之后调用：清掉稍后提醒，重新从当前时间计时
    func afterActivity() {
        overrideNext = nil
        isSnoozed = false
        recompute()
    }

    /// 稍后提醒 / 暂停
    func snooze(minutes: Int) {
        overrideNext = Date().addingTimeInterval(TimeInterval(minutes * 60))
        isSnoozed = true
        recompute()
    }

    func cancelSnooze() {
        afterActivity()
    }

    func recompute(now: Date = Date()) {
        guard store.settings.enabled else {
            nextFireAt = nil
            remainingSeconds = 0
            return
        }

        var candidate: Date
        if let override = overrideNext, override > now {
            candidate = override
        } else {
            overrideNext = nil
            isSnoozed = false
            candidate = store.lastActionAt.addingTimeInterval(TimeInterval(store.settings.intervalMinutes * 60))
            // 睡醒 / 退出重进导致错过时间点：立即补一次
            if candidate < now { candidate = now }
        }

        nextFireAt = WorkWindow.clamp(candidate, settings: store.settings)
        updateCountdown(now: now)
    }

    private func tick() {
        let now = Date()
        if let fire = nextFireAt, now >= fire {
            store.markReminded(at: now)
            overrideNext = nil
            isSnoozed = false
            onFire?()
            recompute(now: now)
        } else {
            updateCountdown(now: now)
        }
    }

    private func updateCountdown(now: Date) {
        guard let fire = nextFireAt else {
            remainingSeconds = 0
            return
        }
        remainingSeconds = max(0, Int(fire.timeIntervalSince(now).rounded()))
    }
}
