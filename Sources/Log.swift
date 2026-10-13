import Foundation

/// 极简文件日志：默认写 /tmp/pptclicker.log，方便排查"到底有没有拦到事件"。
final class Log {
    static let shared = Log()

    private let queue = DispatchQueue(label: "ai.dsh.pptclicker.log")
    private var handle: FileHandle?
    private var enabled = false
    private var path = "/tmp/pptclicker.log"

    private init() {}

    func configure(enabled: Bool, path: String) {
        queue.sync {
            self.enabled = enabled
            self.path = path
            self.handle?.closeFile()
            self.handle = nil
            guard enabled else { return }

            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                self.handle = h
            }
        }
    }

    func write(_ message: String) {
        NSLog("PPTClicker: %@", message)
        let line = "[\(Self.stamp())] \(message)\n"
        queue.async {
            guard self.enabled, let handle = self.handle else { return }
            if let data = line.data(using: .utf8) { handle.write(data) }
        }
    }

    var currentPath: String { queue.sync { path } }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
