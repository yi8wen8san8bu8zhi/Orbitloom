import Foundation

nonisolated struct ProjectParser {
    /// 有界读取文本，避免大型文档阻塞扫描；不可读内容交由手动配置补充。
    static func readText(_ url: URL, limit: Int = 262_144) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 将路径和参数作为一个 shell 参数引用，保留空格、引号和特殊字符。
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 提取简单配置中某个节的单行键值；复杂、多行声明留给用户确认。
    static func sectionValues(_ text: String, section: String) -> [String: String] {
        var currentSection = ""
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }
            guard currentSection == section, !line.hasPrefix("#"), !line.hasPrefix(";"),
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let raw = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !raw.hasPrefix("\"\"\""), !raw.hasPrefix("'''"), !raw.isEmpty else { continue }
            if let quote = raw.first, quote == "\"" || quote == "'", let end = raw.dropFirst().firstIndex(of: quote) {
                values[key] = String(raw[raw.index(after: raw.startIndex)..<end])
            } else {
                values[key] = raw.components(separatedBy: " #")[0]
            }
        }
        return values
    }

    /// 从 README 的首段正文提取简介，忽略标题、徽章、表格和代码块。
    static func readmeSummary(_ text: String) -> String {
        var inCode = false
        var paragraph: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inCode.toggle(); continue }
            if inCode { continue }
            if line.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            if ["#", "![", "[![", "<", "|", "---", "===", "[", "- ", "* "].contains(where: line.hasPrefix) { continue }
            paragraph.append(line)
            if paragraph.joined(separator: " ").count >= 400 { break }
        }
        return String(paragraph.joined(separator: " ").prefix(500))
    }

    /// 从脚本头部的注释或 Python 文档字符串提取用途说明。
    static func scriptSummary(_ text: String) -> String {
        var lines: [String] = []
        var inDocstring = false
        for raw in text.components(separatedBy: .newlines).prefix(24) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#!") || line.contains("coding:") || line.contains("coding=") { continue }
            if line.isEmpty { if !lines.isEmpty { break }; continue }
            if line.hasPrefix("\"\"\"") || line.hasPrefix("'''") {
                let content = line.replacingOccurrences(of: "\"\"\"", with: "").replacingOccurrences(of: "'''", with: "")
                if !content.isEmpty { lines.append(content) }
                if line.count > 3 && (line.hasSuffix("\"\"\"") || line.hasSuffix("'''")) { break }
                inDocstring.toggle()
                if !inDocstring { break }
            } else if inDocstring {
                lines.append(line)
            } else if line.hasPrefix("#") || line.hasPrefix("//") {
                lines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "#/ ")))
            } else { break }
        }
        return String(lines.joined(separator: " ").prefix(500))
    }

    /// 读取项目已有虚拟环境的 bin 目录，不创建或激活环境。
    static func pythonEnvironment(_ root: URL) -> String {
        for directory in [".venv", "venv", "env"] {
            let bin = root.appendingPathComponent(directory).appendingPathComponent("bin")
            if FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("python").path) { return bin.path }
        }
        return ""
    }

    /// 解析本地声明与文档，将每项识别结果连同来源一起返回。
    static func parse(_ url: URL, isDirectory: Bool, absoluteScriptPath: Bool = false) -> DetectedProject {
        let manager = FileManager.default
        let root = isDirectory ? url : url.deletingLastPathComponent()
        var detected = DetectedProject(name: isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent, kind: .unknown)
        if !isDirectory {
            detected.kind = ProjectScanner.scriptKind(url) ?? .unknown
            let text = readText(url)
            detected.summary = scriptSummary(text)
            let quoted = shellQuote(absoluteScriptPath ? url.path : url.lastPathComponent)
            let command: String
            switch detected.kind {
            case .python:
                detected.runtimeDirectory = pythonEnvironment(root)
                command = "python3 \(quoted)"
            case .node: command = "node \(quoted)"
            case .shell:
                let first = text.components(separatedBy: .newlines).first ?? ""
                let interpreter: String
                if first.contains("zsh") || url.pathExtension == "zsh" { interpreter = "/bin/zsh" }
                else if first.contains("bash") || url.pathExtension == "bash" { interpreter = "/bin/bash" }
                else { interpreter = "/bin/sh" }
                command = "\(interpreter) \(quoted)"
            case .folder, .unknown: command = ""
            }
            detected.launchOptions = [LaunchOption(command: command, source: "\(url.lastPathComponent) · 文件类型 / shebang")]
            detected.evidence.append(Evidence(label: "简介", value: detected.summary.isEmpty ? "未发现头部说明" : detected.summary, source: url.lastPathComponent))
            return detected
        }

        let packageURL = root.appendingPathComponent("package.json")
        if manager.fileExists(atPath: packageURL.path) {
            detected.kind = .node
            let packageText = readText(packageURL)
            if let object = try? JSONSerialization.jsonObject(with: Data(packageText.utf8)) as? [String: Any] {
                if let name = object["name"] as? String, !name.isEmpty { detected.name = name }
                detected.summary = object["description"] as? String ?? ""
                if let engines = object["engines"] as? [String: String] {
                    detected.evidence.append(Evidence(label: "运行环境", value: engines.keys.sorted().map { "\($0) \(engines[$0]!)" }.joined(separator: ", "), source: "package.json · engines"))
                }
                for field in ["dependencies", "devDependencies"] {
                    if let dependencies = object[field] as? [String: String], !dependencies.isEmpty {
                        detected.evidence.append(Evidence(label: field == "dependencies" ? "依赖声明" : "开发依赖", value: dependencies.keys.sorted().map { "\($0) \(dependencies[$0]!)" }.joined(separator: ", "), source: "package.json · \(field)"))
                    }
                }
                var packageManager = "npm"
                let declaredManager = object["packageManager"] as? String ?? ""
                if declaredManager.hasPrefix("pnpm@") || manager.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { packageManager = "pnpm" }
                else if declaredManager.hasPrefix("yarn@") || manager.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { packageManager = "yarn" }
                else if declaredManager.hasPrefix("bun@") || manager.fileExists(atPath: root.appendingPathComponent("bun.lock").path) || manager.fileExists(atPath: root.appendingPathComponent("bun.lockb").path) { packageManager = "bun" }
                if let scripts = object["scripts"] as? [String: String] {
                    let names = scripts.keys.filter { !["install", "postinstall", "preinstall", "prepare"].contains($0) }.sorted {
                        let priorities = ["start": 0, "dev": 1, "serve": 2]
                        let left = priorities[$0, default: 3], right = priorities[$1, default: 3]
                        return left == right ? $0 < $1 : left < right
                    }
                    detected.launchOptions = names.map { LaunchOption(command: "\(packageManager) run \(shellQuote($0))", source: "package.json · scripts.\($0): \(scripts[$0]!)") }
                }
                if detected.launchOptions.isEmpty, let main = object["main"] as? String,
                   manager.fileExists(atPath: root.appendingPathComponent(main).path) {
                    detected.launchOptions.append(LaunchOption(command: "node \(shellQuote(main))", source: "package.json · main（需确认是否可直接运行）"))
                }
            } else {
                detected.evidence.append(Evidence(label: "解析提示", value: "package.json 无法解析，请手动配置。", source: "package.json"))
            }
        }

        let pythonMarkers = ["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "main.py", "app.py", "__main__.py"]
        if detected.kind == .unknown && pythonMarkers.contains(where: { manager.fileExists(atPath: root.appendingPathComponent($0).path) }) {
            detected.kind = .python
            detected.runtimeDirectory = pythonEnvironment(root)
            let pyproject = readText(root.appendingPathComponent("pyproject.toml"))
            let metadata = sectionValues(pyproject, section: "project")
            let poetry = sectionValues(pyproject, section: "tool.poetry")
            if let name = metadata["name"] ?? poetry["name"] { detected.name = name }
            detected.summary = metadata["description"] ?? poetry["description"] ?? ""
            if let version = metadata["requires-python"] {
                detected.evidence.append(Evidence(label: "运行环境", value: "Python \(version)", source: "pyproject.toml · project.requires-python"))
            }
            for section in ["project.scripts", "tool.poetry.scripts"] {
                let entries = sectionValues(pyproject, section: section)
                detected.launchOptions += entries.keys.sorted().map {
                    LaunchOption(command: shellQuote($0), source: "pyproject.toml · \(section).\($0)（需已安装到所选环境）")
                }
            }
            for entry in ["main.py", "app.py", "__main__.py"] where manager.fileExists(atPath: root.appendingPathComponent(entry).path) {
                detected.launchOptions.append(LaunchOption(command: "python3 \(shellQuote(entry))", source: "\(entry) · 常见入口（需确认）"))
            }
            for filename in ["requirements.txt", "requirements-dev.txt"] {
                let dependencies = readText(root.appendingPathComponent(filename)).components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
                if !dependencies.isEmpty { detected.evidence.append(Evidence(label: "依赖声明", value: dependencies.joined(separator: "\n"), source: filename)) }
            }
            if !pyproject.isEmpty {
                detected.evidence.append(Evidence(label: "依赖配置", value: String(pyproject.prefix(6_000)), source: "pyproject.toml（原始声明，复杂字段需手动确认）"))
            }
            let setupConfig = readText(root.appendingPathComponent("setup.cfg"))
            let setupMetadata = sectionValues(setupConfig, section: "metadata")
            if detected.summary.isEmpty { detected.summary = setupMetadata["description"] ?? "" }
            if !setupConfig.isEmpty { detected.evidence.append(Evidence(label: "依赖配置", value: String(setupConfig.prefix(4_000)), source: "setup.cfg")) }
            if manager.fileExists(atPath: root.appendingPathComponent("setup.py").path) {
                detected.evidence.append(Evidence(label: "依赖配置", value: "检测到 setup.py；扫描不会执行此文件，请核对依赖和入口。", source: "setup.py"))
            }
        }

        let children = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        if detected.kind == .unknown {
            let scripts = children.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && ProjectScanner.scriptKind($0) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let kind = scripts.first.flatMap({ ProjectScanner.scriptKind($0) }) { detected.kind = kind }
            for script in scripts {
                let parsed = parse(script, isDirectory: false)
                detected.launchOptions += parsed.launchOptions
                if detected.summary.isEmpty { detected.summary = parsed.summary }
            }
        }

        if let readme = children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first(where: { ["readme.md", "readme.rst", "readme.txt", "readme"].contains($0.lastPathComponent.lowercased()) }) {
            let text = readText(readme)
            let summary = readmeSummary(text)
            if detected.summary.isEmpty { detected.summary = summary }
            if !summary.isEmpty { detected.evidence.append(Evidence(label: "用途说明", value: summary, source: readme.lastPathComponent)) }
            var inCode = false
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("```") || line.hasPrefix("~~~") { inCode.toggle(); continue }
                let command = line.hasPrefix("$ ") ? String(line.dropFirst(2)) : line
                let prefixes = ["python ", "python3 ", "node ", "npm run ", "npm start", "pnpm run ", "pnpm start", "yarn run ", "yarn start", "bash ", "sh ", "zsh ", "./"]
                guard inCode, prefixes.contains(where: command.hasPrefix), command.count < 400,
                      !command.hasSuffix("\\"), !command.contains(" install"), !command.contains("pip ") else { continue }
                detected.launchOptions.append(LaunchOption(command: command, source: "\(readme.lastPathComponent) · 代码块（需确认）"))
            }
        }

        for filename in [".python-version", ".nvmrc", ".node-version", ".tool-versions"] {
            let version = readText(root.appendingPathComponent(filename), limit: 2_048).trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { detected.evidence.append(Evidence(label: "版本声明", value: version, source: filename)) }
        }
        for filename in [".env.example", ".env.sample", ".env.template"] {
            let text = readText(root.appendingPathComponent(filename))
            for raw in text.components(separatedBy: .newlines) {
                var line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
                guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
                let name = line[..<separator].trimmingCharacters(in: .whitespaces)
                if name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil {
                    detected.environmentNames.append(name)
                }
            }
            if !text.isEmpty { detected.evidence.append(Evidence(label: "环境变量", value: "仅提取变量名称，是否必需请在配置中确认。", source: filename)) }
        }
        detected.environmentNames = Array(Set(detected.environmentNames)).sorted()

        var gitDirectory = root.appendingPathComponent(".git")
        let gitPointer = readText(gitDirectory, limit: 2_048).trimmingCharacters(in: .whitespacesAndNewlines)
        if gitPointer.hasPrefix("gitdir:") {
            let target = gitPointer.dropFirst(7).trimmingCharacters(in: .whitespaces)
            gitDirectory = URL(fileURLWithPath: target, relativeTo: root).standardizedFileURL
        }
        let commonDirectory = readText(gitDirectory.appendingPathComponent("commondir"), limit: 2_048).trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonDirectory.isEmpty { gitDirectory = URL(fileURLWithPath: commonDirectory, relativeTo: gitDirectory).standardizedFileURL }
        let gitConfig = readText(gitDirectory.appendingPathComponent("config"))
        detected.sourceURL = sectionValues(gitConfig, section: "remote \"origin\"")["url"] ?? ""
        if !detected.summary.isEmpty && !detected.evidence.contains(where: { $0.label == "用途说明" }) {
            detected.evidence.append(Evidence(label: "用途说明", value: detected.summary, source: detected.kind == .node ? "package.json · description" : "项目元数据 / 脚本头部"))
        }
        var seenCommands = Set<String>()
        detected.launchOptions = detected.launchOptions.filter { seenCommands.insert($0.command).inserted }
        return detected
    }
}
