import SwiftUI

/// 应用级只有一份的东西：更新检查、更新安装、崩溃账本、个人信息。
/// 菜单栏面板与设置窗口都从这里取，不各自新建。
@MainActor
final class AppServices: ObservableObject {
    let updates = UpdateChecker()
    let installer = UpdateInstaller(steps: UpdateInstaller.productionSteps())
    let crashes = CrashStore()
    let profile = ProfileStore()
    let focus = FocusMonitor()

    init() {
        // 顺序不能反：先收上次的尸（读现场文件），再装处理器——
        // 装处理器时会清空轨迹本，那是留给这一次用的。
        crashes.harvest()
        CrashBreadcrumbs.install(directory: crashes.directory)
        CrashCatcher.install(directory: crashes.directory)
        CrashBreadcrumbs.note("launch \(CrashEnvironment.appVersion)")
        focus.start()
    }
}
