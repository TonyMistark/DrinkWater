import Foundation
import Combine

final class Store: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isLoading, settings != oldValue else { return }
            save()
            settingsChanged?()
        }
    }
    @Published private(set) var records: [DrinkRecord] = []
    @Published private(set) var lastActionAt: Date = Date()

    /// 手机推送 / 权限状态等临时提示
    @Published var pushStatus: String?
    @Published var systemNotificationDenied: Bool = false

    /// 设置变化（用于重排提醒计时）
    var settingsChanged: (() -> Void)?

    private let fileURL: URL
    private var isLoading = true

    private struct PersistedState: Codable {
        var settings: AppSettings
        var records: [DrinkRecord]
        var lastActionAt: Date
    }

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DrinkWater", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("state.json")

        var loadedSettings = AppSettings()
        var loadedRecords: [DrinkRecord] = []
        var loadedLastAction = Date()

        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            loadedSettings = state.settings
            loadedRecords = state.records
            loadedLastAction = state.lastActionAt
        }

        // 启动时如果上次喝水已经过去太久（比如隔夜），重新开始计时，
        // 不让 App 一打开就立刻弹提醒。
        let interval = TimeInterval(loadedSettings.intervalMinutes * 60)
        if Date().timeIntervalSince(loadedLastAction) > interval {
            loadedLastAction = Date()
        }

        settings = loadedSettings
        records = loadedRecords
        lastActionAt = loadedLastAction
        isLoading = false

        pruneOldRecords()
    }

    // MARK: - 今日数据

    var todayRecords: [DrinkRecord] {
        records.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todayTotal: Int {
        todayRecords.reduce(0) { $0 + $1.ml }
    }

    var todayCups: Int {
        todayRecords.count
    }

    var cupsGoal: Int {
        max(1, Int(ceil(Double(settings.dailyGoalML) / Double(max(50, settings.cupML)))))
    }

    var progress: Double {
        min(1, Double(todayTotal) / Double(max(1, settings.dailyGoalML)))
    }

    func last7Days() -> [DayTotal] {
        lastDays(7)
    }

    func lastDays(_ count: Int) -> [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let total = records
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.ml }
            return DayTotal(id: day, date: day, total: total)
        }
    }

    // MARK: - 行为

    func drink(ml: Int? = nil) {
        records.append(DrinkRecord(date: Date(), ml: ml ?? settings.cupML))
        lastActionAt = Date()
        save()
    }

    func undoLastDrink() {
        guard let index = records.lastIndex(where: { Calendar.current.isDateInToday($0.date) }) else { return }
        records.remove(at: index)
        save()
    }

    /// 记录列表里按条删除，不限于今天。
    func deleteRecord(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    /// 提醒已发出：把计时基准推到当前时间，下一次按间隔重新算
    func markReminded(at date: Date = Date()) {
        lastActionAt = date
        save()
    }

    // MARK: - 持久化

    private func save() {
        guard !isLoading else { return }
        let state = PersistedState(settings: settings, records: records, lastActionAt: lastActionAt)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func pruneOldRecords() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) else { return }
        let kept = records.filter { $0.date >= cutoff }
        if kept.count != records.count {
            records = kept
            save()
        }
    }
}
