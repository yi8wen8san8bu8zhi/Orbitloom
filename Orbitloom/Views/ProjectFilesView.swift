import SwiftUI

struct ProjectFilesView: View {
    let project: Project
    let onShowResult: (RunResultSelection) -> Void
    @Environment(ProjectStore.self) private var store
    @Environment(RunManager.self) private var runner
    @State private var relativeDirectory = ""
    @State private var files: [ProjectFile] = []
    @State private var selectedScript: ProjectFile?
    @State private var pendingResult: RunResultSelection?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingConfigured = false

    private var activeScriptCount: Int {
        project.scripts.filter { runner.snapshot(for: $0.id).status.isActive }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回上级", systemImage: "chevron.left") {
                    relativeDirectory = (relativeDirectory as NSString).deletingLastPathComponent
                }.labelStyle(.iconOnly).disabled(relativeDirectory.isEmpty || isLoading)
                Button(project.name, systemImage: "folder") { relativeDirectory = "" }
                    .buttonStyle(.borderless).disabled(relativeDirectory.isEmpty || isLoading)
                if !relativeDirectory.isEmpty {
                    Text("/ " + relativeDirectory).lineLimit(1).truncationMode(.middle).help(relativeDirectory)
                }
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { Task { await loadFiles() } }.disabled(isLoading)
            }.font(.callout).padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !project.scripts.isEmpty {
                        DisclosureGroup(isExpanded: $showingConfigured) {
                            ForEach(project.scripts) { script in
                                HStack(spacing: 14) {
                                    Button {
                                        selectedScript = ProjectFile(relativePath: script.relativePath,
                                                                     name: (script.relativePath as NSString).lastPathComponent,
                                                                     isDirectory: false, kind: nil)
                                    } label: {
                                        HStack {
                                            Image(systemName: "play.rectangle")
                                            Text(script.relativePath).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            let status = runner.snapshot(for: script.id).status
                                            Text(status.title).font(.caption).foregroundStyle(status.color)
                                        }.padding(.vertical, 7).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    startButton(for: script.relativePath)
                                    Button("查看结果", systemImage: "rectangle.bottomthird.inset.filled") { showResult(for: script) }
                                        .buttonStyle(.borderless)
                                }
                            }
                        } label: {
                            HStack {
                                Text("已配置脚本与历史日志（\(project.scripts.count)）")
                                if activeScriptCount > 0 {
                                    Text("\(activeScriptCount) 个运行中").foregroundStyle(.indigo)
                                }
                            }.font(.callout.weight(.medium))
                        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                    }
                    if isLoading {
                        ProgressView("正在读取目录…").frame(maxWidth: .infinity).padding(30)
                    } else if files.isEmpty && errorMessage == nil {
                        ContentUnavailableView("此目录没有可显示的文件", systemImage: "folder",
                                               description: Text("隐藏文件、依赖和构建目录不会显示。"))
                    } else {
                        Text("当前目录 · \(files.count) 项").font(.caption).foregroundStyle(.secondary)
                        ForEach(files) { file in fileRow(file) }
                    }
                }.padding(24)
            }
        }
        .task(id: relativeDirectory) { await loadFiles() }
        .sheet(item: $selectedScript, onDismiss: {
            guard let pendingResult else { return }
            onShowResult(pendingResult)
            self.pendingResult = nil
        }) { file in
            ScriptDetailView(location: ScriptLocation(projectID: project.id, relativePath: file.relativePath), onShowResult: { result in
                pendingResult = result
                selectedScript = nil
            })
        }
    }

    /// 显示目录、可运行脚本和其他文件；只有支持的脚本提供配置及运行入口。
    private func fileRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 14) {
            Button {
                if file.isDirectory { relativeDirectory = file.relativePath }
                else { selectedScript = file }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: file.isDirectory ? "folder.fill" : (file.kind?.symbol ?? "doc.text"))
                        .font(.title3).foregroundStyle(file.isDirectory ? .indigo : .secondary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.name).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                        if file.isDirectory {
                            Text("打开目录").font(.caption).foregroundStyle(.secondary)
                        } else if let kind = file.kind {
                            Text(kind.title + " · 点击查看配置与运行").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(file.isSQL ? "需要数据库执行环境" : "此文件类型不支持直接运行")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let saved = project.scripts.first(where: { $0.relativePath == file.relativePath }) {
                        let status = runner.snapshot(for: saved.id).status
                        Text(status == .idle && saved.configuration.confirmedAt == nil ? "待配置" : status.title)
                            .font(.caption).foregroundStyle(status.color)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!file.isDirectory && file.kind == nil)
            if !file.isDirectory && file.kind != nil {
                startButton(for: file.relativePath)
            }
            if let saved = project.scripts.first(where: { $0.relativePath == file.relativePath }) {
                Button("查看结果", systemImage: "rectangle.bottomthird.inset.filled") { showResult(for: saved) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("查看执行结果")
            }
            Button("在 Finder 中显示", systemImage: "arrow.up.forward.square") {
                FilePanels.reveal(URL(fileURLWithPath: project.path).appendingPathComponent(file.relativePath).path)
            }.labelStyle(.iconOnly).buttonStyle(.borderless)
        }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 为两处脚本列表提供启动入口，运行中或项目丢失时禁用。
    private func startButton(for relativePath: String) -> some View {
        let saved = project.scripts.first(where: { $0.relativePath == relativePath })
        let isActive = saved.map { runner.snapshot(for: $0.id).status.isActive } ?? false
        return Button("启动", systemImage: "play.fill") {
            Task { await startScript(relativePath) }
        }.buttonStyle(.borderedProminent).tint(.indigo).controlSize(.small)
            .disabled(isActive || project.isMissing)
    }

    /// 使用已确认配置启动脚本并显示结果；尚未配置时打开脚本详情。
    private func startScript(_ relativePath: String) async {
        guard let parent = store.project(id: project.id) else {
            runner.errorMessage = "所属项目已从资料库移除。"
            return
        }
        guard let saved = parent.scripts.first(where: { $0.relativePath == relativePath }),
              saved.configuration.confirmedAt != nil, !saved.configuration.command.isEmpty else {
            selectedScript = ProjectFile(relativePath: relativePath,
                                         name: (relativePath as NSString).lastPathComponent,
                                         isDirectory: false, kind: nil)
            return
        }
        do {
            let root = parent.path
            var script = try await Task.detached(priority: .userInitiated) {
                try ProjectFileBrowser.inspectScript(root: root, relativePath: relativePath)
            }.value
            script.id = saved.id
            script.configuration = saved.configuration
            script.hasSavedConfiguration = true
            try store.validateScript(script, at: ScriptLocation(projectID: parent.id, relativePath: relativePath))
            runner.start(script)
            showResult(for: saved)
        } catch { runner.errorMessage = error.localizedDescription }
    }

    /// 直接按已保存的脚本标识打开结果，即使原文件失效也能读取日志或停止实例。
    private func showResult(for script: ScriptConfiguration) {
        let path = URL(fileURLWithPath: project.path).appendingPathComponent(script.relativePath)
        onShowResult(RunResultSelection(id: script.id, projectID: project.id, title: path.lastPathComponent, path: path.path))
    }

    /// 在后台按需读取当前层目录；刷新失败时显示原因，保留已保存脚本的日志入口。
    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        files = []
        let root = project.path
        let directory = relativeDirectory
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ProjectFileBrowser.contents(root: root, relativeDirectory: directory)
            }.value
            guard !Task.isCancelled else { return }
            files = result
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "无法读取目录：\(error.localizedDescription)"
        }
        isLoading = false
    }
}

private struct ScriptDetailView: View {
    let location: ScriptLocation
    let onShowResult: (RunResultSelection) -> Void
    @Environment(ProjectStore.self) private var store
    @Environment(RunManager.self) private var runner
    @Environment(\.dismiss) private var dismiss
    @State private var inspected: Project?
    @State private var errorMessage: String?

    private var script: Project? {
        guard var script = inspected else { return nil }
        if let saved = store.project(id: location.projectID)?.scripts.first(where: { $0.relativePath == location.relativePath }) {
            script.id = saved.id
            script.configuration = saved.configuration
            script.hasSavedConfiguration = true
        }
        return script
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(location.relativePath, systemImage: "doc.text").lineLimit(1).truncationMode(.middle).help(location.relativePath)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.font(.callout).padding(16)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let message = runner.errorMessage {
                HStack {
                    Text(message).textSelection(.enabled)
                    Spacer()
                    Button("关闭提示") { runner.errorMessage = nil }
                }.font(.callout).foregroundStyle(.orange).padding(16)
            }
            Divider()
            if let script {
                ProjectDetailView(project: script, onShowResult: onShowResult, scriptLocation: location).id(script.id)
            } else if errorMessage == nil {
                ProgressView("正在读取脚本…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("无法打开脚本", systemImage: "doc.badge.ellipsis",
                                       description: Text("关闭面板后刷新目录，检查文件位置和权限。"))
            }
        }.frame(width: 880, height: 780)
        .task { await loadScript() }
    }

    /// 加载脚本草稿；文件失效时仍允许查看已保存日志和停止尚在运行的实例。
    private func loadScript() async {
        guard let parent = store.project(id: location.projectID) else {
            errorMessage = "所属项目已从资料库移除。"
            return
        }
        do {
            let root = parent.path
            let relativePath = location.relativePath
            inspected = try await Task.detached(priority: .userInitiated) {
                try ProjectFileBrowser.inspectScript(root: root, relativePath: relativePath)
            }.value
        } catch {
            errorMessage = "无法读取脚本：\(error.localizedDescription)"
            if let saved = parent.scripts.first(where: { $0.relativePath == location.relativePath }) {
                let path = URL(fileURLWithPath: parent.path).appendingPathComponent(location.relativePath).path
                var missing = Project(path: path, isDirectory: false,
                                      detected: DetectedProject(name: (path as NSString).lastPathComponent, kind: .unknown))
                missing.id = saved.id
                missing.isMissing = true
                inspected = missing
            }
        }
    }
}
