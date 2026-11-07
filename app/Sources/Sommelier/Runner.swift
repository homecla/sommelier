// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import Foundation

/// Buffers bytes coming from a pipe and returns complete lines.
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data[data.startIndex..<nl]
            lines.append(Self.decode(lineData))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return [] }
        let s = Self.decode(data); data.removeAll()
        return [s]
    }

    private static func decode(_ d: Data) -> String {
        let s = String(decoding: d, as: UTF8.self)
        // strip \r and ANSI color sequences
        return s.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }
}

/// Runs the `sommelier` script bundled with the app.
enum Runner {
    static var scriptPath: String {
        if let p = Bundle.main.path(forResource: "sommelier", ofType: nil) { return p }
        let local = NSHomeDirectory() + "/.local/bin/sommelier"
        if FileManager.default.isExecutableFile(atPath: local) { return local }
        return "/usr/local/bin/sommelier"
    }

    static func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptPath] + args
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["SOMMELIER_LANG"] = Lang.current
        p.environment = env
        return p
    }

    /// Starts a process bound to a Job, streaming its output.
    @MainActor
    static func start(_ args: [String], job: Job,
                      onLine: @escaping @MainActor (String) -> Void = { _ in },
                      onExit: @escaping @MainActor (Int32) -> Void = { _ in }) {
        let p = makeProcess(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let buffer = LineBuffer()

        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                let rest = buffer.flush()
                if !rest.isEmpty { DispatchQueue.main.async { rest.forEach { onLine($0) } } }
                return
            }
            let lines = buffer.append(d)
            if !lines.isEmpty { DispatchQueue.main.async { lines.forEach { onLine($0) } } }
        }
        p.terminationHandler = { proc in
            let code = proc.terminationStatus
            // short delay to receive the last output before closing the job
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                job.running = false
                job.exitCode = code
                job.process = nil
                onExit(code)
            }
        }
        do {
            try p.run()
            job.process = p
        } catch {
            job.running = false
            job.error = L("Impossibile avviare sommelier: %@", "\(error.localizedDescription)")
            onExit(-1)
        }
    }

    /// Runs and returns the whole output (stdout) when the process ends.
    static func capture(_ args: [String]) async -> (code: Int32, out: String, err: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = makeProcess(args)
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch {
                    cont.resume(returning: (-1, "", error.localizedDescription)); return
                }
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus,
                                        String(decoding: o, as: UTF8.self),
                                        String(decoding: e, as: UTF8.self)))
            }
        }
    }
}
