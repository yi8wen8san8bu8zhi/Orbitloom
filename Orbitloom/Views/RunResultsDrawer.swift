import SwiftUI

struct RunResultSelection: Identifiable {
    let id: UUID
    let projectID: UUID
    let title: String
    let path: String
}

struct RunResultsDrawer: View {
    let result: RunResultSelection
    @Binding var height: CGFloat
    let maximumHeight: CGFloat
    let onClose: () -> Void
    @Environment(RunManager.self) private var runner
    @State private var followLog = true
    @State private var resizeStartHeight: CGFloat?

    private var run: RunSnapshot { runner.snapshot(for: result.id) }
    private var displayedHeight: CGFloat { min(maximumHeight, max(220, height)) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            resizeHandle
            HStack(spacing: 16) {
                Image(systemName: "terminal").font(.title3).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(result.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(result.path)
                }
                Spacer()
                Label(run.status.title, systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(run.status.color).help(run.detail)
                Button("停止", systemImage: "stop.fill") { runner.stop(result.id) }
                    .disabled(run.status != .running)
                Button("收起结果", systemImage: "chevron.down") { onClose() }
                    .labelStyle(.iconOnly).keyboardShortcut(.cancelAction)
                    .help("收起结果，不停止脚本")
            }.padding(.horizontal, 22).padding(.vertical, 12)
            if !run.detail.isEmpty {
                Text(run.detail).font(.caption).foregroundStyle(run.status.color)
                    .lineLimit(2).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.bottom, 8)
            }
            Divider()
            RunLogView(run: run, followLog: $followLog)
        }
        .frame(height: displayedHeight)
        .background(.background)
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
        .task(id: result.id) { runner.loadLog(for: result.id) }
    }

    /// 拖动抽屉顶部调整高度，使用全局位移避免顶部移动影响拖动距离。
    private var resizeHandle: some View {
        Capsule().fill(.secondary.opacity(0.5))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity).frame(height: 10)
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .help("上下拖动调整终端高度")
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let startHeight = resizeStartHeight ?? displayedHeight
                        resizeStartHeight = startHeight
                        height = min(maximumHeight, max(220, startHeight - value.translation.height))
                    }
                    .onEnded { _ in resizeStartHeight = nil }
            )
    }
}

struct RunLogView: View {
    let run: RunSnapshot
    @Binding var followLog: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("最近一次运行", systemImage: "terminal").font(.caption.weight(.medium))
                Text("保留最新 1 MB").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("跟随输出", isOn: $followLog).toggleStyle(.checkbox).font(.caption)
                Button("复制日志", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.log, forType: .string)
                }.disabled(run.log.isEmpty)
            }.padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(run.log.isEmpty ? "暂无运行日志。启动后，输出会显示在这里。" : run.log)
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.81, green: 0.85, blue: 0.91))
                                .textSelection(.enabled).lineSpacing(4).fixedSize(horizontal: true, vertical: true)
                            Color.clear.frame(width: 1, height: 1).id("logEnd")
                        }.padding(22)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }.background(Color(red: 0.075, green: 0.085, blue: 0.115))
                        .onChange(of: run.log) { _, _ in if followLog { proxy.scrollTo("logEnd", anchor: .bottomLeading) } }
                        .onChange(of: geometry.size) { _, _ in if followLog { proxy.scrollTo("logEnd", anchor: .bottomLeading) } }
                        .onAppear { if followLog { proxy.scrollTo("logEnd", anchor: .bottomLeading) } }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
