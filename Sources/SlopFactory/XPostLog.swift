import Foundation

// Appends timestamped X posting steps to post.log in the run folder, so a
// failed draft can be diagnosed without seeing the window.
struct XPostLog {
    let url: URL

    func write(_ line: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(entry.utf8))
    }
}
