import Foundation

nonisolated struct ProjectScanner {
    static let excludedDirectories: Set<String> = [
        "node_modules", "vendor", "venv", "env", ".venv", ".env", "__pycache__",
        "build", "dist", "out", "target", "DerivedData", ".git", ".next", ".tox",
        ".mypy_cache", ".pytest_cache", "site-packages", "coverage", ".build"
    ]

    /// 规范化路径并解析符号链接，让重叠扫描位置共享同一个项目标识。
    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// 返回项目边界的识别依据，包括尚需手动配置的 Maven 和 Gradle 项目。
    static func projectMarker(_ url: URL) -> String? {
        let markers = [
            "package.json", "pyproject.toml", "requirements.txt", "setup.py", "setup.cfg",
            "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
            ".git", "main.py", "app.py", "__main__.py"
        ]
        return markers.first { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    /// 识别独立脚本；无扩展名时只读取 shebang，不执行文件。
    static func scriptKind(_ url: URL) -> ProjectKind? {
        switch url.pathExtension.lowercased() {
        case "py": return .python
        case "js", "mjs", "cjs": return .node
        case "sh", "bash", "zsh": return .shell
        case "":
            let firstLine = ProjectParser.readText(url, limit: 256).components(separatedBy: .newlines).first ?? ""
            guard firstLine.hasPrefix("#!") else { return nil }
            if firstLine.contains("python") { return .python }
            if firstLine.contains("node") { return .node }
            if ["/sh", "bash", "zsh", "env sh"].contains(where: firstLine.contains) { return .shell }
            return nil
        default: return nil
        }
    }

    /// 收录单个目录或脚本，并给出读取权限、文件类型等可操作的错误。
    static func inspect(_ path: String) throws -> Project {
        let canonical = canonicalPath(path)
        let url = URL(fileURLWithPath: canonical)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let isDirectory = values.isDirectory == true
        guard isDirectory || (values.isRegularFile == true && scriptKind(url) != nil) else {
            throw OrbitloomError.message("请选择项目目录或 Python、Node.js、Shell 脚本。")
        }
        guard FileManager.default.isReadableFile(atPath: canonical) else {
            throw OrbitloomError.message("无法读取 \(canonical)，请检查目录权限。")
        }
        var detected = ProjectParser.parse(url, isDirectory: isDirectory)
        if isDirectory, let marker = projectMarker(url) {
            detected.evidence.insert(Evidence(label: "识别依据", value: "项目目录 · 检测到 \(marker)", source: marker), at: 0)
        } else if !isDirectory {
            let basis = url.pathExtension.isEmpty ? "shebang 解释器声明" : ".\(url.pathExtension) 扩展名"
            detected.evidence.insert(Evidence(label: "识别依据", value: "脚本文件 · \(basis)", source: url.lastPathComponent), at: 0)
        }
        return Project(path: canonical, isDirectory: isDirectory, detected: detected)
    }

    /// 只发现尚未收录的候选项目，遇到项目边界停止下钻，不刷新或保存资料库。
    static func scan(locations: [String], existingPaths: [String]) -> ScanResult {
        var result = ScanResult()
        var visited = Set(existingPaths.map(canonicalPath))
        let manager = FileManager.default

        var roots: [String] = []
        for path in Set(locations.map(canonicalPath)).sorted(by: { $0.count < $1.count }) {
            if !roots.contains(where: { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }) { roots.append(path) }
        }
        for source in roots {
            let root = URL(fileURLWithPath: canonicalPath(source))
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  manager.isReadableFile(atPath: root.path) else {
                result.warnings.append("扫描位置不可用：\(root.path)")
                continue
            }
            if projectMarker(root) != nil {
                if visited.insert(root.path).inserted {
                    do { result.projects.append(try inspect(root.path)) }
                    catch { result.warnings.append(error.localizedDescription) }
                }
                continue
            }
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    result.warnings.append("无法扫描 \(url.path)：\(error.localizedDescription)")
                    return true
                }
            ) else { continue }

            for case let url as URL in enumerator {
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true {
                        enumerator.skipDescendants()
                        continue
                    }
                    if values.isDirectory == true {
                        if excludedDirectories.contains(url.lastPathComponent) {
                            enumerator.skipDescendants()
                            continue
                        }
                        guard projectMarker(url) != nil else { continue }
                        enumerator.skipDescendants()
                    } else if values.isRegularFile != true
                                || ["mvnw", "gradlew"].contains(url.lastPathComponent.lowercased())
                                || scriptKind(url) == nil {
                        continue
                    }
                    let path = canonicalPath(url.path)
                    if visited.insert(path).inserted { result.projects.append(try inspect(path)) }
                } catch {
                    result.warnings.append("无法读取 \(url.path)：\(error.localizedDescription)")
                }
            }
        }

        result.projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    /// 只读取已收录路径的最新信息，不遍历扫描目录，也不发现新项目。
    static func refresh(paths: [String]) -> ScanResult {
        var result = ScanResult()
        for path in paths where FileManager.default.fileExists(atPath: path) {
            do { result.projects.append(try inspect(path)) }
            catch { result.warnings.append("无法刷新 \(path)：\(error.localizedDescription)") }
        }
        return result
    }
}
