import Foundation

/// 一段时间内的喝水统计。纯函数、可注入日历与「现在」，方便测试。
struct DrinkStats {
    let days: Int
    let total: Int
    let cups: Int
    let averageDay: Int      // 有记录的天平均；没记录的天不算
    let goalDays: Int
    let streak: Int          // 当前连续达标天数（今天没达标不算断，从昨天数）
    let averageCup: Int
    let bestStartHour: Int?  // 最常喝水时段的起点（两小时一档）
}

enum DrinkInsights {
    static func stats(
        records: [DrinkRecord],
        settings: AppSettings,
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DrinkStats {
        let goal = max(1, settings.dailyGoalML)
        let today = calendar.startOfDay(for: now)
        let window: [Date] = (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }

        func ml(on day: Date) -> Int {
            records
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.ml }
        }

        let totals = window.map { DayTotal(id: $0, date: $0, total: ml(on: $0)) }
        let total = totals.reduce(0) { $0 + $1.total }
        let activeDays = totals.filter { $0.total > 0 }
        let averageDay = activeDays.isEmpty
            ? 0
            : Int((Double(activeDays.reduce(0) { $0 + $1.total }) / Double(activeDays.count)).rounded())

        let inWindow = records.filter { ($0.date >= (window.first ?? today)) && $0.date <= now }
        let cups = inWindow.count
        let averageCup = cups == 0 ? 0 : Int((Double(total) / Double(cups)).rounded())
        let goalDays = totals.filter { $0.total >= goal }.count

        var streak = 0
        if ml(on: today) >= goal { streak = 1 }
        var offset = 1
        while offset <= days,
              let day = calendar.date(byAdding: .day, value: -offset, to: today),
              ml(on: day) >= goal {
            streak += 1
            offset += 1
        }

        var buckets: [Int: Int] = [:]
        for record in inWindow {
            buckets[calendar.component(.hour, from: record.date) / 2, default: 0] += 1
        }
        let best = buckets.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }

        return DrinkStats(
            days: days,
            total: total,
            cups: cups,
            averageDay: averageDay,
            goalDays: goalDays,
            streak: streak,
            averageCup: averageCup,
            bestStartHour: best.map { $0.key * 2 }
        )
    }

    /// 一段可以直接读、也可以复制的总结。数字都来自 stats，措辞走 t()。
    static func summary(
        records: [DrinkRecord],
        settings: AppSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let goal = max(1, settings.dailyGoalML)
        let todayTotal = records
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.ml }
        let todayCups = records.filter { calendar.isDateInToday($0.date) }.count
        let week = stats(records: records, settings: settings, days: 7, now: now, calendar: calendar)
        let month = stats(records: records, settings: settings, days: 30, now: now, calendar: calendar)

        var lines: [String] = []
        lines.append(t("Today: {} cups, {} / {} ml.", todayCups, todayTotal, goal))

        if week.cups == 0 {
            lines.append(t("No drinks logged in the last 7 days."))
        } else {
            lines.append(t("Last 7 days: about {} ml a day, {} of 7 days on goal.", week.averageDay, week.goalDays))
            if week.streak >= 2 {
                lines.append(t("{} days in a row on goal.", week.streak))
            }
        }

        if let hour = week.bestStartHour {
            lines.append(t("Most drinks land between {} and {}.", hourLabel(hour), hourLabel(hour + 2)))
        }

        if month.cups > 0 {
            lines.append(t("Last 30 days: {} cups, {} ml in total, best streak {} days.",
                           month.cups, month.total, max(week.streak, month.streak)))
        }

        let ratio = Double(todayTotal) / Double(goal)
        if ratio >= 1 {
            lines.append(t("Goal reached — keep sipping at this pace."))
        } else if ratio >= 0.5 {
            lines.append(t("Almost there. Two more glasses will do it."))
        } else {
            lines.append(t("Behind today's goal. Start with a glass of water now."))
        }

        return lines.joined(separator: "\n")
    }

    /// 把一天按四段汇总，报表里的「时段分布」用它。
    static func buckets(
        records: [DrinkRecord],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DrinkBucket] {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let recent = records.filter { $0.date >= from && $0.date <= now }

        let ranges = [(t("Night"), 0, 6), (t("Morning"), 6, 12), (t("Afternoon"), 12, 18), (t("Evening"), 18, 24)]
        return ranges.enumerated().map { index, item in
            let ml = recent
                .filter {
                    let hour = calendar.component(.hour, from: $0.date)
                    return hour >= item.1 && hour < item.2
                }
                .reduce(0) { $0 + $1.ml }
            return DrinkBucket(id: index, label: item.0, ml: ml)
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour % 24)
    }
}

struct DrinkBucket: Identifiable {
    let id: Int
    let label: String
    let ml: Int
}
