import SwiftUI

struct ScanDiscoveryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: ScanResult?
    @State private var selectedIDs: Set<UUID> = []

    private var candidates: [Project] {
        let knownPaths = Set(store.projects.map(\.path))
        return (result?.projects ?? []).filter { !knownPaths.contains($0.path) }
    }

    private var candidateIDs: Set<UUID> { Set(candidates.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("扫描发现", systemImage: "magnifyingglass").font(.title2.weight(.semibold))
            Text("查看候选项目的路径和识别依据，勾选需要的项目后再添加到资料库。")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("扫描目录（\(store.locations.count)）").font(.callout.weight(.medium))
                        Spacer()
                        Button("添加目录…", systemImage: "plus") {
                            if let url = FilePanels.chooseDirectory(title: "选择扫描目录") { store.addLocation(url) }
                        }.disabled(store.isScanning)
                        Button(result == nil ? "开始扫描" : "重新扫描", systemImage: "arrow.clockwise") {
                            Task { await discover() }
                        }.disabled(store.isScanning || store.locations.isEmpty)
                    }
                    if store.locations.isEmpty {
                        Text("先添加项目所在的目录。添加目录不会自动收录项目。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(store.locations) { location in
                                    Text(location.path).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(.caption, design: .monospaced)).frame(maxHeight: 70)
                        Text("可在设置中移除扫描目录。").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(6)
            }

            if store.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(store.scanMessage).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if result == nil {
                ContentUnavailableView("扫描后预览候选", systemImage: "folder.badge.questionmark",
                                       description: Text("扫描只发现项目，不会自动添加到资料库。"))
            } else if candidates.isEmpty {
                ContentUnavailableView("没有待添加的候选", systemImage: "checkmark.circle",
                                       description: Text("已收录的项目会跳过。你也可以添加其他扫描目录，或手动添加项目和脚本。"))
            } else {
                HStack {
                    Text("\(candidates.count) 个候选 · 已选 \(selectedIDs.count) 项").font(.callout.weight(.medium))
                    Spacer()
                    Button(selectedIDs == candidateIDs ? "取消全选" : "全选候选") {
                        if selectedIDs == candidateIDs { selectedIDs.removeAll() }
                        else { selectedIDs = candidateIDs }
                    }.buttonStyle(.borderless)
                }
                List(candidates) { project in
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(project.id) },
                        set: { isSelected in
                            if isSelected { selectedIDs.insert(project.id) }
                            else { selectedIDs.remove(project.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(project.name, systemImage: project.kind.symbol).font(.headline)
                                Spacer()
                                Text(project.kind.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(project.path).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if let evidence = project.detected.evidence.first(where: { $0.label == "识别依据" }) {
                                Text(evidence.value).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }.toggleStyle(.checkbox)
                }.listStyle(.inset).border(.quaternary, width: 1)
            }

            if let result, !result.warnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("部分位置未能读取", systemImage: "exclamationmark.triangle").fontWeight(.medium)
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption).foregroundStyle(.orange).frame(maxHeight: 70)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            Divider()
            HStack {
                Text("候选默认不勾选，取消不会添加任何项目。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isScanning)
                Button("添加所选（\(selectedIDs.count)）") {
                    Task {
                        let selected = candidates.filter { selectedIDs.contains($0.id) }
                        if await store.addDiscoveredProjects(selected) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.isEmpty || store.isScanning)
            }
        }.padding(24).frame(width: 780, height: 700)
            .interactiveDismissDisabled(store.isScanning)
            .task {
                if !store.locations.isEmpty { await discover() }
            }
            .onChange(of: store.locations.map(\.path)) { _, _ in
                result = nil
                selectedIDs.removeAll()
            }
            .onChange(of: candidateIDs) { _, ids in
                selectedIDs.formIntersection(ids)
            }
    }

    /// 每次发现都清空旧候选和勾选，扫描结果只保留在当前预览窗口中。
    private func discover() async {
        selectedIDs.removeAll()
        result = nil
        result = await store.discoverProjects()
    }
}
