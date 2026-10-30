import SwiftUI

struct AddProjectView: View {
    let onAdded: (UUID) -> Void
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var project: Project?
    @State private var name = ""
    @State private var summary = ""
    @State private var tagsText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var existingProject: Project? {
        guard let project else { return nil }
        return store.projects.first { $0.path == project.path }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("添加项目到资料库", systemImage: "folder.badge.plus").font(.title2.weight(.semibold))
                Text("选择本地项目目录或脚本，填写名称和用途后保存。")
                    .font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            Divider()
            Form {
                Section("项目位置") {
                    HStack {
                        if let project {
                            Label(project.isDirectory ? "项目目录" : "独立脚本", systemImage: project.isDirectory ? "folder" : "doc.text")
                        } else {
                            Text("尚未选择目录或脚本").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(project == nil ? "选择…" : "重新选择…") { chooseProject() }
                            .disabled(isWorking)
                    }
                    if let project {
                        Text(project.path).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        LabeledContent("识别类型", value: project.kind.title)
                    }
                }
                if let existingProject {
                    Section {
                        Label("这个项目已在资料库中", systemImage: "checkmark.circle")
                        Text(existingProject.name).font(.headline)
                        Text("可直接打开已有项目，名称、用途和运行配置将保持原样。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("项目信息") {
                        TextField("项目名称（必填）", text: $name)
                        TextField("用途简介（可选）", text: $summary, axis: .vertical).lineLimit(3...6)
                    }.disabled(project == nil || isWorking)
                    Section("项目标签") {
                        ProjectTagsInput(text: $tagsText, availableTags: store.allTags)
                    }.disabled(project == nil || isWorking)
                }
            }.formStyle(.grouped)
            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取或保存项目信息…").font(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 12)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Text("保存后可在详情中配置运行方式。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
                Button(existingProject == nil ? "保存到资料库" : "打开已有项目") {
                    if let existingProject {
                        onAdded(existingProject.id)
                        dismiss()
                    } else {
                        Task { await save() }
                    }
                }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.defaultAction)
                    .disabled(isWorking || project == nil || (existingProject == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }.padding(20)
        }.frame(width: 660, height: 640)
            .interactiveDismissDisabled(isWorking)
    }

    /// 读取所选路径并预填名称和用途，只更新表单草稿，不收录项目。
    private func chooseProject() {
        guard let url = FilePanels.chooseProject() else { return }
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let found = try await Task.detached(priority: .userInitiated) { try ProjectScanner.inspect(url.path) }.value
                project = found
                name = found.name
                summary = found.summary
                tagsText = ""
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// 保存完成后选中资料库条目；失败时保留填写内容，供用户修正或重试。
    private func save() async {
        guard let project else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let id = try await store.addProject(at: URL(fileURLWithPath: project.path), name: name, summary: summary, tagsText: tagsText)
            onAdded(id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
