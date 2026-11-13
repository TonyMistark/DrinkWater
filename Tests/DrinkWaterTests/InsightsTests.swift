import Foundation
import Testing

@testable import DrinkWater

/// 统计口径是报表的地基：平均、达标、连续达标、时段都错一位，用户看到的
/// 就是假数字。这里固定日历与时区，避免跟着机器跑。
@Suite("喝水统计")
struct InsightsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        return c
    }

    /// 2026-11-13 23:00 GMT——放在当天末尾，当天的记录都算「已经发生」
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 23))!
    }

    private func record(daysAgo: Int, hour: Int, ml: Int) -> DrinkRecord {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let date = calendar.date(byAdding: .hour, value: hour, to: day)!
        return DrinkRecord(date: date, ml: ml)
    }

    @Test("有记录的天才算进日均；达标天数与连续达标分开数")
    func averagesAndStreak() {
        var settings = AppSettings()
        settings.dailyGoalML = 2000

        let records = [
            record(daysAgo: 0, hour: 9, ml: 1000),
            record(daysAgo: 0, hour: 15, ml: 1000),   // 今天 2000，达标
            record(daysAgo: 1, hour: 10, ml: 2000),   // 昨天达标
            record(daysAgo: 2, hour: 10, ml: 1500),   // 未达标，连续中断
            record(daysAgo: 3, hour: 11, ml: 2000)    // 达标
        ]

        let stats = DrinkInsights.stats(records: records, settings: settings, days: 30, now: now, calendar: calendar)

        #expect(stats.cups == 5)
        #expect(stats.total == 7500)
        #expect(stats.averageDay == 1875)          // 7500 / 4 个有记录的天
        #expect(stats.goalDays == 3)               // 今天、昨天、三天前
        #expect(stats.streak == 2)                 // 今天 + 昨天
        #expect(stats.averageCup == 1500)
    }

    @Test("今天还没达标不算断：从昨天开始数连续")
    func streakIgnoresUnfinishedToday() {
        var settings = AppSettings()
        settings.dailyGoalML = 1000

        let records = [
            record(daysAgo: 1, hour: 10, ml: 1200),
            record(daysAgo: 2, hour: 10, ml: 1200)
        ]

        let stats = DrinkInsights.stats(records: records, settings: settings, days: 30, now: now, calendar: calendar)
        #expect(stats.streak == 2)
    }

    @Test("最常喝水的两小时窗口：次数最多的那一档")
    func busiestWindow() {
        var settings = AppSettings()
        settings.dailyGoalML = 2000

        let records = [
            record(daysAgo: 0, hour: 14, ml: 250),
            record(daysAgo: 0, hour: 15, ml: 250),
            record(daysAgo: 1, hour: 14, ml: 250),
            record(daysAgo: 1, hour: 9, ml: 250)
        ]

        let stats = DrinkInsights.stats(records: records, settings: settings, days: 7, now: now, calendar: calendar)
        #expect(stats.bestStartHour == 14)
    }

    @Test("一条记录都没有：全为 0，不崩、不瞎算")
    func emptyRecords() {
        let stats = DrinkInsights.stats(records: [], settings: AppSettings(), days: 30, now: now, calendar: calendar)
        #expect(stats.total == 0)
        #expect(stats.cups == 0)
        #expect(stats.averageDay == 0)
        #expect(stats.goalDays == 0)
        #expect(stats.streak == 0)
        #expect(stats.bestStartHour == nil)
    }

    @Test("时段分桶：按四段汇总，总数对得上")
    func timeBuckets() {
        let records = [
            record(daysAgo: 0, hour: 3, ml: 100),
            record(daysAgo: 0, hour: 9, ml: 200),
            record(daysAgo: 0, hour: 14, ml: 300),
            record(daysAgo: 0, hour: 21, ml: 400)
        ]

        let buckets = DrinkInsights.buckets(records: records, days: 7, now: now, calendar: calendar)
        #expect(buckets.map(\.ml) == [100, 200, 300, 400])
        #expect(buckets.reduce(0) { $0 + $1.ml } == 1000)
    }
}
