import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var scheduler: ReminderScheduler
    @EnvironmentObject private var notifier: Notifier
    @EnvironmentObject private var services: AppServices

    @State private var tab: Tab = .today

    enum Tab: String, CaseIterable, Identifiable {
        case today
        case reminder
        case sync

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return t("Today")
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
