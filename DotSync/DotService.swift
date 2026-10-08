import Foundation
import Observation

/// Runs ~/.dotfiles/dot and keeps the last known status.
@MainActor
@Observable
final class DotService {
    private(set) var status: DotStatus?
    private(set) var error: String?
    private(set) var isSyncing = false
    private(set) var lastOutput = ""

    static let repo = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".dotfiles")
    private var dotScript: URL { Self.repo.appending(path: "dot") }
    private var timer: Timer?

    var health: Health {
        if isSyncing { return .syncing }
        if error != nil { return .broken }
        return status?.health ?? .broken
    }

    init() {
        Task { await refresh() }
        // launchd syncs every 30 min on its own; polling keeps the icon honest in between
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard FileManager.default.fileExists(atPath: dotScript.path) else {
            error = "~/.dotfiles/dot introuvable : clone le dépôt dotfiles"
            status = nil
            return
        }
        let result = await run(["status", "--json"])
        guard result.code == 0, let data = result.output.data(using: .utf8) else {
            error = result.output.isEmpty ? "dot status a échoué (code \(result.code))" : result.output
            return
        }
        do {
            status = try JSONDecoder().decode(DotStatus.self, from: data)
            error = nil
        } catch {
            self.error = "Réponse illisible de dot status : \(error.localizedDescription)"
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        let result = await run(["sync"])
        lastOutput = result.output
            .split(separator: "\n")
            .filter { !$0.contains(" INF ") }   // gitleaks progress lines
            .joined(separator: "\n")
        isSyncing = false
        await refresh()
    }

    func setAutosync(_ on: Bool) async {
        _ = await run(["autosync", on ? "on" : "off"])
        await refresh()
    }

    // MARK: - Process

    private func run(_ args: [String]) async -> (code: Int32, output: String) {
        let script = dotScript
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path] + args
            var env = ProcessInfo.processInfo.environment
            // GUI apps get a minimal PATH: git, gitleaks and brew live in Homebrew
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["DOT_NO_NOTIFY"] = "1"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (-1, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, text)
        }.value
    }
}
