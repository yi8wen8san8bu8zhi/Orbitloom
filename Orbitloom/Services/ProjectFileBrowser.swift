import Foundation

nonisolated struct ProjectFile: Identifiable, Sendable {
    var relativePath: String
    var name: String
    var isDirectory: Bool
    var kind: ProjectKind?

    var id: String { relativePath }
    var isSQL: Bool { (name as NSString).pathExtension.lowercased() == "sql" }
}

nonisolated enum ProjectFileBrowser {
    /// 解析目录内的相对位置，并将文件浏览和运行限制在所属项目目录内。
    static func url(root: String, relativePath: String) throws -> URL {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = rootURL.path == "/" ? "/" : rootURL.path + "/"
        guard url.path == rootURL.path || url.path.hasPrefix(prefix) else {
            throw OrbitloomError.message("文件已不在此项目目录中，请刷新文件列表。")
        }
        return url
    }

    /// 只读取当前层文件，沿用扫描器的目录忽略规则，不执行脚本或跟随符号链接。
    static func contents(root: String, relativeDirectory: String) throws -> [ProjectFile] {
        let directory = try url(root: root, relativePath: relativeDirectory)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var files: [ProjectFile] = []
        for child in children {
            let values = try child.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isPackage != true else { continue }
            let isDirectory = values.isDirectory == true
            guard isDirectory || values.isRegularFile == true else { continue }
            if isDirectory && ProjectScanner.excludedDirectories.contains(child.lastPathComponent) { continue }
            let relativePath = relativeDirectory.isEmpty ? child.lastPathComponent : relativeDirectory + "/" + child.lastPathComponent
            files.append(ProjectFile(relativePath: relativePath, name: child.lastPathComponent, isDirectory: isDirectory,
                                     kind: isDirectory ? nil : ProjectScanner.scriptKind(child)))
        }
        return files.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 在脚本打开、保存和启动入口检查当前位置与支持的文件类型。
    static func scriptURL(root: String, relativePath: String) throws -> URL {
        let file = try url(root: root, relativePath: relativePath)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true, ProjectScanner.scriptKind(file) != nil else {
            throw OrbitloomError.message("此文件不是支持的 Python、Node.js 或 Shell 脚本。")
        }
        guard FileManager.default.isReadableFile(atPath: file.path) else {
            throw OrbitloomError.message("无法读取脚本，请检查文件权限。")
        }
        return file
    }

    /// 为目录内脚本生成独立运行草稿，使用绝对文件路径以允许修改工作目录。
    static func inspectScript(root: String, relativePath: String) throws -> Project {
        let file = try scriptURL(root: root, relativePath: relativePath)
        let detected = ProjectParser.parse(file, isDirectory: false, absoluteScriptPath: true)
        var project = Project(path: file.path, isDirectory: false, detected: detected)
        project.customName = file.lastPathComponent
        return project
    }
}
