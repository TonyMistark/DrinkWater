import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var scheduler: ReminderScheduler
    @EnvironmentObject private var notifier: Notifier
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var focus: FocusMonitor

    @State private var tab: Tab = .today
    @State private var summaryText = ""
    @State private var showSummary = false

    enum Tab: String, CaseIterable, Identifiable {
        case today
        case records
        case reminder
        case sync

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return t("Today")
            case .records: return t("Records")
            case .reminder: return t("Reminders")
            case .sync: return t("Sync")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    switch tab {
                    case .today: todayTab
                    case .records: recordsTab
                    case .reminder: reminderTab
                    case .sync: syncTab
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { notifier.refreshAuthorizationStatus() }
        .sheet(isPresented: $showSummary) {
            SummarySheet(text: summaryText)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue],
                                                startPoint: .top,
                                                endPoint: .bottom))
            Text(t("Drink Water Reminder"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(store.settings.enabled ? t("On") : t("Paused"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("", isOn: $store.settings.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            Button {
                SettingsWindowController.shared.show(services: services)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(t("Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(t("Quit"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 今日

    private var todayTab: some View {
        VStack(spacing: 12) {
            progressCard
            actionButtons
            weekCard
            nextReminderCard
        }
    }

    private var progressCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.12), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.001, store.progress))
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .indigo],
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.45), value: store.progress)

                VStack(spacing: 2) {
                    Text("\(store.todayTotal)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(t("/ {} ml", store.settings.dailyGoalML))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 148, height: 148)
            .padding(.top, 4)

            HStack(spacing: 0) {
                statItem(title: t("Drank"), value: t("{} cups", store.todayCups))
                Divider().frame(height: 24)
                statItem(title: t("Goal"), value: t("{} cups", store.cupsGoal))
                Divider().frame(height: 24)
                statItem(title: t("Done"), value: "\(Int(store.progress * 100))%")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                drink()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                    Text(t("Drink {} ml", store.settings.cupML))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)

            HStack(spacing: 8) {
                Button {
                    scheduler.snooze(minutes: 10)
                } label: {
                    Label(t("10 min later"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    store.undoLastDrink()
                } label: {
                    Label(t("Undo"), systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.todayCups == 0)
            }
        }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Last 7 Days"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(store.last7Days()) { day in
                    VStack(spacing: 5) {
                        Text(day.total > 0 ? "\(day.total)" : "")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(for: day))
                            .frame(height: barHeight(for: day))
                        Text(dayLabel(day.date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var nextReminderCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(nextReminderTitle)
                    .font(.callout.weight(.medium))
                Text(t("{} – {} · every {} min",
                       TimeText.minutesLabel(store.settings.activeStartMinutes),
                       TimeText.minutesLabel(store.settings.activeEndMinutes),
                       store.settings.intervalMinutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 记录与报表

    private var recordsTab: some View {
        VStack(spacing: 12) {
            summaryCard
            reportCard
            distributionCard
            recordsCard
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.blue)
                Text(t("Drinking summary"))
                    .font(.callout.weight(.medium))
                Spacer()
            }
            Text(t("One tap turns today and the last 7 days into a few readable lines."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                summaryText = DrinkInsights.summary(records: store.records, settings: store.settings)
                showSummary = true
            } label: {
                Label(t("Generate Summary"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var reportCard: some View {
        let stats = DrinkInsights.stats(records: store.records, settings: store.settings, days: 30)
        let days = store.lastDays(30)
        return SettingsCard(title: t("30-day report")) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(reportBarColor(for: day))
                        .frame(height: reportBarHeight(for: day))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)

            HStack {
                Text(days.first.map { shortDate($0.date) } ?? "")
                Spacer()
                Text(t("Today"))
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)

            Divider()

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      spacing: 8) {
                metric(t("Average day"), t("{} ml", stats.averageDay))
                metric(t("On goal"), t("{} / 30 days", stats.goalDays))
                metric(t("Streak"), t("{} days", stats.streak))
                metric(t("Average cup"), t("{} ml", stats.averageCup))
            }
        }
    }

    private var distributionCard: some View {
        let buckets = DrinkInsights.buckets(records: store.records, days: 30)
        let maxML = max(1, buckets.map(\.ml).max() ?? 0)
        return SettingsCard(title: t("By time of day")) {
            ForEach(buckets) { bucket in
                HStack(spacing: 8) {
                    Text(bucket.label)
                        .font(.caption2)
                        .frame(width: 54, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: geo.size.width * CGFloat(bucket.ml) / CGFloat(maxML))
                        }
                    }
                    .frame(height: 6)
                    Text(t("{} ml", bucket.ml))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private var recordsCard: some View {
        SettingsCard(title: t("Drinking records")) {
            if recordGroups.isEmpty {
                Text(t("No records yet. Drink a glass and it will show up here."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recordGroups, id: \.day) { group in
                    Text(dayTitle(group.day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(group.items) { record in
                        HStack(spacing: 8) {
                            Text(timeText(record.date))
                                .font(.caption)
                                .monospacedDigit()
                            Text(t("{} ml", record.ml))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.deleteRecord(record.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(t("Delete"))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var recordGroups: [(day: Date, items: [DrinkRecord])] {
        let calendar = Calendar.current
        let recent = store.records.sorted { $0.date > $1.date }.prefix(40)
        var order: [Date] = []
        var map: [Date: [DrinkRecord]] = [:]
        for record in recent {
            let day = calendar.startOfDay(for: record.date)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(record)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func reportBarHeight(for day: DayTotal) -> CGFloat {
        let goal = max(1, store.settings.dailyGoalML)
        let ratio = min(1, Double(day.total) / Double(goal))
        return max(3, CGFloat(ratio) * 56)
    }

    private func reportBarColor(for day: DayTotal) -> Color {
        if day.total >= store.settings.dailyGoalML { return .blue }
        if day.total > 0 { return .blue.opacity(0.4) }
        return Color.primary.opacity(0.08)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = L10n.isChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return t("Today") }
        if calendar.isDateInYesterday(day) { return t("Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = L10n.isChinese ? "M月d日 EEEE" : "EEEE, MMM d"
        return formatter.string(from: day)
    }

    // MARK: - 提醒设置

    private var reminderTab: some View {
        VStack(spacing: 12) {
            SettingsCard(title: t("Reminder rhythm")) {
                stepperRow(title: t("Interval"), value: t("{} min", store.settings.intervalMinutes)) {
                    Stepper("", value: $store.settings.intervalMinutes, in: 5...180, step: 5)
                        .labelsHidden()
                }

                Divider()

                HStack {
                    Text(t("Start"))
                    Spacer()
                    DatePicker("", selection: timeBinding(\.activeStartMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }

                Divider()

                HStack {
                    Text(t("End"))
                    Spacer()
                    DatePicker("", selection: timeBinding(\.activeEndMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }

            SettingsCard(title: t("Water intake")) {
                stepperRow(title: t("Daily goal"), value: t("{} ml", store.settings.dailyGoalML)) {
                    Stepper("", value: $store.settings.dailyGoalML, in: 500...5000, step: 100)
                        .labelsHidden()
                }
                Divider()
                stepperRow(title: t("Cup size"), value: t("{} ml", store.settings.cupML)) {
                    Stepper("", value: $store.settings.cupML, in: 100...600, step: 50)
                        .labelsHidden()
                }
            }

            SettingsCard(title: t("Mac notification channels")) {
                Toggle(t("Notification banner"), isOn: $store.settings.systemBanner)
                Toggle(t("Floating reminder card"), isOn: $store.settings.reminderPanel)
                Toggle(t("Full-screen overlay"), isOn: $store.settings.fullscreenOverlay)
                Toggle(t("Menu bar icon flash"), isOn: $store.settings.menuBarPulse)
                Toggle(t("Spoken reminder"), isOn: $store.settings.speechEnabled)

                Divider()

                Toggle(t("Alert sound"), isOn: $store.settings.soundEnabled)
                if store.settings.soundEnabled {
                    HStack {
                        Picker("", selection: $store.settings.soundName) {
                            ForEach(Notifier.soundNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        Button(t("Preview")) { notifier.previewSound() }
                            .buttonStyle(.link)
                    }
                }
            }

            SettingsCard(title: t("Launch")) {
                LaunchAtLoginRow()
            }

            SettingsCard(title: t("Focus")) {
                Toggle(t("Pause reminders during Focus"), isOn: $store.settings.muteDuringFocus)

                HStack(spacing: 6) {
                    Circle()
                        .fill(focus.isFocusActive ? Color.indigo : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text(focusStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.settings.muteDuringFocus && focus.needsPermission {
                        Button(t("Allow Focus Access")) { focus.requestAuthorization() }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }

                Text(t("When a Focus is on, reminders wait and arrive once it ends."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: store.settings.muteDuringFocus) { enabled in
                if enabled, focus.needsPermission {
                    focus.requestAuthorization()
                }
            }

            if store.systemNotificationDenied {
                SettingsCard(title: t("System notifications are off")) {
                    Text(t("Banners will not appear. You can allow notifications for DrinkWater again in System Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(t("Open Notification Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }

            Button {
                notifier.notify(isTest: true)
            } label: {
                Label(t("Test current notification channels"), systemImage: "bell.and.waves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 手机同步

    private var syncTab: some View {
        VStack(spacing: 12) {
            SettingsCard(title: t("Push to phone / watch")) {
                HStack {
                    Text(t("Method"))
                    Spacer()
                    Picker("", selection: $store.settings.pushProvider) {
                        ForEach(PushProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                Text(store.settings.pushProvider.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.settings.pushProvider != .none {
                SettingsCard(title: t("Setup")) {
                    switch store.settings.pushProvider {
                    case .bark:
                        fieldRow(title: t("Server"), placeholder: "https://api.day.app", text: $store.settings.barkServer)
                        fieldRow(title: t("Device Key"), placeholder: t("Copied from the Bark app"), text: $store.settings.barkKey)
                    case .ntfy:
                        fieldRow(title: t("Server"), placeholder: "https://ntfy.sh", text: $store.settings.ntfyServer)
                        fieldRow(title: t("Topic"), placeholder: "water-ice", text: $store.settings.ntfyTopic)
                    case .pushover:
                        fieldRow(title: t("Token"), placeholder: t("App token"), text: $store.settings.pushoverToken)
                        fieldRow(title: t("User Key"), placeholder: t("User key"), text: $store.settings.pushoverUser)
                    case .custom:
                        fieldRow(title: t("URL template"), placeholder: "https://example.com/hook?title={title}", text: $store.settings.customURL)
                        HStack {
                            Text(t("HTTP method"))
                            Spacer()
                            Picker("", selection: $store.settings.customMethod) {
                                Text("POST").tag("POST")
                                Text("GET").tag("GET")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                        }
                    case .none:
                        EmptyView()
                    }
                }

                Button {
                    notifier.sendTestPush()
                } label: {
                    Label(t("Send Test Push"), systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if let status = store.pushStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.hasPrefix("✗") ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: t("About watch reminders")) {
                Text(t("Bark and Pushover notifications reach iPhone first. When iPhone is locked and you are wearing Apple Watch, the system mirrors them to your wrist. ntfy needs the ntfy app on iPhone with the same topic."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 组件

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepperRow<Control: View>(title: String,
                                           value: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.callout.monospacedDigit())
            control()
        }
    }

    private func fieldRow(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 62, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    // MARK: - 计算

    private var nextReminderTitle: String {
        guard store.settings.enabled else { return t("Reminders paused") }
        if scheduler.isSnoozed {
            return t("Snoozed · {}", TimeText.countdown(scheduler.remainingSeconds))
        }
        return t("Next reminder · {}", TimeText.countdown(scheduler.remainingSeconds))
    }

    private var focusStatusText: String {
        guard store.settings.muteDuringFocus else { return t("Not following Focus") }
        switch focus.authorization {
        case .authorized:
            return focus.isFocused == true ? t("Focus is on · reminders held") : t("Focus is off")
        case .denied:
            return t("Focus access denied. Allow it in System Settings.")
        case .notDetermined:
            return t("Allow access to Focus status to use this.")
        case .restricted, .unknown:
            return t("Focus status is unavailable on this Mac.")
        }
    }

    private func barHeight(for day: DayTotal) -> CGFloat {
        let goal = max(1, store.settings.dailyGoalML)
        let ratio = min(1, Double(day.total) / Double(goal))
        return max(4, CGFloat(ratio) * 64)
    }

    private func barColor(for day: DayTotal) -> Color {
        if day.total >= store.settings.dailyGoalML { return .blue }
        if day.total > 0 { return .blue.opacity(0.45) }
        return Color.primary.opacity(0.08)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isChinese ? "zh_CN" : "en_US")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    // MARK: - 行为

    private func drink() {
        store.drink()
        scheduler.afterActivity()
        notifier.dismissWindows()
    }

    private func timeBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: { minutesToDate(store.settings[keyPath: keyPath]) },
            set: { store.settings[keyPath: keyPath] = minutesFromDate($0) }
        )
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

// MARK: - 喝水总结

struct SummarySheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Drinking summary"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label(t("Copy"), systemImage: "doc.on.doc")
                }
                Spacer()
                Button(t("Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340, height: 300)
    }
}

// MARK: - 设置分组卡片

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - 登录启动行

struct LaunchAtLoginRow: View {
    @State private var isOn: Bool = LaunchAtLogin.isEnabled
    @State private var needsApproval: Bool = LaunchAtLogin.needsApproval
    @State private var error: String?

    var body: some View {
        Toggle(t("Start when I log in"), isOn: Binding(
            get: { isOn },
            set: { set($0) }
        ))

        if needsApproval {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(t("macOS is asking for approval. Open Login Items and flip the switch on."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(t("Open Settings")) { LaunchAtLogin.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        } else if let error {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !LaunchAtLogin.isSupported {
            Text(t("Not available when running from the source build. Please use the .app."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func set(_ newValue: Bool) {
        guard LaunchAtLogin.isSupported else {
            isOn = false
            return
        }
        if let reason = LaunchAtLogin.set(newValue) {
            error = reason
            isOn = LaunchAtLogin.isEnabled
            needsApproval = LaunchAtLogin.needsApproval
        } else {
            isOn = LaunchAtLogin.isEnabled
            needsApproval = LaunchAtLogin.needsApproval
            error = nil
        }
    }
}

