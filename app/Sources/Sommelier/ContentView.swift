// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("checkOnLaunch") private var checkOnLaunch = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch model.selection {
            case .bottle(let name):
                if let b = model.bottle(named: name) { BottleView(bottle: b).id(b.id) }
                else { ContentUnavailableView(L("Bottiglia non trovata"), systemImage: "wineglass") }
            case .activity:
                ActivityView()
            case .program(let bottleName, let path):
                if let b = model.bottle(named: bottleName), let p = b.programs.first(where: { $0.path == path }) {
                    ProgramDetailView(bottle: b, program: p).id(b.id + path)
                } else {
                    ContentUnavailableView(L("Programma non trovato"), systemImage: "app.dashed")
                }
            case .recipes:
                RecipesView()
            default:
                VersionsView()
            }
        }
        .sheet(isPresented: $model.showNewBottle) { NewBottleSheet() }
        .sheet(isPresented: Binding(get: { !model.pendingOpen.isEmpty },
                                    set: { if !$0 { model.pendingOpen = [] } })) {
            OpenWithSheet(urls: model.pendingOpen)
        }
        .alert("Sommelier", isPresented: Binding(get: { model.alert != nil },
                                                       set: { if !$0 { model.alert = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(model.alert ?? "") }
        .task {
            await model.loadPresets()   // the first sommelier call also migrates data from the old name
            model.loadBottles()
            await model.refreshStatus(remote: checkOnLaunch)
            if checkOnLaunch { await model.loadCatalog() }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete: Bottle?
    @AppStorage("sidebar.programs.expanded") private var programsExpanded = true
    @AppStorage("sidebar.bottles.expanded") private var bottlesExpanded = true

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section(L("Wine")) {
                Label(L("Versioni"), systemImage: "shippingbox")
                    .badge(model.updatesCount)
                    .tag(SidebarItem.versions)
                Label(L("Ricette"), systemImage: "sparkles.rectangle.stack")
                    .badge(model.catalogUpdates)
                    .tag(SidebarItem.recipes)
            }
            Section(L("Programmi"), isExpanded: $programsExpanded) {
                ForEach(model.allPrograms) { entry in
                    ProgramSidebarRow(bottle: entry.bottle, program: entry.program)
                        .tag(SidebarItem.program(bottle: entry.bottle.name, path: entry.program.path))
                }
                if model.allPrograms.isEmpty {
                    Text(L("Nessun programma")).foregroundStyle(.secondary).font(.callout)
                }
            }
            Section(L("Bottiglie"), isExpanded: $bottlesExpanded) {
                ForEach(model.bottles) { b in
                    Label {
                        HStack {
                            Text(b.name)
                            Spacer()
                            if !model.jobs(forBottle: b.name).isEmpty {
                                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                                    .help(L("Programmi in esecuzione"))
                            }
                        }
                    } icon: { Image(systemName: "wineglass") }
                    .tag(SidebarItem.bottle(b.name))
                    .contextMenu {
                        Button(L("Mostra nel Finder")) { NSWorkspace.shared.activateFileViewerSelecting([b.driveC]) }
                        Button(L("Termina processi")) { model.killBottle(b) }
                        Divider()
                        Button(L("Sposta nel Cestino…"), role: .destructive) { confirmDelete = b }
                    }
                }
                if model.bottles.isEmpty {
                    Text(L("Nessuna bottiglia")).foregroundStyle(.secondary).font(.callout)
                }
            }
            Section {
                Label(L("Attività"), systemImage: "list.bullet.rectangle.portrait")
                    .badge(model.runningJobs)
                    .tag(SidebarItem.activity)
            }
        }
        .id(model.sidebarIdentity)     // rebuild when bottles or programs change (stale sidebar fix)
        .safeAreaInset(edge: .bottom) {
            Button { model.showNewBottle = true } label: {
                Label(L("Nuova bottiglia"), systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .confirmDelete($confirmDelete)
    }
}

extension View {
    func confirmDelete(_ item: Binding<Bottle?>) -> some View {
        confirmationDialog(L("Spostare la bottiglia «%@» nel Cestino?", "\(item.wrappedValue?.name ?? "")"),
                           isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                           titleVisibility: .visible) {
            Button(L("Sposta nel Cestino"), role: .destructive) {
                if let b = item.wrappedValue { AppModel.shared.deleteBottle(b) }
            }
        } message: {
            Text(L("Tutti i programmi installati al suo interno verranno chiusi e spostati nel Cestino insieme alla bottiglia."))
        }
    }
}

// MARK: - Sheets

struct NewBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var branch = "default"
    @State private var presetID: String? = nil

    var body: some View {
        let err = model.validBottleName(name)
        VStack(alignment: .leading, spacing: 16) {
            Label(L("Nuova bottiglia"), systemImage: "wineglass").font(.title2.bold())
            Text(L("Una bottiglia è un «PC Windows» separato con il suo disco C: e le sue impostazioni. Usane una diversa per ogni programma o gioco problematico."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L("Configurazione")).font(.headline)
                Spacer()
                PresetManageBar()
            }
            PresetGallery(selection: $presetID, allowEmpty: true)
                .onChange(of: presetID) { old, new in
                    let oldTitle = model.preset(old)?.title ?? ""
                    if name.isEmpty || name == oldTitle { name = model.preset(new)?.title ?? "" }
                }
            if let p = model.preset(presetID), !p.notes.isEmpty {
                Label(p.notes, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Form {
                TextField(L("Nome"), text: $name, prompt: Text(L("es. Giochi, Office, Lavoro")))
                BranchPicker(selection: $branch)
            }
            .formStyle(.grouped)
            if !name.isEmpty, let err { Text(err).font(.caption).foregroundStyle(.red) }
            if model.installedBranches.isEmpty {
                Label(L("Nessuna versione di Wine installata: installane una dalla sezione Versioni."), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.preset(presetID)?.installs == true ? L("Crea e installa") : L("Crea")) {
                    model.createBottle(name: name, branch: branch, preset: presetID); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(err != nil || model.installedBranches.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// Grid for picking a recipe.
struct PresetGallery: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    var allowEmpty = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            if allowEmpty {
                tile(id: nil, icon: "square.dashed", title: L("Vuota"), subtitle: L("Solo Wine, nessun componente aggiuntivo"))
            }
            ForEach(model.presets) { p in
                tile(id: p.id, icon: p.icon.isEmpty ? "shippingbox" : p.icon, title: p.title, subtitle: p.steps.joined(separator: " · "),
                     help: p.description, badge: p.installs ? L("Installa") : nil)
            }
        }
    }

    private func tile(id: String?, icon: String, title: String, subtitle: String, help: String = "", badge: String? = nil) -> some View {
        let on = selection == id
        return Button { selection = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2).frame(width: 30)
                    .foregroundStyle(on ? Color.white : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.callout.weight(.semibold))
                        if let badge { Pill(text: badge, color: on ? .white : .accentColor) }
                    }
                    Text(subtitle).font(.caption).lineLimit(2)
                        .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.accentColor : Color.secondary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .contextMenu {
            if let p = model.preset(id), p.user == true {
                Button(L("Modifica…")) { if let path = p.path { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
                Button(L("Elimina ricetta"), role: .destructive) {
                    if selection == id { selection = nil }
                    Task { _ = await model.removePreset(p) }
                }
            } else if let p = model.preset(id), let path = p.path {
                Button(L("Mostra file")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
        }
    }
}

/// Menu with the recipe management commands.
struct PresetManageBar: View {
    @Environment(AppModel.self) private var model
    @State private var askURL = false
    @State private var askNew = false
    @State private var text = ""
    @State private var message: String?

    private func perform(_ op: @escaping () async -> String) {
        Task { let m = await op(); if !m.isEmpty { message = m } }
    }

    var body: some View {
        Menu {
            Button(L("Aggiungi da file…")) {
                let p = NSOpenPanel()
                p.title = L("Scegli un file .preset")
                p.allowedContentTypes = []
                p.allowsOtherFileTypes = true
                if p.runModal() == .OK, let u = p.url { perform { await model.addPreset(from: u.path) } }
            }
            Button(L("Aggiungi da indirizzo web…")) { text = "https://"; askURL = true }
            Button(L("Nuova ricetta personale…")) { text = ""; askNew = true }
            Divider()
            Button(L("Aggiorna ricette scaricate")) { perform { await model.updatePresets() } }
            Button(L("Apri cartella ricette personali")) {
                let dir = model.supportDir.appendingPathComponent("Presets")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
        } label: { Label(L("Gestisci ricette"), systemImage: "slider.horizontal.3") }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .alert(L("Aggiungi ricetta da indirizzo web"), isPresented: $askURL) {
            TextField("https://…/ricetta.preset", text: $text)
            Button(L("Annulla"), role: .cancel) {}
            Button(L("Aggiungi")) { let u = text; perform { await model.addPreset(from: u) } }
        } message: {
            Text(L("Aggiungi solo ricette di fonti fidate: possono scaricare ed eseguire programmi nella bottiglia."))
        }
        .alert(L("Nuova ricetta personale"), isPresented: $askNew) {
            TextField(L("nome (es. mio-gioco)"), text: $text)
            Button(L("Annulla"), role: .cancel) {}
            Button(L("Crea")) { let n = text.lowercased(); perform { await model.newPreset(n) } }
        } message: {
            Text(L("Verrà creato un modello da modificare con un editor di testo."))
        }
        .alert(L("Ricette"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

struct BranchPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String
    var body: some View {
        Picker(L("Versione di Wine"), selection: $selection) {
            Text(L("Predefinita (%@)", "\(model.defaultBranch.title)")).tag("default")
            Divider()
            ForEach(Branch.allCases) { b in
                let st = model.status(for: b)
                Text(st?.isInstalled == true ? "\(b.title) \(st!.installed)" : L("%@ — non installata", "\(b.title)")).tag(b.rawValue)
            }
        }
    }
}

struct OpenWithSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @State private var bottleName = ""
    @State private var addToPrograms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L("Esegui con Wine"), systemImage: "play.circle").font(.title2.bold())
            ForEach(urls, id: \.self) { u in
                Label(u.lastPathComponent, systemImage: "doc").font(.headline)
            }
            if model.bottles.isEmpty {
                Text(L("Prima crea una bottiglia in cui eseguire il programma.")).foregroundStyle(.secondary)
                Button(L("Nuova bottiglia…")) { dismiss(); model.showNewBottle = true }
            } else {
                Form {
                    Picker(L("Bottiglia"), selection: $bottleName) {
                        ForEach(model.bottles) { Text($0.name).tag($0.name) }
                    }
                    Toggle(L("Aggiungi all'elenco dei programmi della bottiglia"), isOn: $addToPrograms)
                }
                .formStyle(.grouped)
            }
            HStack {
                Spacer()
                Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Esegui")) {
                    if let b = model.bottle(named: bottleName) {
                        for u in urls {
                            if addToPrograms { model.addPrograms([Program(name: u.deletingPathExtension().lastPathComponent, path: u.path)], to: b) }
                            model.run(u.path, in: b)
                        }
                        model.selection = .bottle(b.name)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.bottle(named: bottleName) == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if case .bottle(let n) = model.selection { bottleName = n } else { bottleName = model.bottles.first?.name ?? "" }
        }
    }
}
