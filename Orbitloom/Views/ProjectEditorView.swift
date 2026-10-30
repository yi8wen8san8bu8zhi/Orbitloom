import SwiftUI

struct ProjectEditorView: View {
    let project: Project
    let scriptLocation: ScriptLocation?
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var summary: String
    @State private var kind: ProjectKind
    @State private var notes: String
    @State private var configuration: RunConfiguration
    @State private var errorMessage: String?

    /// 从项目快照建立编辑草稿，取消编辑不会改变已保存的数据。
    init(project: Project, scriptLocation: ScriptLocation? = nil) {
        self.project = project
        self.scriptLocation = scriptLocation
        _name = State(initialValue: project.name)
        _summary = State(initialValue: project.summary)
        _kind = State(initialValue: project.kind)
        _notes = State(initialValue: project.notes)
        _configuration = State(initialValue: project.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Group {
                        if scriptLocation != nil {
                            Text("配置脚本：\(project.name)")
                        } else {
                            Text(kind == .folder ? "编辑文件夹信息" : "检查运行配置")
                        }
                    }.font(.title2.weight(.semibold))
                    Text(kind == .folder ? "文件夹用于收录和浏览内容，无需配置启动命令。" : "启动命令可留空，启动前再补充。扫描会保留你保存的修改。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                if scriptLocation == nil {
                    Section("项目信息") {
                        TextField("名称", text: $name)
                        Picker("类型", selection: $kind) {
                            ForEach(ProjectKind.allCases.filter { project.isDirectory || $0 != .folder }) { Text($0.title).tag($0) }
                        }
                        TextField("用途简介", text: $summary, axis: .vertical).lineLimit(2...5)
                        TextField("使用备注", text: $notes, axis: .vertical).lineLimit(2...6)
                    }
                }
                if kind != .folder {
                    Section {
                        if !project.detected.launchOptions.isEmpty {
                            Menu {
                                ForEach(project.detected.launchOptions) { option in
                                    Button("\(option.command) — \(option.source)") { configuration.command = option.command }
                                }
                            } label: { Label("选择识别到的入口（\(project.detected.launchOptions.count)）", systemImage: "list.bullet") }
                        }
                        TextField("启动命令（可选）", text: $configuration.command, axis: .vertical).font(.system(.body, design: .monospaced)).lineLimit(2...5)
                        TextField("附加参数（可选）", text: $configuration.arguments)
                        Picker("运行方式", selection: $configuration.mode) { ForEach(RunMode.allCases) { Text($0.title).tag($0) } }
                        HStack {
                            TextField("工作目录", text: $configuration.workingDirectory)
                            Button("选择…") {
                                if let url = FilePanels.chooseDirectory(title: "选择工作目录") { configuration.workingDirectory = url.path }
                            }
                        }
                    } header: { Text("启动") } footer: {
                        Text("命令和附加参数使用 zsh 语法，以当前用户权限执行。请确认路径、参数及命令用途。首版不支持需要终端输入的交互式命令。")
                    }
                    Section {
                        HStack {
                            TextField("环境 bin 目录（留空使用 PATH）", text: $configuration.runtimeDirectory)
                            Button("选择…") {
                                if let url = FilePanels.chooseDirectory(title: "选择解释器所在 bin 目录，例如 .venv/bin") { configuration.runtimeDirectory = url.path }
                            }
                        }
                        TextField("必需环境变量名称", text: $configuration.requiredEnvironment, axis: .vertical).lineLimit(2...4)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("环境变量值（每行 KEY=VALUE）").font(.callout)
                            TextEditor(text: $configuration.environmentText).font(.system(.callout, design: .monospaced))
                                .frame(minHeight: 85).scrollContentBackground(.hidden)
                                .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6))
                        }
                    } header: { Text("已有运行环境") } footer: {
                        Text("变量名称可按实际需要删改。值按原文传递，不使用 shell 引号或变量展开，并随配置明文保存在本机。应用不自动安装环境或依赖，也不读取项目 .env 的值。")
                    }
                    Section {
                        TextField("停止命令（可选）", text: $configuration.stopCommand, axis: .vertical).font(.system(.body, design: .monospaced)).lineLimit(2...4)
                    } header: { Text("停止") } footer: {
                        Text("留空使用实例进程组停止。自定义命令请限定到本次运行，可使用 $ORBITLOOM_PID 和 $ORBITLOOM_PGID；避免按进程名批量结束程序。")
                    }
                }
            }.formStyle(.grouped)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            HStack {
                Text(kind == .folder ? "保存后可浏览文件，并单独配置和运行目录内的脚本。" : "保存后仍需手动点击启动。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确认并保存") { save() }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 730, height: 760)
    }

    /// 保存项目信息或脚本配置；文件夹保留原运行配置，失败时保留草稿。
    private func save() {
        do {
            if let scriptLocation {
                try store.saveScriptConfiguration(configuration, script: project, at: scriptLocation)
            } else {
                try store.saveConfiguration(id: project.id, name: name, summary: summary, kind: kind, notes: notes,
                                            configuration: kind == .folder ? project.configuration : configuration)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
