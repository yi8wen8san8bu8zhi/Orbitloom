import SwiftUI

struct ScanSettingsView: View {
    @Environment(ProjectStore.self) private var store
    @State private var isShowingDiscovery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("扫描目录", systemImage: "folder.badge.gearshape").font(.title2.weight(.semibold))
            Text("保存项目可能存放的位置，需要时点击「扫描发现」并勾选添加。应用启动时只刷新已收录项目。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox {
                if store.locations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("尚未设置扫描目录").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.locations) { location in
                                HStack(spacing: 12) {
                                    Image(systemName: "folder").foregroundStyle(.indigo)
                                    Text(location.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                    Spacer()
                                    Button("移除扫描目录", systemImage: "minus.circle") { store.removeLocation(id: location.id) }
                                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.isScanning)
                                }.padding(12)
                                if location.id != store.locations.last?.id { Divider() }
                            }
                        }
                    }.frame(maxHeight: 220)
                }
            }
            HStack {
                Button("添加扫描目录…", systemImage: "plus") {
                    if let url = FilePanels.chooseDirectory(title: "选择扫描目录") { store.addLocation(url) }
                }.disabled(store.isScanning)
                Spacer()
                if store.isScanning { ProgressView().controlSize(.small) }
                Button("扫描发现", systemImage: "magnifyingglass") { isShowingDiscovery = true }.disabled(store.isScanning)
            }
            Text("跳过依赖、虚拟环境、构建产物和 mvnw、gradlew 等包装脚本；识别项目边界后停止下钻。扫描结果仅作候选，勾选后才会收录。移除扫描目录会保留已收录项目。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !store.scanMessage.isEmpty { Text(store.scanMessage).font(.callout).foregroundStyle(.secondary) }
            if !store.scanWarnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("部分位置未能读取", systemImage: "exclamationmark.triangle").font(.callout.weight(.medium))
                        ForEach(Array(store.scanWarnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 120).foregroundStyle(.orange)
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("资料库与日志仅保存在本机").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开数据目录") { FilePanels.reveal(store.dataDirectory.path) }.font(.caption)
            }
        }.padding(26).frame(width: 620, height: 560)
            .sheet(isPresented: $isShowingDiscovery) {
                ScanDiscoveryView().environment(store)
            }
    }
}
