import Foundation

nonisolated enum ProjectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case python, node, shell, folder, unknown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .python: "Python"
        case .node: "Node.js"
        case .shell: "Shell"
        case .folder: "文件夹"
        case .unknown: "待识别"
        }
    }
    var symbol: String {
        switch self {
        case .python: "chevron.left.forwardslash.chevron.right"
        case .node: "shippingbox"
        case .shell: "terminal"
        case .folder, .unknown: "folder"
        }
    }
}

nonisolated enum RunMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case task, service
    var id: String { rawValue }
    var title: String { self == .task ? "一次性任务" : "常驻服务" }
}

nonisolated enum RunStatus: String, Sendable {
    case idle, running, stopping, completed, stopped, failed
    var title: String {
        switch self {
        case .idle: "未运行"
        case .running: "运行中"
        case .stopping: "停止中"
        case .completed: "执行完成"
        case .stopped: "已停止"
        case .failed: "运行失败"
        }
    }
    var isActive: Bool { self == .running || self == .stopping }
}

nonisolated struct Evidence: Codable, Hashable, Sendable {
    var label: String
    var value: String
    var source: String
}

nonisolated struct LaunchOption: Codable, Hashable, Identifiable, Sendable {
    var command: String
    var source: String
    var id: String { command }
}

nonisolated struct DetectedProject: Codable, Sendable {
    var name: String
    var kind: ProjectKind
    var summary = ""
    var sourceURL = ""
    var evidence: [Evidence] = []
    var launchOptions: [LaunchOption] = []
    var runtimeDirectory = ""
    var environmentNames: [String] = []
}

nonisolated struct RunConfiguration: Codable, Equatable, Sendable {
    var command = ""
    var arguments = ""
    var workingDirectory = ""
    var runtimeDirectory = ""
    var stopCommand = ""
    var mode: RunMode = .task
    var environmentText = ""
    var requiredEnvironment = ""
    var confirmedAt: Date?
}

nonisolated struct ScriptConfiguration: Codable, Identifiable, Sendable {
    var id: UUID
    var relativePath: String
    var configuration: RunConfiguration
}

nonisolated struct ScriptLocation: Sendable {
    var projectID: UUID
    var relativePath: String
}

nonisolated struct Project: Codable, Identifiable, Sendable {
    var id = UUID()
    var path: String
    var isDirectory: Bool
    var detected: DetectedProject
    var customName: String?
    var customSummary: String?
    var customKind: ProjectKind?
    var notes = ""
    var tags: [String] = []
    var hasSavedConfiguration = false
    var configuration: RunConfiguration
    var scripts: [ScriptConfiguration] = []
    var isMissing = false
    var lastScannedAt = Date()

    var name: String { customName ?? detected.name }
    var summary: String { customSummary ?? detected.summary }
    var kind: ProjectKind { customKind ?? detected.kind }
    /// 文件夹只收录和浏览内容，无需配置项目启动命令。
    var needsConfiguration: Bool { kind != .folder && (configuration.confirmedAt == nil || configuration.command.isEmpty) }

    private enum CodingKeys: String, CodingKey {
        case id, path, isDirectory, detected, customName, customSummary, customKind, notes, tags
        case hasSavedConfiguration, configuration, scripts, isMissing, lastScannedAt
    }

    /// 读取项目资料，旧版本缺少标签或脚本配置时使用空数组。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        path = try values.decode(String.self, forKey: .path)
        isDirectory = try values.decode(Bool.self, forKey: .isDirectory)
        detected = try values.decode(DetectedProject.self, forKey: .detected)
        customName = try values.decodeIfPresent(String.self, forKey: .customName)
        customSummary = try values.decodeIfPresent(String.self, forKey: .customSummary)
        customKind = try values.decodeIfPresent(ProjectKind.self, forKey: .customKind)
        notes = try values.decode(String.self, forKey: .notes)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        hasSavedConfiguration = try values.decode(Bool.self, forKey: .hasSavedConfiguration)
        configuration = try values.decode(RunConfiguration.self, forKey: .configuration)
        scripts = try values.decodeIfPresent([ScriptConfiguration].self, forKey: .scripts) ?? []
        isMissing = try values.decode(Bool.self, forKey: .isMissing)
        lastScannedAt = try values.decode(Date.self, forKey: .lastScannedAt)
    }

    /// 解析用户输入的标签，支持中英文逗号及换行，去掉空白和重复项并保留输入顺序。
    static func parseTags(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text.components(separatedBy: CharacterSet(charactersIn: ",，\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 创建未确认的项目配置，只有唯一启动候选时才预填命令。
    init(path: String, isDirectory: Bool, detected: DetectedProject) {
        self.path = path
        self.isDirectory = isDirectory
        self.detected = detected
        configuration = RunConfiguration(
            command: detected.launchOptions.count == 1 ? detected.launchOptions[0].command : "",
            workingDirectory: isDirectory ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path,
            runtimeDirectory: detected.runtimeDirectory,
            requiredEnvironment: detected.environmentNames.joined(separator: "\n")
        )
    }
}

nonisolated struct ScanLocation: Codable, Identifiable, Sendable {
    var id = UUID()
    var path: String
}

nonisolated struct LibraryDocument: Codable, Sendable {
    var version = 1
    var projects: [Project] = []
    var locations: [ScanLocation] = []
}

nonisolated struct ScanResult: Sendable {
    var projects: [Project] = []
    var warnings: [String] = []
}

nonisolated enum OrbitloomError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
