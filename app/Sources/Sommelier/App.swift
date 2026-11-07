// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppModel.shared.pendingOpen = urls.filter { $0.isFileURL }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Debug: SOMMELIER_SNAPSHOT_DIR=/path saves a screenshot of every section, then quits the app.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let dir = ProcessInfo.processInfo.environment["SOMMELIER_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            let model = AppModel.shared
            try? await Task.sleep(for: .seconds(4))
            var shots: [(String, SidebarItem)] = [("versions", .versions), ("recipes", .recipes)]
            if let e = model.allPrograms.first {
                shots.append(("program", .program(bottle: e.bottle.name, path: e.program.path)))
            }
            // Demo task (screenshots only) so the progress bar can be checked
            let demo = Job(title: L("Creazione bottiglia «%@» (%@)", "Demo", "Steam"), kind: .bottle, bottle: model.bottles.first?.name)
            demo.stage = 3; demo.stageCount = 8; demo.stageStarted = Date().addingTimeInterval(-74)
            demo.step = L("Winetricks: %@", "corefonts")
            model.jobs.insert(demo, at: 0)
            if let b = model.bottles.first { shots.append(("bottle", .bottle(b.name))) }
            shots.append(("activity", .activity))
            for (name, item) in shots {
                model.selection = item
                try? await Task.sleep(for: .seconds(1.5))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView else { continue }
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
                }
            }
            model.selection = .versions
            model.showNewBottle = true
            try? await Task.sleep(for: .seconds(3.5))
            if let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }), let view = sheet.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("newbottle.png"))
            }
            exit(0)   // terminate() doesn't quit while a sheet is open
        }
    }
}

@main
struct SommelierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel.shared
    @AppStorage(Lang.settingKey) private var language = "system"

    var body: some Scene {
        WindowGroup("Sommelier") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .id(language)
                .onChange(of: language) {
                    Task { await model.loadPresets(); await model.loadCatalog() }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Nuova bottiglia…")) { model.showNewBottle = true }
                    .keyboardShortcut("n")
                Button(L("Esegui un programma Windows…")) {
                    if let urls = FilePicker.pickWindowsFiles() { model.pendingOpen = urls }
                }
                .keyboardShortcut("o")
            }
            CommandMenu(L("Wine")) {
                Button(L("Controlla aggiornamenti")) { Task { await model.refreshStatus(force: true) } }
                    .keyboardShortcut("r")
                Button(L("Aggiorna tutte le versioni")) { model.updateAll() }
                    .disabled(model.updatesCount == 0)
                Divider()
                Button(L("Versioni di Wine")) { model.selection = .versions }.keyboardShortcut("1")
                Button(L("Attività")) { model.selection = .activity }.keyboardShortcut("2")
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}

enum FilePicker {
    @MainActor
    static func pickWindowsFiles(in dir: URL? = nil) -> [URL]? {
        let p = NSOpenPanel()
        p.title = L("Scegli un programma Windows")
        p.prompt = L("Esegui")
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.allowedContentTypes = []
        p.allowsOtherFileTypes = true
        if let dir { p.directoryURL = dir }
        return p.runModal() == .OK ? p.urls : nil
    }
}

struct SettingsView: View {
    @AppStorage("verboseLogs") private var verboseLogs = false
    @AppStorage(Lang.settingKey) private var language = "system"
    @AppStorage("checkOnLaunch") private var checkOnLaunch = true
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker(L("Lingua"), selection: $language) {
                Text(L("Automatica (lingua del sistema)")).tag("system")
                Text("English").tag("en")
                Text("Italiano").tag("it")
            }
            Toggle(L("Controlla gli aggiornamenti di Wine all'avvio"), isOn: $checkOnLaunch)
            Toggle(L("Log dettagliati di Wine (utile per capire perché un programma non parte)"), isOn: $verboseLogs)
            LabeledContent(L("Dati e bottiglie")) {
                Button(L("Mostra nel Finder")) { NSWorkspace.shared.open(model.supportDir) }
            }
            LabeledContent(L("Strumento a riga di comando")) {
                Text(Runner.scriptPath).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .id(language)
        .padding()
    }
}
