import SwiftUI

@main
struct OrbitloomApp: App {
    @NSApplicationDelegateAdaptor(OrbitloomAppDelegate.self) private var delegate
    @State private var store: ProjectStore
    @State private var runner: RunManager

    /// 建立单一资料库和运行管理器，在主窗口与设置之间共享状态。
    init() {
        let store = ProjectStore()
        _store = State(initialValue: store)
        _runner = State(initialValue: RunManager(dataDirectory: store.dataDirectory))
    }

    var body: some Scene {
        Window("Orbitloom", id: "main") {
            ContentView()
                .environment(store).environment(runner)
                .task {
                    delegate.runner = runner
                    await store.refreshProjects()
                }
        }.defaultSize(width: 1160, height: 780)
        Settings {
            ScanSettingsView().environment(store)
        }
    }
}

@MainActor
final class OrbitloomAppDelegate: NSObject, NSApplicationDelegate {
    var runner: RunManager?

    /// 有活动实例时确认退出，并等待其进程和日志完成清理。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runner, runner.hasActiveRuns else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "停止运行中的项目并退出？"
        alert.informativeText = "Orbitloom 将停止由本应用启动的运行实例，并保存最近一次日志。"
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        runner.stopAll()
        Task {
            while runner.hasActiveRuns { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
