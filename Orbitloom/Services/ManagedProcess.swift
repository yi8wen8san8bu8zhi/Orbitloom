import Darwin
import Foundation

nonisolated struct ProcessExit: Sendable {
    var code: Int32
    var signal: Int32
    var succeeded: Bool { code == 0 && signal == 0 }
    var description: String { signal == 0 ? "退出码 \(code)" : "被信号 \(signal) 终止" }
}

nonisolated final class ManagedProcess: Sendable {
    let pid: pid_t

    /// 原子创建独立进程组，在指定目录运行命令，并合并捕获 stdout/stderr。
    init(command: String, directory: String, environment: [String: String], onOutput: @escaping @MainActor @Sendable (Data) -> Void, onExit: @escaping @MainActor @Sendable (ProcessExit) -> Void) throws {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw OrbitloomError.message("无法创建日志管道：\(String(cString: strerror(errno)))") }
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        _ = fcntl(readDescriptor, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeDescriptor, F_SETFD, FD_CLOEXEC)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
            close(writeDescriptor)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, readDescriptor)
        posix_spawn_file_actions_addclose(&actions, writeDescriptor)
        let directoryResult = posix_spawn_file_actions_addchdir(&actions, directory)
        guard directoryResult == 0 else {
            close(readDescriptor)
            throw OrbitloomError.message("无法设置工作目录：\(String(cString: strerror(directoryResult)))")
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGPIPE, SIGHUP, SIGQUIT] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        let argumentValues: [String] = ["/bin/zsh", "-f", "-c", command]
        let argumentPointers = argumentValues.map { strdup($0) }
        let environmentPointers = environment.keys.sorted().map { strdup("\($0)=\(environment[$0]!)") }
        defer {
            argumentPointers.forEach { free($0) }
            environmentPointers.forEach { free($0) }
        }
        var arguments = argumentPointers + [nil]
        var variables = environmentPointers + [nil]
        var child: pid_t = 0
        let result = posix_spawn(&child, "/bin/zsh", &actions, &attributes, &arguments, &variables)
        guard result == 0 else {
            close(readDescriptor)
            throw OrbitloomError.message("无法启动命令：\(String(cString: strerror(result)))")
        }
        pid = child
        let processID = child
        let outputFinished = DispatchGroup()
        outputFinished.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { close(readDescriptor); outputFinished.leave() }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = read(readDescriptor, &bytes, bytes.count)
                if count > 0 {
                    let data = Data(bytes.prefix(count))
                    // 同步提交有界数据，对高输出命令施加背压，避免主线程队列无限堆积。
                    DispatchQueue.main.sync { onOutput(data) }
                } else if count < 0 && errno == EINTR { continue }
                else { break }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            var waited: pid_t
            repeat { waited = waitpid(processID, &status, 0) } while waited < 0 && errno == EINTR
            // 入口退出后清理同组后代，防止后台子进程继续占用日志管道和端口。
            kill(-processID, SIGKILL)
            let signal = status & 0x7f
            let exit = ProcessExit(code: waited < 0 ? 1 : (status >> 8) & 0xff, signal: signal)
            outputFinished.notify(queue: .main) { MainActor.assumeIsolated { onExit(exit) } }
        }
    }

    /// 只向本实例创建的进程组发送信号，不按进程名或端口查杀。
    func send(_ signal: Int32) {
        kill(-pid, signal)
    }
}
