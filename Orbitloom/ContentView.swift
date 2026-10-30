import SwiftUI

struct ContentView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(RunManager.self) private var runner
    @State private var selection: UUID?
    @State private var search = ""
    @State private var tagFilter: TagFilter = .all
    @State private var isBatchSelecting = false
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var projectsToRemove: [Project] = []
    @State private var isShowingDiscovery = false
    @State private var isShowingAddProject = false
    @State private var result: RunResultSelection?

    private var filteredProjects: [Project] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.projects.filter { project in
            let matchesSearch = query.isEmpty || project.name.localizedCaseInsensitiveContains(query) || project.summary.localizedCaseInsensitiveContains(query)
            guard matchesSearch else { return false }
            switch tagFilter {
            case .all: return true
            case .untagged: return project.tags.isEmpty
            case .tag(let tag): return project.tags.contains(tag)
            }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var removableProjectIDs: Set<UUID> {
        Set(filteredProjects.filter { !runner.status(for: $0).isActive }.map(\.id))
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid.fill").font(.title2).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orbitloom").font(.headline)
                        Text("本地项目，随时就绪").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(20)
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索名称或用途", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                        }
                    }.padding(9).frame(maxWidth: .infinity)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    tagFilterControls.frame(width: 100)
                }.padding(.horizontal, 16)
                HStack {
                    Text("项目资料库").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(filteredProjects.count)").font(.caption.monospacedDigit())
                    Button("添加", systemImage: "plus") { isShowingAddProject = true }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.indigo)
                        .help("手动添加项目到资料库").disabled(store.isScanning)
                    Button(isBatchSelecting ? "取消" : "批量选择") {
                        isBatchSelecting.toggle()
                        selectedProjectIDs.removeAll()
                    }.buttonStyle(.borderless).font(.caption).foregroundStyle(.indigo)
                        .disabled(store.projects.isEmpty || (store.isScanning && !isBatchSelecting))
                }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
                if store.projects.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("还没有收录项目").font(.callout).foregroundStyle(.secondary)
                        Text("添加目录或脚本即可开始").font(.caption).foregroundStyle(.tertiary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredProjects.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的项目", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("试试其他搜索词或标签。")
                    } actions: {
                        Button("清除搜索和标签筛选") { search = ""; tagFilter = .all }
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(filteredProjects) { project in
                            let status = runner.status(for: project)
                            HStack(spacing: 8) {
                                if isBatchSelecting {
                                    Toggle("选择 \(project.name)", isOn: Binding(
                                        get: { selectedProjectIDs.contains(project.id) },
                                        set: { isSelected in
                                            if isSelected { selectedProjectIDs.insert(project.id) }
                                            else { selectedProjectIDs.remove(project.id) }
                                        }
                                    )).toggleStyle(.checkbox).labelsHidden()
                                        .disabled(status.isActive || store.isScanning)
                                }
                                ProjectRow(project: project, status: status)
                            }.tag(project.id)
                            .contextMenu {
                                Button("在 Finder 中显示") { FilePanels.reveal(project.path) }
                                Divider()
                                Button("从资料库移除…", role: .destructive) { projectsToRemove = [project] }
                                    .disabled(status.isActive || store.isScanning)
                            }
                        }
                    }.listStyle(.sidebar)
                }
                if isBatchSelecting { batchSelectionControls }
                Divider()
                HStack {
                    if store.isScanning { ProgressView().controlSize(.small) }
                    Text(store.isScanning ? store.scanMessage : "\(store.projects.count) 个项目 · 本地资料库").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("扫描目录设置")
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let selection, let project = store.project(id: selection) {
                ProjectDetailView(project: project, onShowResult: { result = $0 }).id(project.id)
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 62, weight: .light)).foregroundStyle(.indigo.gradient)
                    VStack(spacing: 10) {
                        Text("让项目随时可用").font(.system(size: 28, weight: .semibold))
                        Text("集中整理散落的脚本与项目，保存运行方式。\n下次需要时，搜索、启动，就这么简单。")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    HStack(spacing: 12) {
                        Button("添加项目或脚本", systemImage: "plus") { isShowingAddProject = true }
                            .buttonStyle(.borderedProminent).tint(.indigo).disabled(store.isScanning)
                        Button("扫描发现", systemImage: "magnifyingglass") { isShowingDiscovery = true }.buttonStyle(.bordered).disabled(store.isScanning)
                    }
                    HStack(spacing: 20) {
                        Label("Python", systemImage: "chevron.left.forwardslash.chevron.right")
                        Label("Node.js", systemImage: "shippingbox")
                        Label("Shell", systemImage: "terminal")
                    }.font(.caption).foregroundStyle(.tertiary).padding(.top, 10)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("刷新已收录项目", systemImage: "arrow.clockwise") { Task { await store.refreshProjects() } }.disabled(store.isScanning)
                Button("扫描发现", systemImage: "magnifyingglass") { isShowingDiscovery = true }.disabled(store.isScanning)
                Button("添加项目", systemImage: "plus") { isShowingAddProject = true }
                    .keyboardShortcut("o", modifiers: .command).disabled(store.isScanning)
            }
        }
        .sheet(isPresented: $isShowingDiscovery) {
            ScanDiscoveryView().environment(store)
        }
        .sheet(isPresented: $isShowingAddProject) {
            AddProjectView { id in
                search = ""
                tagFilter = .all
                isBatchSelecting = false
                selectedProjectIDs.removeAll()
                selection = id
            }.environment(store)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = store.errorMessage ?? runner.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("关闭", systemImage: "xmark") { store.errorMessage = nil; runner.errorMessage = nil }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }.padding(14).background(.orange.opacity(0.1))
            }
        }
        .confirmationDialog("从资料库移除 \(projectsToRemove.count) 个项目？", isPresented: Binding(get: { !projectsToRemove.isEmpty }, set: { if !$0 { projectsToRemove = [] } }), titleVisibility: .visible) {
            if !projectsToRemove.isEmpty {
                let projects = projectsToRemove
                Button(projects.count == 1 ? "移除 \(projects[0].name)" : "移除这 \(projects.count) 个项目", role: .destructive) {
                    removeProjects(ids: Set(projects.map(\.id)))
                }
                .disabled(store.isScanning || projects.contains { runner.status(for: $0).isActive })
            }
            Button("取消", role: .cancel) { projectsToRemove = [] }
        } message: { Text("只移除索引和保存的配置，磁盘文件不受影响。移除后不会自动重新收录；再次扫描时可重新勾选添加。") }
        .onChange(of: removableProjectIDs) { _, ids in
            selectedProjectIDs.formIntersection(ids)
        }
        .overlay(alignment: .bottom) {
            if let result {
                RunResultsDrawer(result: result, onClose: { self.result = nil })
                    .id(result.id).frame(height: 320)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: result != nil)
        .clipped()
        .frame(minWidth: 980, minHeight: 650)
    }

    private var tagFilterControls: some View {
        HStack(spacing: 4) {
            Picker("标签", selection: $tagFilter) {
                Text("全部标签").tag(TagFilter.all)
                Text("无标签").tag(TagFilter.untagged)
                ForEach(store.allTags, id: \.self) { tag in
                    Text(tag).tag(TagFilter.tag(tag))
                }
                if case .tag(let tag) = tagFilter, !store.allTags.contains(tag) {
                    Text("\(tag)（无项目）").tag(TagFilter.tag(tag))
                }
            }.pickerStyle(.menu).labelsHidden()
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity)
                .accessibilityLabel("标签筛选").help("按标签筛选项目")
            if tagFilter != .all {
                Button { tagFilter = .all } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除标签筛选")
            }
        }.font(.caption)
    }

    private var batchSelectionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("已选 \(selectedProjectIDs.count) 项").foregroundStyle(.secondary)
                Spacer()
                Button(!removableProjectIDs.isEmpty && selectedProjectIDs == removableProjectIDs ? "取消全选" : "全选当前结果") {
                    if selectedProjectIDs == removableProjectIDs { selectedProjectIDs.removeAll() }
                    else { selectedProjectIDs = removableProjectIDs }
                }.buttonStyle(.borderless)
                    .disabled(removableProjectIDs.isEmpty || store.isScanning)
            }.font(.caption)
            Button(role: .destructive) {
                projectsToRemove = filteredProjects.filter { selectedProjectIDs.contains($0.id) }
            } label: {
                Label("移除已选（\(selectedProjectIDs.count)）", systemImage: "trash").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(.red)
                .disabled(selectedProjectIDs.isEmpty || store.isScanning)
            Text("运行中或停止中的项目不可选择。").font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }

    /// 确认项目可移除后统一保存，仅在成功时清理详情和批量勾选状态。
    private func removeProjects(ids: Set<UUID>) {
        guard !store.isScanning else {
            store.errorMessage = "正在扫描，请等待扫描完成后再移除项目。"
            return
        }
        guard !store.projects.contains(where: { ids.contains($0.id) && runner.status(for: $0).isActive }) else {
            store.errorMessage = "所选项目仍在运行或停止中，请先停止后再移除。"
            return
        }
        guard store.removeProjects(ids: ids) else { return }
        if let result, ids.contains(result.projectID) { self.result = nil }
        if let selection, ids.contains(selection) { self.selection = nil }
        selectedProjectIDs.subtract(ids)
        if selectedProjectIDs.isEmpty { isBatchSelecting = false }
        projectsToRemove = []
    }

}

private enum TagFilter: Hashable {
    case all, untagged, tag(String)
}

private struct ProjectRow: View {
    let project: Project
    let status: RunStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: project.kind.symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(.indigo).frame(width: 34, height: 34)
                .background(.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(project.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 2)
                    Circle().fill(status.color).frame(width: 6, height: 6).help(status.title)
                }
                Text(project.summary.isEmpty ? "暂无用途说明" : project.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !project.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(project.tags.prefix(2)), id: \.self) { tag in
                            ProjectTagLabel(tag: tag)
                        }
                        if project.tags.count > 2 {
                            Text("+\(project.tags.count - 2)").font(.caption2).foregroundStyle(.secondary)
                                .help(project.tags.dropFirst(2).joined(separator: "、"))
                        }
                    }
                }
                Text(project.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(project.kind.title)
                    Text("·")
                    Text(status.title).foregroundStyle(status.color)
                    if project.isMissing { Text("· 原位置不存在").foregroundStyle(.orange) }
                    else if project.needsConfiguration { Text("· 待配置").foregroundStyle(.orange) }
                }.font(.system(size: 10))
            }
        }.padding(.vertical, 8)
    }
}

extension RunStatus {
    var color: Color {
        switch self {
        case .idle, .stopped: .secondary
        case .running, .completed: .green
        case .stopping: .orange
        case .failed: .red
        }
    }
}
