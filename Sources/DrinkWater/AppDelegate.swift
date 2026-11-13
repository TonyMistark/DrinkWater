import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let services = AppServices()
    private lazy var scheduler = ReminderScheduler(store: store)
    private lazy var notifier = Notifier(store: store)

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setUpPopover()
        setUpStatusItem()

        notifier.setUp()
        notifier.statusButton = statusItem.button
        notifier.requestAuthorization()

        scheduler.onFire = { [weak self] in
            self?.notifier.notify()
        }
        let settingsStore = store
        let focusMonitor = services.focus
        scheduler.shouldHoldReminder = {
            settingsStore.settings.muteDuringFocus && focusMonitor.isFocusActive
        }
        store.settingsChanged = { [weak self] in
            self?.scheduler.recompute()
            self?.updateStatusTitle()
        }

        scheduler.start()
        scheduler.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)
        scheduler.$isSnoozed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        notifier.onDrink = { [weak self] in self?.handleDrink() }
        notifier.onSnooze = { [weak self] in self?.handleSnooze() }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(handleWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(handleWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        updateStatusTitle()

        // 上次没正常退出？把现场摊开；同时每天查一次更新（失败静默）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            CrashWindowController.shared.presentIfNeeded(store: self.services.crashes)
        }
        Task { [services] in
            await services.updates.checkIfDue()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
    }

    // MARK: - 菜单栏

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: t("Drink Water Reminder"))
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 600)

        let root = ContentView()
            .environmentObject(store)
            .environmentObject(scheduler)
            .environmentObject(notifier)
            .environmentObject(services)
            .environmentObject(services.focus)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: t("Open Panel"), action: #selector(openPanelFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: t("Drink {} ml", store.settings.cupML), action: #selector(drinkFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: t("Remind Me in 10 Minutes"), action: #selector(snoozeFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(withTitle: t("Check for Updates…"), action: #selector(checkUpdatesFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: t("About DrinkWater"), action: #selector(aboutFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: t("Report a Problem…"), action: #selector(reportProblemFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: store.settings.enabled ? t("Pause Reminders") : t("Resume Reminders"),
                     action: #selector(toggleEnabledFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Quit DrinkWater"), action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanelFromMenu() { togglePopover() }

    @objc private func drinkFromMenu() { handleDrink() }

    @objc private func snoozeFromMenu() { handleSnooze() }

    @objc private func openSettingsFromMenu() {
        SettingsWindowController.shared.show(services: services)
    }

    @objc private func checkUpdatesFromMenu() {
        Task { [services] in
            await services.updates.check(force: true)
        }
        SettingsWindowController.shared.show(services: services)
    }

    @objc private func aboutFromMenu() {
        AboutPanel.show()
    }

    @objc private func reportProblemFromMenu() {
        _ = services.crashes.recordFeedback(note: "", documentName: nil)
        CrashWindowController.shared.presentIfNeeded(store: services.crashes)
    }

    @objc private func toggleEnabledFromMenu() {
        store.settings.enabled.toggle()
        updateStatusTitle()
    }

    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    // MARK: - 行为

    private func handleDrink() {
        store.drink()
        scheduler.afterActivity()
        notifier.dismissWindows()
    }

    private func handleSnooze() {
        scheduler.snooze(minutes: 10)
        notifier.dismissWindows()
    }

    @objc private func handleWake() {
        services.focus.refresh()
        scheduler.recompute()
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let title: String
        if !store.settings.enabled {
            title = ""
        } else if scheduler.remainingSeconds <= 0 {
            title = t("Now")
        } else {
            let minutes = max(1, (scheduler.remainingSeconds + 59) / 60)
            title = "\(minutes)m"
        }
        if button.title != title {
            button.title = title
        }
    }
}
