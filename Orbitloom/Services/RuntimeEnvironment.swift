import Foundation

nonisolated struct RuntimeEnvironment {
    /// 解析显式输入的环境变量；值按原文传递，不求值 shell 表达式。
    static func overrides(_ text: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { throw OrbitloomError.message("环境变量第 \(index + 1) 行应为 KEY=VALUE。") }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw OrbitloomError.message("环境变量名称无效：\(key)")
            }
            let value = String(line[line.index(after: separator)...])
            guard !value.contains("\0") else { throw OrbitloomError.message("环境变量不能包含空字符。") }
            values[key] = value
        }
        return values
    }

    /// 在配置保存入口校验格式，实际路径和运行时在启动时检查。
    static func validateConfiguration(_ configuration: RunConfiguration) throws {
        guard !configuration.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrbitloomError.message("请填写启动命令，或从识别结果中选择入口。")
        }
        guard configuration.workingDirectory.hasPrefix("/") || configuration.workingDirectory.hasPrefix("~/") else {
            throw OrbitloomError.message("工作目录需要使用绝对路径或 ~/ 路径。")
        }
        for value in [configuration.command, configuration.arguments, configuration.stopCommand, configuration.workingDirectory, configuration.runtimeDirectory] {
            guard !value.contains("\0") else { throw OrbitloomError.message("运行配置不能包含空字符。") }
        }
        _ = try overrides(configuration.environmentText)
        for name in requiredNames(configuration) {
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw OrbitloomError.message("必需环境变量名称无效：\(name)")
            }
        }
    }

    /// 将必需变量名称按空白或逗号拆分，供配置检查和运行前检查共享。
    static func requiredNames(_ configuration: RunConfiguration) -> [String] {
        configuration.requiredEnvironment.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))).filter { !$0.isEmpty }
    }

    /// 继承应用环境并补充常见工具目录；用户选择的 bin 目录具有最高优先级。
    static func build(_ configuration: RunConfiguration) throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let custom = try overrides(configuration.environmentText)
        environment.merge(custom) { _, new in new }
        var paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !paths.contains(path) { paths.append(path) }
        if !configuration.runtimeDirectory.isEmpty {
            let bin = ProjectScanner.canonicalPath(configuration.runtimeDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: bin, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw OrbitloomError.message("所选环境 bin 目录不存在：\(bin)")
            }
            paths.insert(bin, at: 0)
            let root = URL(fileURLWithPath: bin).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("pyvenv.cfg").path) { environment["VIRTUAL_ENV"] = root.path }
        }
        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TERM"] = "dumb"
        for name in requiredNames(configuration) where environment[name, default: ""].isEmpty {
            throw OrbitloomError.message("缺少必需环境变量 \(name)。请在运行配置中填写，或核对该变量是否确实必需。")
        }
        return environment
    }

    /// 检查可识别命令的可执行文件是否存在，不运行探测命令或安装任何内容。
    static func preflight(command: String, workingDirectory: String, environment: [String: String]) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OrbitloomError.message("工作目录不存在：\(workingDirectory)")
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let first: String
        if let quote = trimmed.first, quote == "'" || quote == "\"", let end = trimmed.dropFirst().firstIndex(of: quote) {
            first = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        } else { first = String(trimmed.prefix { !$0.isWhitespace }) }
        let known = ["python", "python3", "node", "npm", "pnpm", "yarn", "bun", "sh", "bash", "zsh", "uv", "poetry"]
        guard known.contains(first) || first.hasPrefix("/") || first.hasPrefix("./") else { return }
        let candidates: [String]
        if first.hasPrefix("/") { candidates = [first] }
        else if first.hasPrefix("./") { candidates = [URL(fileURLWithPath: workingDirectory).appendingPathComponent(first).path] }
        else { candidates = environment["PATH", default: ""].split(separator: ":").map { String($0) + "/" + first } }
        guard candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw OrbitloomError.message("未找到可执行的 \(first)。请准备好运行环境，并选择对应的 bin 目录。")
        }
    }
}
