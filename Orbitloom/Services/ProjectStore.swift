import Foundation
import Observation

@MainActor
@Observable
final class ProjectStore {
    private(set) var document = LibraryDocument()
    private(set) var isScanning = false
    private(set) var scanMessage = ""
    private(set) var scanWarnings: [String] = []
    var errorMessage: String?
    @ObservationIgnored let dataDirectory: URL
    @ObservationIgnored private var storageIsReadable = true

    var projects: [Project] { document.projects }
    var locations: [ScanLocation] { document.locations }
    var allTags: [String] {
        Set(projects.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 从应用专属目录加载资料库；文件损坏时停止写入，保留原始数据供恢复。
    init(dataDirectory: URL? = nil) {
        self.dataDirectory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbitloom", isDirectory: true)
        let file = self.dataDirectory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            document = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf: file))
            guard document.version == 1 else { throw OrbitloomError.message("资料库版本不受支持。") }
            for index in document.projects.indices {
                document.projects[index].isMissing = !FileManager.default.fileExists(atPath: document.projects[index].path)
            }
        } catch {
            storageIsReadable = false
            errorMessage = "无法加载资料库，已保留原文件并停止写入。\(error.localizedDescription)\n\(file.path)"
        }
    }

    /// 先原子写入磁盘，成功后再更新界面，避免将保存失败的配置显示为已保存。
    private func commit(_ updated: LibraryDocument) throws {
        guard storageIsReadable else { throw OrbitloomError.message("资料库读取失败，请先恢复 library.json 后重启应用。") }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = dataDirectory.appendingPathComponent("library.json")
        try encoder.encode(updated).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        document = updated
    }

    /// 查找最新项目快照，供编辑、运行和详情页面使用。
    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// 保存手动填写的名称、用途与标签；重复路径返回已有项目，不覆盖其资料或配置。
    func addProject(at url: URL, name: String, summary: String, tagsText: String = "") async throws -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw OrbitloomError.message("请填写项目名称。") }
        var project = try await Task.detached(priority: .userInitiated) { try ProjectScanner.inspect(url.path) }.value
        if let existing = projects.first(where: { $0.path == project.path }) { return existing.id }
        project.customName = trimmedName
        project.customSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        project.tags = Project.parseTags(tagsText)
        var updated = document
        updated.projects.append(project)
        try commit(updated)
        return project.id
    }

    /// 只保存扫描位置；发现候选和确认收录由用户分别触发。
    func addLocation(_ url: URL) {
        let path = ProjectScanner.canonicalPath(url.path)
        guard !locations.contains(where: { $0.path == path }) else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw OrbitloomError.message("扫描位置必须是目录。") }
            var updated = document
            updated.locations.append(ScanLocation(path: path))
            try commit(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    /// 移除扫描来源，已收录项目及磁盘文件均保留。
    func removeLocation(id: UUID) {
        var updated = document
        updated.locations.removeAll { $0.id == id }
        do { try commit(updated) }
        catch { errorMessage = error.localizedDescription }
    }

    /// 发现未收录的候选项目并返回预览，扫描本身不写入资料库。
    func discoverProjects() async -> ScanResult? {
        guard !isScanning, storageIsReadable else { return nil }
        errorMessage = nil
        isScanning = true
        scanMessage = "正在发现候选项目…"
        defer { isScanning = false }
        let locations = locations.map(\.path)
        let existingPaths = projects.map(\.path)
        var result = await Task.detached(priority: .utility) {
            ProjectScanner.scan(locations: locations, existingPaths: existingPaths)
        }.value
        let currentPaths = Set(projects.map(\.path))
        result.projects.removeAll { currentPaths.contains($0.path) }
        scanMessage = "扫描完成 · 发现 \(result.projects.count) 个候选，勾选后才会添加"
        scanWarnings = result.warnings
        return result
    }

    /// 重新读取用户勾选的候选，并一次保存新增条目；失败时保留资料库原状。
    func addDiscoveredProjects(_ candidates: [Project]) async -> Bool {
        guard !isScanning, storageIsReadable, !candidates.isEmpty else { return false }
        errorMessage = nil
        isScanning = true
        scanMessage = "正在添加所选项目…"
        defer { isScanning = false }
        do {
            let paths = candidates.map(\.path)
            let inspected = try await Task.detached(priority: .userInitiated) {
                try paths.map { try ProjectScanner.inspect($0) }
            }.value
            var updated = document
            var knownPaths = Set(updated.projects.map(\.path))
            for project in inspected where knownPaths.insert(project.path).inserted {
                updated.projects.append(project)
            }
            let added = updated.projects.count - document.projects.count
            try commit(updated)
            scanMessage = "已添加 \(added) 个项目"
            return true
        } catch {
            errorMessage = error.localizedDescription
            scanMessage = "添加失败，所选项目尚未收录"
            return false
        }
    }

    /// 只刷新已收录项目的识别信息和未保存的默认配置，不新增或移除条目。
    func refreshProjects() async {
        guard !isScanning, storageIsReadable else { return }
        errorMessage = nil
        isScanning = true
        scanMessage = "正在刷新已收录项目…"
        defer { isScanning = false }
        let existingPaths = projects.map(\.path)
        let result = await Task.detached(priority: .utility) {
            ProjectScanner.refresh(paths: existingPaths)
        }.value
        var updated = document
        for found in result.projects {
            if let index = updated.projects.firstIndex(where: { $0.path == found.path }) {
                updated.projects[index].detected = found.detected
                updated.projects[index].lastScannedAt = Date()
                if !updated.projects[index].hasSavedConfiguration {
                    updated.projects[index].configuration = found.configuration
                }
            }
        }
        for index in updated.projects.indices {
            updated.projects[index].isMissing = !FileManager.default.fileExists(atPath: updated.projects[index].path)
        }
        do {
            try commit(updated)
            scanMessage = "已刷新 \(result.projects.count) 个项目"
            scanWarnings = result.warnings
        } catch { errorMessage = error.localizedDescription }
    }

    /// 独立保存项目标签，无需校验启动命令，也不改变运行配置的确认状态。
    func saveTags(id: UUID, text: String) throws {
        guard let index = document.projects.firstIndex(where: { $0.id == id }) else {
            throw OrbitloomError.message("项目已从资料库移除，无法保存标签。")
        }
        var updated = document
        updated.projects[index].tags = Project.parseTags(text)
        try commit(updated)
    }

    /// 保存用户确认的完整配置，重新扫描不会覆盖这些字段。
    func saveConfiguration(id: UUID, name: String, summary: String, kind: ProjectKind, notes: String, configuration: RunConfiguration) throws {
        guard let index = document.projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw OrbitloomError.message("请填写项目名称。") }
        try RuntimeEnvironment.validateConfiguration(configuration)
        var updated = document
        updated.projects[index].customName = trimmedName
        updated.projects[index].customSummary = summary
        updated.projects[index].customKind = kind
        updated.projects[index].notes = notes
        updated.projects[index].configuration = configuration
        updated.projects[index].configuration.confirmedAt = Date()
        updated.projects[index].hasSavedConfiguration = true
        try commit(updated)
    }

    /// 保存或启动目录内脚本前核对所属项目及文件位置，避免使用重新定位前的草稿。
    func validateScript(_ script: Project, at location: ScriptLocation) throws {
        guard let parent = project(id: location.projectID), parent.isDirectory else {
            throw OrbitloomError.message("所属项目已不在资料库中。")
        }
        let file = try ProjectFileBrowser.scriptURL(root: parent.path, relativePath: location.relativePath)
        guard file.path == script.path else {
            throw OrbitloomError.message("项目位置已改变，请关闭面板并重新打开脚本。")
        }
    }

    /// 按项目内相对路径保存脚本配置和稳定日志标识，不新增左侧资料库条目。
    func saveScriptConfiguration(_ configuration: RunConfiguration, script: Project, at location: ScriptLocation) throws {
        try validateScript(script, at: location)
        try RuntimeEnvironment.validateConfiguration(configuration)
        guard let index = document.projects.firstIndex(where: { $0.id == location.projectID }) else { return }
        var updated = document
        var confirmed = configuration
        confirmed.confirmedAt = Date()
        if let scriptIndex = updated.projects[index].scripts.firstIndex(where: { $0.relativePath == location.relativePath }) {
            updated.projects[index].scripts[scriptIndex].configuration = confirmed
        } else {
            updated.projects[index].scripts.append(ScriptConfiguration(id: script.id, relativePath: location.relativePath, configuration: confirmed))
        }
        try commit(updated)
    }

    /// 重新关联原项目，调整项目内目录并要求用户复核可能失效的绝对命令路径。
    func relocate(id: UUID, to url: URL) async {
        do {
            let found = try await Task.detached(priority: .userInitiated) { try ProjectScanner.inspect(url.path) }.value
            guard let index = document.projects.firstIndex(where: { $0.id == id }) else { return }
            guard !projects.contains(where: { $0.path == found.path && $0.id != id }) else {
                throw OrbitloomError.message("新位置已被另一个项目收录，请选择其他位置。")
            }
            var updated = document
            let original = updated.projects[index]
            guard original.isDirectory == found.isDirectory else { throw OrbitloomError.message("请选择与原项目一致的目录或脚本类型。") }
            let oldRoot = original.isDirectory ? original.path : URL(fileURLWithPath: original.path).deletingLastPathComponent().path
            let newRoot = found.isDirectory ? found.path : URL(fileURLWithPath: found.path).deletingLastPathComponent().path
            var configuration = original.configuration
            if configuration.workingDirectory == oldRoot || configuration.workingDirectory.hasPrefix(oldRoot + "/") {
                configuration.workingDirectory = newRoot + configuration.workingDirectory.dropFirst(oldRoot.count)
            }
            if configuration.runtimeDirectory.hasPrefix(oldRoot + "/") {
                configuration.runtimeDirectory = newRoot + configuration.runtimeDirectory.dropFirst(oldRoot.count)
            }
            configuration.confirmedAt = nil
            updated.projects[index].path = found.path
            updated.projects[index].detected = found.detected
            updated.projects[index].isMissing = false
            updated.projects[index].configuration = configuration
            for scriptIndex in updated.projects[index].scripts.indices {
                var scriptConfiguration = updated.projects[index].scripts[scriptIndex].configuration
                if scriptConfiguration.workingDirectory == oldRoot || scriptConfiguration.workingDirectory.hasPrefix(oldRoot + "/") {
                    scriptConfiguration.workingDirectory = newRoot + scriptConfiguration.workingDirectory.dropFirst(oldRoot.count)
                }
                if scriptConfiguration.runtimeDirectory == oldRoot || scriptConfiguration.runtimeDirectory.hasPrefix(oldRoot + "/") {
                    scriptConfiguration.runtimeDirectory = newRoot + scriptConfiguration.runtimeDirectory.dropFirst(oldRoot.count)
                }
                scriptConfiguration.confirmedAt = nil
                updated.projects[index].scripts[scriptIndex].configuration = scriptConfiguration
            }
            updated.projects[index].lastScannedAt = Date()
            try commit(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    /// 只从索引移除项目，不删除磁盘上的项目目录或脚本。
    @discardableResult
    func removeProject(id: UUID) -> Bool {
        removeProjects(ids: [id])
    }

    /// 一次保存所有选中项目的移除结果；保存失败时保留原资料库并返回失败。
    @discardableResult
    func removeProjects(ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        var updated = document
        updated.projects.removeAll { ids.contains($0.id) }
        do {
            try commit(updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
