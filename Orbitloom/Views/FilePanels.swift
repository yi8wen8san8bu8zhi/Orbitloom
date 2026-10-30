import AppKit

@MainActor
enum FilePanels {
    /// 使用系统选择器获取一个项目目录或脚本路径。
    static func chooseProject() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择项目目录或独立脚本"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 选择扫描位置、工作目录或已有环境目录。
    static func chooseDirectory(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "选择目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 在 Finder 中定位项目，便于用户自行维护文件。
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
