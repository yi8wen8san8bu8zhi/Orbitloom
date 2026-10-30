import Darwin
import Foundation
import Observation

struct RunSnapshot {
    var status: RunStatus = .idle
    var log = ""
    var startedAt: Date?
    var finishedAt: Date?
    var detail = ""
}

@MainActor
private final class RunningInstance {
    let token = UUID()
    let configuration: RunConfiguration
    let environment: [String: String]
    var process: ManagedProcess?
    var stopProcess: ManagedProcess?
    var primaryExit: ProcessExit?
    var stopRequested = false
    var flushTask: Task<Void, Never>?

    /// 保留一次运行所使用的配置快照，后续编辑不会改变正在运行的实例。
    init(configuration: RunConfiguration, environment: [String: String]) {
        self.configuration = configuration
        self.environment = environment
    }
}

@MainActor
@Observable
final class RunManager {
    static let logLimit = 1_048_576
    private(set) var snapshots: [UUID: RunSnapshot] = [:]
    var errorMessage: String?
    @ObservationIgnored private let logDirectory: URL
    @ObservationIgnored private var instances: [UUID: RunningInstance] = [:]
    @ObservationIgnored private var buffers: [UUID: Data] = [:]
    @ObservationIgnored private var dirtyLogs = Set<UUID>()

    var hasActiveRuns: Bool { snapshots.values.contains { $0.status.isActive } }

    /// 将每个项目最近一次运行的日志保存在应用专属目录。
    init(dataDirectory: URL) {
        logDirectory = dataDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    /// 返回当前运行状态，未运行过的项目使用空状态。
    func snapshot(for id: UUID) -> RunSnapshot {
        snapshots[id] ?? RunSnapshot()
    }

    /// 汇总目录及其脚本状态，用于列表展示和运行期间的移除、重新定位限制。
    func status(for project: Project) -> RunStatus {
        let runs = ([project.id] + project.scripts.map(\.id)).compactMap { snapshots[$0] }
        if runs.contains(where: { $0.status == .running }) { return .running }
        if runs.contains(where: { $0.status == .stopping }) { return .stopping }
        return runs.max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }?.status ?? .idle
    }

    /// 按需加载最近一次日志；重启应用后不恢复旧 PID 或宣称项目仍在运行。
    func loadLog(for id: UUID) {
        guard snapshots[id] == nil else { return }
        let file = logDirectory.appendingPathComponent("\(id.uuidString).log")
        let data = (try? Data(contentsOf: file)) ?? Data()
        let bounded = Data(data.suffix(Self.logLimit))
        buffers[id] = bounded
        snapshots[id] = RunSnapshot(log: String(decoding: bounded, as: UTF8.self))
    }

    /// 在用户确认的配置上检查路径与环境，然后启动一个受管实例。
    func start(_ project: Project) {
        guard instances[project.id] == nil else { return }
        let id = project.id
        do {
            guard !project.needsConfiguration else { throw OrbitloomError.message("请先检查并保存运行配置。") }
            guard FileManager.default.fileExists(atPath: project.path) else { throw OrbitloomError.message("原位置不存在，请先重新定位项目。") }
            let configuration = project.configuration
            try RuntimeEnvironment.validateConfiguration(configuration)
            let environment = try RuntimeEnvironment.build(configuration)
            let directory = ProjectScanner.canonicalPath(configuration.workingDirectory)
            let command = configuration.command + (configuration.arguments.isEmpty ? "" : " " + configuration.arguments)
            try RuntimeEnvironment.preflight(command: command, workingDirectory: directory, environment: environment)
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            buffers[id] = Data()
            snapshots[id] = RunSnapshot(status: .running, startedAt: Date(), detail: "运行中")
            append("[Orbitloom] \(Date().formatted())\n工作目录：\(directory)\n$ \(command)\n\n", to: id)
            let instance = RunningInstance(configuration: configuration, environment: environment)
            instances[id] = instance
            let token = instance.token
            instance.process = try ManagedProcess(command: command, directory: directory, environment: environment) { [weak self] data in
                guard let self, self.instances[id]?.token == token else { return }
                self.append(data, to: id)
            } onExit: { [weak self] exit in
                guard let self, let current = self.instances[id], current.token == token else { return }
                current.primaryExit = exit
                current.process = nil
                current.stopProcess?.send(SIGKILL)
                self.finalizeIfFinished(id)
            }
            instance.flushTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.instances[id]?.token == token else { return }
                    self.flushLog(id)
                }
            }
            flushLog(id)
        } catch {
            instances.removeValue(forKey: id)?.flushTask?.cancel()
            var snapshot = snapshots[id] ?? RunSnapshot()
            snapshot.status = .failed
            snapshot.detail = error.localizedDescription
            snapshot.finishedAt = Date()
            snapshots[id] = snapshot
            append("\n[Orbitloom] 启动失败：\(error.localizedDescription)\n", to: id)
            flushLog(id)
            errorMessage = error.localizedDescription
        }
    }

    /// 优先执行用户配置的停止命令，再向对应实例发出终止信号并处理超时。
    func stop(_ id: UUID) {
        guard let instance = instances[id], !instance.stopRequested else { return }
        instance.stopRequested = true
        snapshots[id]?.status = .stopping
        snapshots[id]?.detail = "正在停止本次运行"
        append("\n[Orbitloom] 正在停止…\n", to: id)
        let token = instance.token
        let stopCommand = instance.configuration.stopCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stopCommand.isEmpty, let process = instance.process {
            var environment = instance.environment
            environment["ORBITLOOM_PID"] = String(process.pid)
            environment["ORBITLOOM_PGID"] = String(process.pid)
            do {
                instance.stopProcess = try ManagedProcess(command: stopCommand, directory: ProjectScanner.canonicalPath(instance.configuration.workingDirectory), environment: environment) { [weak self] data in
                    guard let self, self.instances[id]?.token == token else { return }
                    self.append(data, to: id)
                } onExit: { [weak self] exit in
                    guard let self, let current = self.instances[id], current.token == token else { return }
                    current.stopProcess = nil
                    self.append("\n[Orbitloom] 停止命令：\(exit.description)\n", to: id)
                    current.process?.send(SIGTERM)
                    self.finalizeIfFinished(id)
                }
            } catch {
                append("[Orbitloom] 停止命令失败：\(error.localizedDescription)，改用实例终止。\n", to: id)
                instance.process?.send(SIGTERM)
            }
        } else { instance.process?.send(SIGTERM) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(stopCommand.isEmpty ? 3 : 5))
            guard let self, let current = self.instances[id], current.token == token else { return }
            self.append("[Orbitloom] 停止等待已超时，强制结束本实例。\n", to: id)
            current.stopProcess?.send(SIGKILL)
            current.process?.send(SIGKILL)
        }
    }

    /// 应用退出时停止本应用仍持有的运行实例。
    func stopAll() {
        for id in Array(instances.keys) { stop(id) }
    }

    /// 收集有界日志数据，按字节保留最新的 1 MB。
    private func append(_ data: Data, to id: UUID) {
        var buffer = buffers[id] ?? Data()
        buffer.append(data)
        if buffer.count > Self.logLimit { buffer = Data(buffer.suffix(Self.logLimit)) }
        buffers[id] = buffer
        dirtyLogs.insert(id)
    }

    /// 为运行生命周期提示复用日志通道。
    private func append(_ text: String, to id: UUID) {
        append(Data(text.utf8), to: id)
    }

    /// 定期刷新界面和磁盘日志，避免每个输出分片触发完整视图更新。
    private func flushLog(_ id: UUID) {
        guard dirtyLogs.remove(id) != nil, let data = buffers[id] else { return }
        snapshots[id, default: RunSnapshot()].log = String(decoding: data, as: UTF8.self)
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let file = logDirectory.appendingPathComponent("\(id.uuidString).log")
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { errorMessage = "运行日志无法保存：\(error.localizedDescription)" }
    }

    /// 在主命令和停止命令均退出后，区分正常任务、服务退出和主动停止。
    private func finalizeIfFinished(_ id: UUID) {
        guard let instance = instances[id], let exit = instance.primaryExit, instance.stopProcess == nil else { return }
        let status: RunStatus
        let detail: String
        if instance.stopRequested {
            status = .stopped
            detail = "已停止本次运行"
        } else if instance.configuration.mode == .service {
            status = .failed
            detail = "常驻服务已退出（\(exit.description)），请查看日志。"
        } else if exit.succeeded {
            status = .completed
            detail = "任务已正常完成"
        } else {
            status = .failed
            detail = "运行失败：\(exit.description)"
        }
        snapshots[id]?.status = status
        snapshots[id]?.detail = detail
        snapshots[id]?.finishedAt = Date()
        append("\n[Orbitloom] \(detail)\n", to: id)
        flushLog(id)
        instance.flushTask?.cancel()
        instances.removeValue(forKey: id)
    }
}
