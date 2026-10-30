import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    let onShowResult: (RunResultSelection) -> Void
    var scriptLocation: ScriptLocation? = nil
    @Environment(ProjectStore.self) private var store
    @Environment(RunManager.self) private var runner
    @State private var tab = "overview"
    @State private var editing = false
    @State private var editingTags = false
    @State private var followLog = true

    private var run: RunSnapshot { runner.snapshot(for: project.id) }
    private var projectStatus: RunStatus { runner.status(for: project) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: project.kind.symbol).font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.indigo).frame(width: 64, height: 64)
                        .background(.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.name).font(.system(size: 27, weight: .semibold)).textSelection(.enabled)
                        HStack(spacing: 8) {
                            badge(project.kind.title, color: .indigo)
                            if project.kind != .folder { badge(projectStatus.title, color: projectStatus.color) }
                            if project.isMissing { badge("原位置不存在", color: .orange) }
                            else if project.needsConfiguration { badge(project.isDirectory ? "项目启动待配置" : "待配置", color: .orange) }
                            else if project.kind != .folder { badge("配置已确认", color: .secondary) }
                        }
                    }
                    Spacer()
                    Button(project.kind == .folder ? "编辑信息" : "编辑配置", systemImage: "slider.horizontal.3") { editing = true }.disabled(projectStatus.isActive)
                }
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    Text(project.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    Spacer()
                    Button("在 Finder 中显示", systemImage: "arrow.up.forward.square") { FilePanels.reveal(project.path) }
                        .labelStyle(.iconOnly).buttonStyle(.plain).disabled(project.isMissing)
                }.foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Picker("项目详情", selection: $tab) {
                        Text("概览").tag("overview")
                        if project.isDirectory { Text("文件").tag("files") }
                        if project.kind != .folder {
                            Text("运行配置").tag("configuration")
                            if project.isDirectory { Text("运行日志").tag("logs") }
                        }
                    }.pickerStyle(.segmented).frame(maxWidth: 460)
                    if !project.isDirectory {
                        Button("查看结果", systemImage: "rectangle.bottomthird.inset.filled") { showResult() }
                    }
                }
            }.padding(28)
            Divider()
            if tab == "files" { ProjectFilesView(project: project, onShowResult: onShowResult).id(project.path) }
            else if tab == "logs" { RunLogView(run: run, followLog: $followLog) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if project.isMissing {
                            GroupBox {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label("原位置不存在", systemImage: "exclamationmark.folder").foregroundStyle(.orange)
                                        Group {
                                            if project.kind == .folder {
                                                Text("项目信息已保留，请重新定位文件夹。")
                                            } else {
                                                Text(scriptLocation == nil ? "备注和配置已保留。重新定位后，请核对命令并保存配置。" : "配置和日志已保留。请检查文件位置与权限，恢复后重新打开脚本。")
                                            }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if scriptLocation == nil {
                                        Button("重新定位…") { relocate() }.disabled(projectStatus.isActive || store.isScanning)
                                    }
                                }.padding(6)
                            }
                        }
                        if tab == "overview" { overview } else { configurationView }
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            if tab == "files" {
                Text("点击脚本查看配置和日志；首次确认配置后即可运行。")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.vertical, 18).background(.bar)
            } else if project.kind == .folder {
                Text("文件夹无需启动，可在「文件」中浏览内容和运行脚本。")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.vertical, 18).background(.bar)
            } else {
                HStack(spacing: 14) {
                    Circle().fill(run.status.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.detail.isEmpty ? "准备好后，从这里启动" : run.detail).font(.callout).lineLimit(2)
                        Text(project.configuration.mode.title + " · " + (project.configuration.runtimeDirectory.isEmpty ? "系统 PATH 环境" : "已选择本地环境"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("停止", systemImage: "stop.fill") { runner.stop(project.id) }.disabled(run.status != .running)
                    Button(project.needsConfiguration ? "检查并配置" : "启动", systemImage: project.needsConfiguration ? "slider.horizontal.3" : "play.fill") {
                        if project.needsConfiguration { editing = true }
                        else { start() }
                    }.buttonStyle(.borderedProminent).tint(.indigo).disabled(run.status.isActive || project.isMissing)
                }.padding(.horizontal, 28).padding(.vertical, 18).background(.bar)
            }
        }
        .sheet(isPresented: $editing) { ProjectEditorView(project: project, scriptLocation: scriptLocation) }
        .sheet(isPresented: $editingTags) { ProjectTagsEditorView(project: project) }
        .task { runner.loadLog(for: project.id) }
        .onChange(of: project.kind) { _, kind in
            if kind == .folder && (tab == "configuration" || tab == "logs") { tab = "overview" }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailSection("用途说明", symbol: "text.alignleft") {
                let fallbackSummary: String = if project.kind == .folder {
                    "尚未填写用途说明，可在编辑信息中补充。"
                } else {
                    scriptLocation == nil ? "尚未识别到用途说明，可在编辑配置中补充。" : "未识别到脚本头部用途说明。"
                }
                Text(project.summary.isEmpty ? fallbackSummary : project.summary)
                    .foregroundStyle(project.summary.isEmpty ? .secondary : .primary).textSelection(.enabled).lineSpacing(5)
            }
            if scriptLocation == nil {
                detailSection("项目标签", symbol: "tag") {
                    if project.tags.isEmpty {
                        Text("暂无标签，添加标签后可在左侧筛选项目。").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach(project.tags, id: \.self) { tag in
                                ProjectTagLabel(tag: tag)
                            }
                        }
                    }
                    Button("编辑标签", systemImage: "pencil") { editingTags = true }
                        .buttonStyle(.borderless)
                }
            }
            if !project.detected.sourceURL.isEmpty {
                detailSection("项目来源", symbol: "arrow.triangle.branch") {
                    Text(project.detected.sourceURL).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text("来源：.git/config · remote origin").font(.caption).foregroundStyle(.secondary)
                }
            }
            detailSection("本地识别结果", symbol: "doc.text.magnifyingglass") {
                if project.detected.evidence.isEmpty {
                    Text(project.kind == .folder ? "未找到项目识别信息，可按需要补充用途和备注。" : "未找到明确的环境和依赖声明，请手动补充运行配置。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(project.detected.evidence.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.label).font(.callout.weight(.medium))
                        Text(item.value).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary).lineLimit(12)
                        Text("来源：\(item.source)").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 6)
                }
            }
            if scriptLocation == nil {
                detailSection("使用备注", symbol: "note.text") {
                    Text(project.notes.isEmpty ? "记录运行步骤、注意事项，或下次使用时需要的信息。" : project.notes)
                        .foregroundStyle(project.notes.isEmpty ? .secondary : .primary).textSelection(.enabled)
                }
            }
            HStack {
                Text("最近扫描：\(project.lastScannedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if !project.isMissing && scriptLocation == nil {
                    Button("重新定位…") { relocate() }.font(.caption).disabled(projectStatus.isActive || store.isScanning)
                }
            }
        }
    }

    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailSection("启动命令", symbol: "terminal") {
                Text(project.configuration.command.isEmpty ? "尚未选择启动入口" : project.configuration.command)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                if !project.configuration.arguments.isEmpty {
                    Text("附加参数：\(project.configuration.arguments)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Text(project.needsConfiguration ? "首次启动前需要检查并保存配置。" : "已由你确认，重新扫描会保留此配置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            detailSection("运行环境", symbol: "shippingbox") {
                LabeledContent("工作目录", value: project.configuration.workingDirectory).textSelection(.enabled)
                LabeledContent("环境 bin 目录", value: project.configuration.runtimeDirectory.isEmpty ? "系统 PATH" : project.configuration.runtimeDirectory).textSelection(.enabled)
                LabeledContent("运行方式", value: project.configuration.mode.title)
                let names = RuntimeEnvironment.requiredNames(project.configuration)
                LabeledContent("必需变量", value: names.isEmpty ? "未指定" : names.joined(separator: ", "))
            }
            detailSection("停止方式", symbol: "stop.circle") {
                Text(project.configuration.stopCommand.isEmpty ? "终止 Orbitloom 为本次运行创建的进程组。" : project.configuration.stopCommand)
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("停止等待超时后会强制结束本实例。退出应用前会提示停止仍在运行的项目。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !project.detected.launchOptions.isEmpty {
                detailSection("识别到的启动入口", symbol: "list.bullet.rectangle") {
                    ForEach(project.detected.launchOptions) { option in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            Text(option.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
    }

    /// 为项目状态提供紧凑且独立的文字标记。
    private func badge(_ title: String, color: Color) -> some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.09), in: Capsule())
    }

    /// 统一详情分区的标题、间距和内容容器。
    private func detailSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 重新关联项目位置，保留备注并要求复核保存过的命令。
    private func relocate() {
        guard let url = FilePanels.chooseProject() else { return }
        Task { await store.relocate(id: project.id, to: url) }
    }

    /// 将当前脚本的身份和路径交给主窗口，在底部抽屉查看对应结果。
    private func showResult() {
        onShowResult(RunResultSelection(id: project.id, projectID: scriptLocation?.projectID ?? project.id,
                                       title: project.name, path: project.path))
    }

    /// 启动后将脚本结果展示在底部抽屉；目录主命令沿用详情中的日志页签。
    private func start() {
        do {
            if let scriptLocation { try store.validateScript(project, at: scriptLocation) }
            runner.start(project)
            if project.isDirectory { tab = "logs" }
            else { showResult() }
        } catch { runner.errorMessage = error.localizedDescription }
    }
}
