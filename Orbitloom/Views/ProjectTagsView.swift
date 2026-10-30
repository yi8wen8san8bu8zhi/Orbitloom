import SwiftUI

struct ProjectTagsEditorView: View {
    let project: Project
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tagsText: String
    @State private var errorMessage: String?

    /// 从已保存的标签建立独立草稿，取消编辑不会修改资料库。
    init(project: Project) {
        self.project = project
        _tagsText = State(initialValue: project.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("编辑标签", systemImage: "tag").font(.title2.weight(.semibold))
                Text(project.name).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            Divider()
            Form {
                Section("项目标签") {
                    ProjectTagsInput(text: $tagsText, availableTags: store.allTags)
                }
            }.formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Text("标签用于整理和筛选项目。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 560, height: 430)
    }

    /// 保存标签后关闭编辑窗口；写入失败时保留草稿并显示错误。
    private func save() {
        do {
            try store.saveTags(id: project.id, text: tagsText)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ProjectTagsInput: View {
    @Binding var text: String
    let availableTags: [String]

    private var tags: [String] { Project.parseTags(text) }
    private var suggestedTags: [String] { availableTags.filter { !tags.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("标签（可选）", text: $text, axis: .vertical).lineLimit(2...4)
            Text("多个标签用逗号或换行分隔，点击 × 可移除；留空表示无标签。")
                .font(.caption).foregroundStyle(.secondary)
            if !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            ProjectTagLabel(tag: tag)
                            Button {
                                text = tags.filter { $0 != tag }.joined(separator: ", ")
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("移除标签 \(tag)")
                        }
                    }
                }
            }
            if !suggestedTags.isEmpty {
                Menu {
                    ForEach(suggestedTags, id: \.self) { tag in
                        Button(tag) { text = (tags + [tag]).joined(separator: ", ") }
                    }
                } label: { Label("使用已有标签", systemImage: "plus.circle") }
                    .fixedSize()
            }
        }
    }
}

struct ProjectTagLabel: View {
    let tag: String

    var body: some View {
        Label(tag, systemImage: "tag").font(.caption2).lineLimit(1)
            .foregroundStyle(.indigo).padding(.horizontal, 7).padding(.vertical, 4)
            .background(.indigo.opacity(0.09), in: Capsule()).help(tag)
    }
}
