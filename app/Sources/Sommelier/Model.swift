// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI
import AppKit
import Observation

// MARK: - Types

enum Branch: String, CaseIterable, Identifiable, Codable {
    case stable, devel, staging
    var id: String { rawValue }
    var title: String {
        switch self { case .stable: L("Stable"); case .devel: L("Devel"); case .staging: L("Staging") }
    }
    var subtitle: String {
        switch self {
        case .stable: L("La più collaudata. Consigliata per l'uso quotidiano.")
        case .devel: L("Rilasci ogni due settimane: più compatibilità con le app recenti, meno test.")
        case .staging: L("Devel con patch sperimentali: a volte fa girare ciò che le altre non fanno.")
        }
    }
    var color: Color {
        switch self { case .stable: .green; case .devel: .blue; case .staging: .orange }
    }
}

struct BranchStatus: Codable, Identifiable, Hashable {
    let branch: String
    let installed: String
    let path: String
    let latest: String
    let date: String
    let running: Bool
    var id: String { branch }
    var isInstalled: Bool { !installed.isEmpty }
    var hasUpdate: Bool { isInstalled && !latest.isEmpty && latest != installed }
}

struct WineStatus: Codable {
    let tool: String
    let `default`: String
    let installDir: String
    let rosetta: Bool
    let branches: [BranchStatus]
}

struct Program: Codable, Hashable, Identifiable {
    var name: String
    var path: String          // Unix path of the executable or .lnk shortcut
    var args: [String]? = nil // launch arguments (e.g. set by a recipe)
    var id: String { path }
}

struct BottleMeta: Codable {
    var name: String
    var branch: String?
    var created: String?
    var programs: [Program]?
    var preset: String?
}

/// Recipe (a .preset file read via `sommelier preset list --json`).
struct Preset: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let notes: String
    let winver: String
    let winetricks: String
    let installs: Bool
    let order: Int
    var user: Bool? = nil      // personal recipe (can be deleted)
    var source: String? = nil  // URL it was downloaded from
    var path: String? = nil

    /// Summary of what the recipe will do.
    var steps: [String] {
        var s: [String] = []
        if !winver.isEmpty { s.append(L("Windows %@", "\(winver.replacingOccurrences(of: "win", with: ""))")) }
        if !winetricks.isEmpty { s.append(winetricks.split(separator: " ").joined(separator: ", ")) }
        if installs { s.append(L("installa %@", "\(title)")) }
        return s
    }
}

struct Bottle: Identifiable, Hashable {
    let url: URL
    var meta: BottleMeta
    var id: String { url.lastPathComponent }
    var name: String { url.lastPathComponent }
    var branch: String { meta.branch ?? "default" }
    var programs: [Program] { meta.programs ?? [] }
    var driveC: URL { url.appendingPathComponent("drive_c") }
    static func == (a: Bottle, b: Bottle) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }
}

struct CatalogRecipe: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let notes: String
    let installs: Bool
    let order: Int
    let winver: String
    let winetricks: String
    let state: String   // available | installed | update | builtin
}

struct CatalogResponse: Codable {
    let url: String
    let recipes: [CatalogRecipe]
}

/// A program together with the bottle it lives in.
struct ProgramEntry: Identifiable {
    let bottle: Bottle
    let program: Program
    var id: String { bottle.name + "\u{1}" + program.path }
}

enum SidebarItem: Hashable {
    case versions
    case recipes
    case program(bottle: String, path: String)
    case bottle(String)
    case activity
}

@MainActor @Observable
final class Job: Identifiable {
    enum Kind { case wine, bottle, program, tool }
    let id = UUID()
    let title: String
    let kind: Kind
    let bottle: String?
    let branch: String?
    let target: String?        // file or command being run (for programs)
    let started = Date()
    var lines: [String] = []
    var step = ""
    var progress: Double?          // progress inside the current step (downloads)
    var stage = 0                  // current numbered step (from "@stage i n")
    var stageCount = 0
    var stageStarted: Date?
    var error: String?
    var running = true
    var exitCode: Int32?
    var process: Process?

    init(title: String, kind: Kind, bottle: String? = nil, branch: String? = nil, target: String? = nil) {
        self.title = title; self.kind = kind; self.bottle = bottle; self.branch = branch; self.target = target
    }

    func append(_ line: String) {
        lines.append(line)
        if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
    }

    func stop() { process?.terminate() }

    var succeeded: Bool { !running && exitCode == 0 && error == nil }

    /// Overall progress 0…1 when the script reports numbered steps, otherwise the step progress (or nil).
    var overallProgress: Double? {
        guard stageCount > 0, stage > 0 else { return progress }
        let done = Double(stage - 1) + min(max(progress ?? 0, 0), 1)
        return min(done / Double(stageCount), 1)
    }
}

// MARK: - App model

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var status: WineStatus?
    var statusError: String?
    var checking = false
    var bottles: [Bottle] = []
    var presets: [Preset] = []
    var catalog: CatalogResponse?
    var catalogError: String?
    var catalogURL = ""
    var catalogLoading = false
    var catalogBusy: Set<String> = []
    var jobs: [Job] = []
    var selection: SidebarItem? = .versions
    var pendingOpen: [URL] = []          // files opened from Finder ("Open With")
    var showNewBottle = false
    var alert: String?

    let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sommelier")
    var bottlesDir: URL { supportDir.appendingPathComponent("Bottles") }

    var verboseLogs: Bool { UserDefaults.standard.bool(forKey: "verboseLogs") }

    // MARK: Version status

    func status(for b: Branch) -> BranchStatus? { status?.branches.first { $0.branch == b.rawValue } }
    var defaultBranch: Branch { Branch(rawValue: status?.default ?? "stable") ?? .stable }
    var installedBranches: [Branch] { Branch.allCases.filter { status(for: $0)?.isInstalled == true } }
    var updatesCount: Int { status?.branches.filter(\.hasUpdate).count ?? 0 }
    var runningJobs: Int { jobs.filter(\.running).count }

    func job(forBranch b: Branch) -> Job? {
        jobs.first { $0.kind == .wine && $0.branch == b.rawValue && $0.running }
    }
    func jobs(forBottle name: String) -> [Job] {
        jobs.filter { $0.bottle == name && $0.running }
    }

    func refreshStatus(force: Bool = false, remote: Bool = true) async {
        checking = true
        defer { checking = false }
        var args = ["status", "--json"]
        if remote { args.append(force ? "--refresh" : "--remote") }
        let r = await Runner.capture(args)
        if let data = r.out.data(using: .utf8), let s = try? JSONDecoder().decode(WineStatus.self, from: data) {
            status = s
            statusError = nil
        } else {
            // offline: at least show the local status
            let local = await Runner.capture(["status", "--json"])
            if let data = local.out.data(using: .utf8), let s = try? JSONDecoder().decode(WineStatus.self, from: data) {
                status = s
            }
            let msg = (r.out + r.err).split(separator: "\n").last.map(String.init) ?? L("errore sconosciuto")
            statusError = msg.replacingOccurrences(of: "@error ", with: "")
        }
    }

    @discardableResult
    private func startJob(_ title: String, kind: Job.Kind, bottle: String? = nil, branch: String? = nil, target: String? = nil,
                          args: [String], onExit: @escaping @MainActor (Job) -> Void = { _ in }) -> Job {
        let job = Job(title: title, kind: kind, bottle: bottle, branch: branch, target: target)
        jobs.insert(job, at: 0)
        if jobs.count > 60, let i = jobs.lastIndex(where: { !$0.running }) { jobs.remove(at: i) }
        Runner.start(args, job: job, onLine: { line in
            Self.handleMachineLine(line, job: job)
        }, onExit: { code in
            if code != 0, job.error == nil, job.kind != .program {
                job.error = job.lines.last ?? L("terminato con codice %@", "\(code)")
            }
            onExit(job)
        })
        return job
    }

    private static func handleMachineLine(_ line: String, job: Job) {
        if line.hasPrefix("@progress ") {
            if let v = Double(line.dropFirst(10)) { job.progress = v / 100 }
        } else if line.hasPrefix("@stage ") {
            let parts = line.dropFirst(7).split(separator: " ").compactMap { Int($0) }
            if parts.count == 2 {
                job.stage = parts[0]; job.stageCount = parts[1]
                job.stageStarted = Date(); job.progress = nil
            }
        } else if line.hasPrefix("@bottle-created ") {
            // the bottle folder now exists: show it in the sidebar right away
            let name = String(line.dropFirst(16))
            AppModel.shared.loadBottles()
            if AppModel.shared.bottle(named: name) != nil { AppModel.shared.selection = .bottle(name) }
        } else if line.hasPrefix("@step ") {
            job.step = String(line.dropFirst(6)); job.append("▸ " + job.step)
        } else if line.hasPrefix("@error ") {
            job.error = String(line.dropFirst(7)); job.append("✖ " + job.error!)
        } else if line.hasPrefix("@warn ") {
            job.append("⚠︎ " + line.dropFirst(6))
        } else if line.hasPrefix("@done") {
            job.progress = 1
        } else {
            job.append(line)
        }
    }

    func install(_ b: Branch, force: Bool = false) {
        let st = status(for: b)
        let title = st?.isInstalled == true
            ? (st?.hasUpdate == true ? L("Aggiornamento Wine %@", "\(b.title)") : L("Reinstallazione Wine %@", "\(b.title)"))
            : L("Installazione Wine %@", "\(b.title)")
        startJob(title, kind: .wine, branch: b.rawValue,
                 args: ["--machine", "install", b.rawValue] + (force ? ["--force"] : [])) { [weak self] _ in
            Task { await self?.refreshStatus() }
        }
    }

    func updateAll() {
        for b in Branch.allCases where status(for: b)?.hasUpdate == true && job(forBranch: b) == nil { install(b) }
    }

    func uninstall(_ b: Branch) {
        startJob(L("Disinstallazione Wine %@", "\(b.title)"), kind: .wine, branch: b.rawValue,
                 args: ["--machine", "uninstall", b.rawValue, "-y"]) { [weak self] job in
            if let e = job.error { self?.alert = e }
            Task { await self?.refreshStatus() }
        }
    }

    func setDefault(_ b: Branch) {
        Task {
            _ = await Runner.capture(["default", b.rawValue])
            await refreshStatus()
        }
    }

    func installRosetta() {
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        Task.detached {
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            let message = err.map { "\($0[NSAppleScript.errorMessage] ?? "errore sconosciuto")" }
            await MainActor.run {
                if let message { AppModel.shared.alert = L("Installazione di Rosetta non riuscita: %@", "\(message)") }
            }
            await AppModel.shared.refreshStatus()
        }
    }

    // MARK: Bottles

    func loadBottles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: bottlesDir, withIntermediateDirectories: true)
        let dirs = (try? fm.contentsOfDirectory(at: bottlesDir, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        bottles = dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url in
                let metaURL = url.appendingPathComponent("bottle.json")
                let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(BottleMeta.self, from: $0) }
                    ?? BottleMeta(name: url.lastPathComponent, branch: "default", created: nil, programs: [])
                return Bottle(url: url, meta: meta)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if case .bottle(let n) = selection, !bottles.contains(where: { $0.name == n }) { selection = .versions }
    }

    func bottle(named n: String) -> Bottle? { bottles.first { $0.name == n } }

    /// Every saved program of every bottle, sorted by name (for the sidebar).
    var allPrograms: [ProgramEntry] {
        bottles.flatMap { b in b.programs.map { ProgramEntry(bottle: b, program: $0) } }
            .sorted { $0.program.name.localizedStandardCompare($1.program.name) == .orderedAscending }
    }

    func runningJobs(for p: Program, in b: Bottle) -> [Job] {
        jobs.filter { $0.running && $0.kind == .program && $0.bottle == b.name && $0.target == p.path }
    }

    /// Changes whenever bottles or programs change: used to rebuild the sidebar list.
    var sidebarIdentity: String {
        bottles.map { b in ([b.name] + b.programs.map { $0.name + "|" + $0.path }).joined(separator: "\u{1}") }
            .joined(separator: "\u{2}")
    }

    private func save(_ b: Bottle) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        if let data = try? enc.encode(b.meta) {
            try? data.write(to: b.url.appendingPathComponent("bottle.json"), options: .atomic)
        }
        if let i = bottles.firstIndex(of: b) { bottles[i] = b }
    }

    func validBottleName(_ n: String) -> String? {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return L("Inserisci un nome") }
        if t.hasPrefix(".") || t.contains("/") || t.contains("\"") || t.contains("\\") { return L("Il nome non può contenere / \\ \" né iniziare con un punto") }
        if t.count > 64 { return L("Nome troppo lungo") }
        if bottles.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) { return L("Esiste già una bottiglia con questo nome") }
        return nil
    }

    func loadPresets() async {
        let r = await Runner.capture(["preset", "list", "--json"])
        if let data = r.out.data(using: .utf8), let p = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = p.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
        }
    }

    func preset(_ id: String?) -> Preset? { presets.first { $0.id == id } }

    // MARK: Online catalog

    var catalogUpdates: Int { catalog?.recipes.filter { $0.state == "update" }.count ?? 0 }

    func loadCatalog(refresh: Bool = false) async {
        let u = await Runner.capture(["catalog", "url"])
        let url = u.out.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogURL = url.hasPrefix("(") ? "" : url
        guard !catalogURL.isEmpty else { catalog = nil; catalogError = nil; return }
        catalogLoading = true
        defer { catalogLoading = false }
        let r = await Runner.capture(["--machine", "catalog", "list", "--json"] + (refresh ? ["-r"] : []))
        let lines = r.out.split(separator: "\n").map(String.init)
        if let json = lines.first(where: { $0.hasPrefix("{") })?.data(using: .utf8),
           let c = try? JSONDecoder().decode(CatalogResponse.self, from: json) {
            catalog = CatalogResponse(url: c.url, recipes: c.recipes.sorted { ($0.order, $0.title) < ($1.order, $1.title) })
            catalogError = lines.first(where: { $0.hasPrefix("@warn ") }).map { String($0.dropFirst(6)) }
        } else {
            catalog = nil
            catalogError = lines.first(where: { $0.hasPrefix("@error ") }).map { String($0.dropFirst(7)) } ?? L("Catalogo non disponibile")
        }
    }

    func setCatalogURL(_ url: String) async -> String? {
        let r = await Runner.capture(["--machine", "catalog", "url", url.trimmingCharacters(in: .whitespaces)])
        if let e = r.out.split(separator: "\n").first(where: { $0.hasPrefix("@error ") }) { return String(e.dropFirst(7)) }
        await loadCatalog(refresh: true)
        return nil
    }

    /// Installs (or updates) a catalog recipe, verifying its SHA-256 fingerprint.
    func installFromCatalog(_ ids: [String]) async {
        ids.forEach { catalogBusy.insert($0) }
        let r = await Runner.capture(["--machine", "catalog", "install"] + ids)
        ids.forEach { catalogBusy.remove($0) }
        if let e = r.out.split(separator: "\n").first(where: { $0.hasPrefix("@error ") }) { alert = String(e.dropFirst(7)) }
        await loadPresets()
        await loadCatalog()
    }

    func removeCatalogRecipe(_ id: String) async {
        _ = await Runner.capture(["--machine", "preset", "remove", id, "-y"])
        await loadPresets()
        await loadCatalog()
    }

    /// Runs `sommelier preset …`; returns (success, message to show).
    private func presetCommand(_ args: [String]) async -> (ok: Bool, message: String) {
        let r = await Runner.capture(["--machine", "preset"] + args)
        await loadPresets()
        let lines = r.out.split(separator: "\n").map(String.init)
        if let e = lines.first(where: { $0.hasPrefix("@error ") }) { return (false, String(e.dropFirst(7))) }
        let msgs = lines.filter { $0.hasPrefix("@step ") || $0.hasPrefix("@warn ") }.map { String($0.dropFirst(6)) }
        return (r.code == 0, msgs.joined(separator: "\n"))
    }

    func addPreset(from source: String) async -> String { await presetCommand(["add", source, "-y", "--force"]).message }
    func removePreset(_ p: Preset) async -> String { await presetCommand(["remove", p.id, "-y"]).message }
    func updatePresets() async -> String { await presetCommand(["update"]).message }
    func newPreset(_ id: String) async -> String {
        let r = await presetCommand(["new", id])
        if r.ok { NSWorkspace.shared.open(supportDir.appendingPathComponent("Presets/\(id).preset")) }
        return r.message
    }

    func createBottle(name: String, branch: String, preset: String? = nil) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let title = preset.flatMap { self.preset($0)?.title }.map { L("Creazione bottiglia «%@» (%@)", "\(n)", "\($0)") } ?? L("Creazione bottiglia «%@»", "\(n)")
        startJob(title, kind: .bottle, bottle: n,
                 args: ["--machine", "bottle", "create", n, "-b", branch] + (preset.map { ["-P", $0] } ?? [])) { [weak self] job in
            guard let self else { return }
            self.loadBottles()
            if job.succeeded { self.selection = .bottle(n) } else { self.alert = job.error ?? L("Creazione non riuscita") }
        }
    }

    func applyPreset(_ p: Preset, to b: Bottle) {
        startJob(L("Configurazione «%@» su «%@»", "\(p.title)", "\(b.name)"), kind: .bottle, bottle: b.name,
                 args: ["--machine", "bottle", "apply", b.name, p.id]) { [weak self] job in
            self?.loadBottles()
            if !job.succeeded { self?.alert = job.error ?? L("Configurazione non applicata completamente: controlla Attività.") }
        }
    }

    func setBranch(_ branch: String, for b: Bottle) {
        var nb = b; nb.meta.branch = branch; save(nb)
    }

    func deleteBottle(_ b: Bottle) {
        Task {
            _ = await Runner.capture(["kill", "-B", b.name])
            do {
                try FileManager.default.trashItem(at: b.url, resultingItemURL: nil)
            } catch {
                alert = L("Impossibile spostare la bottiglia nel Cestino: %@", "\(error.localizedDescription)")
            }
            loadBottles()
        }
    }

    func addPrograms(_ ps: [Program], to b: Bottle) {
        var nb = b
        var list = nb.programs
        for p in ps where !list.contains(where: { $0.path == p.path }) { list.append(p) }
        nb.meta.programs = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save(nb)
    }

    func removeProgram(_ p: Program, from b: Bottle) {
        var nb = b; nb.meta.programs = nb.programs.filter { $0.path != p.path }; save(nb)
    }

    func renameProgram(_ p: Program, to name: String, in b: Bottle) {
        var nb = b
        nb.meta.programs = nb.programs.map { $0.path == p.path ? Program(name: name, path: p.path, args: p.args) : $0 }
        save(nb)
    }

    // MARK: Running programs

    func run(_ target: String, args: [String] = [], in b: Bottle, title: String? = nil, kind: Job.Kind = .program) {
        var a = ["--machine", "run", "-B", b.name]
        if verboseLogs { a.append("--debug") }
        a += ["--", target] + args
        let t = title ?? URL(fileURLWithPath: target).lastPathComponent
        startJob(t, kind: kind, bottle: b.name, target: target, args: a) { [weak self] job in
            if let e = job.error, kind != .program { self?.alert = e }
            // after an installer, pick up any new programs
            if kind == .program, ["msi", "exe"].contains(URL(fileURLWithPath: target).pathExtension.lowercased()) {
                self?.loadBottles()
            }
        }
    }

    func winetricks(_ verbs: [String], in b: Bottle) {
        startJob(L("Winetricks: %@", "\(verbs.joined(separator: " "))"), kind: .tool, bottle: b.name,
                 args: ["--machine", "winetricks", "-B", b.name, "--", "-q"] + verbs) { [weak self] job in
            if !job.succeeded { self?.alert = L("Winetricks non è riuscito a installare tutto: controlla il registro in Attività.") }
        }
    }

    func killBottle(_ b: Bottle) {
        Task {
            _ = await Runner.capture(["kill", "-B", b.name])
            for j in jobs(forBottle: b.name) { j.stop() }
        }
    }

    func openTerminal(in b: Bottle) {
        let script = Runner.scriptPath
        let cmd = "export SOMMELIER_BOTTLE=\(shq(b.name)); export WINEPREFIX=\(shq(b.url.path)); "
            + "alias wine=\(shq("\"\(script)\" run -B \"$SOMMELIER_BOTTLE\"")); "
            + "alias winetricks=\(shq("\"\(script)\" winetricks -B \"$SOMMELIER_BOTTLE\"")); "
            + "alias sommelier=\(shq("\"\(script)\"")); "
            + "clear; echo 'Bottiglia: \(b.name.replacingOccurrences(of: "'", with: ""))  —  usa: wine programma.exe, winetricks pacchetto'"
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { alert = L("Impossibile aprire il Terminale: %@", "\(err[NSAppleScript.errorMessage] ?? "")") }
    }

    private func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Finds installed programs: Start menu/Desktop shortcuts and .exe files in Program Files.
    func scanPrograms(in b: Bottle) -> [Program] {
        let fm = FileManager.default
        var found: [Program] = []
        var seenNames = Set<String>()
        let skip = ["unins", "uninst", "setup", "install", "update", "crash", "helper", "report", "vcredist", "dxsetup", "repair"]
        func skipName(_ n: String) -> Bool { let l = n.lowercased(); return skip.contains { l.contains($0) } }

        let users = (try? fm.contentsOfDirectory(atPath: b.driveC.appendingPathComponent("users").path)) ?? []
        var lnkRoots = [b.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs")]
        for u in users {
            let base = b.driveC.appendingPathComponent("users/\(u)")
            lnkRoots.append(base.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu/Programs"))
            lnkRoots.append(base.appendingPathComponent("Desktop"))
        }
        for root in lnkRoots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension.lowercased() == "lnk" {
                let n = u.deletingPathExtension().lastPathComponent
                if skipName(n) || seenNames.contains(n.lowercased()) { continue }
                seenNames.insert(n.lowercased())
                found.append(Program(name: n, path: u.path))
            }
        }
        let ignoredDirs = ["common files", "internet explorer", "windows media player", "windows nt", "windowspowershell", "microsoft.net"]
        for pf in ["Program Files", "Program Files (x86)"] {
            let root = b.driveC.appendingPathComponent(pf)
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in e {
                if e.level == 1, ignoredDirs.contains(u.lastPathComponent.lowercased()) { e.skipDescendants(); continue }
                if e.level > 4 { e.skipDescendants(); continue }
                guard u.pathExtension.lowercased() == "exe" else { continue }
                let n = u.deletingPathExtension().lastPathComponent
                if skipName(n) || seenNames.contains(n.lowercased()) { continue }
                seenNames.insert(n.lowercased())
                found.append(Program(name: n, path: u.path))
            }
        }
        let existing = Set(b.programs.map(\.path))
        return found.filter { !existing.contains($0.path) }
    }
}
