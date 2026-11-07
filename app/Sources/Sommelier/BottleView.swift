// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI
import UniformTypeIdentifiers

struct BottleView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    @State private var dropTargeted = false
    @State private var showScan = false
    @State private var showWinetricks = false
    @State private var showPresets = false
    @State private var confirmDelete: Bottle?
    @State private var renaming: Program?
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                dropZone
                programsSection
                runningSection
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup {
                Button { NSWorkspace.shared.open(bottle.driveC) } label: { Label(L("Apri C:"), systemImage: "internaldrive") }
                    .help(L("Apri il disco C: nel Finder"))
                Button { model.killBottle(bottle) } label: { Label(L("Termina tutto"), systemImage: "stop.circle") }
                    .help(L("Chiudi tutti i programmi Windows di questa bottiglia"))
            }
        }
        .sheet(isPresented: $showScan) { ScanSheet(bottle: bottle) }
        .sheet(isPresented: $showWinetricks) { WinetricksSheet(bottle: bottle) }
        .sheet(isPresented: $showPresets) { ApplyPresetSheet(bottle: bottle) }
        .confirmDelete($confirmDelete)
        .alert(L("Rinomina programma"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Nome"), text: $newName)
            Button(L("Annulla"), role: .cancel) {}
            Button(L("Rinomina")) {
                if let p = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.renameProgram(p, to: newName, in: bottle)
                }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.5, green: 0.1, blue: 0.2).gradient)
                Image(systemName: "wineglass.fill").font(.system(size: 26)).foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bottle.name).font(.largeTitle.bold())
                    if let p = model.preset(bottle.meta.preset) { Pill(text: p.title, color: .accentColor) }
                }
                Text(bottle.url.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            BranchPicker(selection: Binding(get: { bottle.branch }, set: { model.setBranch($0, for: bottle) }))
                .frame(width: 260)
        }
        .overlay(alignment: .bottomTrailing) { branchWarning.offset(y: 22) }
    }

    @ViewBuilder private var branchWarning: some View {
        let b = bottle.branch == "default" ? model.defaultBranch : (Branch(rawValue: bottle.branch) ?? .stable)
        if model.status != nil, model.status(for: b)?.isInstalled != true {
            Label(L("Wine %@ non è installato", "\(b.title)"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var dropZone: some View {
        Button { pickAndRun() } label: {
            VStack(spacing: 8) {
                Image(systemName: dropTargeted ? "arrow.down.app.fill" : "arrow.down.app")
                    .font(.system(size: 30))
                Text(L("Trascina qui un programma Windows")).font(.headline)
                Text(L(".exe, .msi, .bat, .lnk — oppure fai clic per sceglierlo")).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 14).fill(dropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.35),
                                                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.run(url.path, in: bottle) }
                }
            }
            return true
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(L("Programmi"))
                Spacer()
                Button { showScan = true } label: { Label(L("Cerca programmi installati"), systemImage: "magnifyingglass") }
                Button { addManually() } label: { Label(L("Aggiungi…"), systemImage: "plus") }
            }
            if bottle.programs.isEmpty {
                Text(L("Nessun programma nell'elenco. Esegui un installer qui sopra, poi premi «Cerca programmi installati» per aggiungere i collegamenti."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(bottle.programs) { p in ProgramTile(program: p, bottle: bottle, onRename: {
                        newName = p.name; renaming = p
                    }) }
                }
            }
        }
    }

    @ViewBuilder private var runningSection: some View {
        let running = model.jobs(forBottle: bottle.name)
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("In esecuzione"))
                ForEach(running) { j in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if !j.showsProgress { ProgressView().controlSize(.small) }
                            Text(j.title).lineLimit(1)
                            if !j.showsProgress, !j.step.isEmpty { Text("— \(j.step)").foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            Button(L("Registro")) { model.selection = .activity }.buttonStyle(.link)
                            if j.kind != .bottle { Button(L("Chiudi")) { j.stop() } }
                        }
                        if j.showsProgress { JobProgress(job: j) }
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(L("Strumenti"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ToolTile(L("Configurazione Wine"), "gearshape", L("Versione di Windows, grafica, audio, librerie")) { tool("winecfg", L("Configurazione Wine")) }
                ToolTile(L("Configurazioni predefinite"), "sparkles.rectangle.stack", L("Steam, giochi, app .NET…")) { showPresets = true }
                ToolTile(L("Winetricks"), "wand.and.stars", L("Font, runtime Visual C++, .NET, DirectX…")) { showWinetricks = true }
                ToolTile(L("Esplora risorse"), "folder", L("File manager di Windows")) { tool("explorer", L("Esplora risorse")) }
                ToolTile(L("Prompt dei comandi"), "terminal", L("cmd.exe in una finestra")) { tool("wineconsole", L("Prompt dei comandi"), ["cmd"]) }
                ToolTile(L("Editor del registro"), "list.bullet.indent", "regedit") { tool("regedit", L("Editor del registro")) }
                ToolTile(L("Pannello di controllo"), "slider.horizontal.3", L("Impostazioni di Windows")) { tool("control", L("Pannello di controllo")) }
                ToolTile(L("Installa/rimuovi programmi"), "trash.square", L("Disinstalla software Windows")) { tool("uninstaller", L("Disinstallazione programmi")) }
                ToolTile(L("Gestione attività"), "chart.bar.doc.horizontal", L("Processi Windows attivi")) { tool("taskmgr", L("Gestione attività")) }
                ToolTile(L("Terminale macOS"), "apple.terminal", L("Shell con wine e winetricks pronti")) { model.openTerminal(in: bottle) }
                ToolTile(L("Elimina bottiglia"), "trash", L("Sposta nel Cestino"), destructive: true) { confirmDelete = bottle }
            }
        }
    }

    // MARK: Actions

    private func tool(_ cmd: String, _ title: String, _ args: [String] = []) {
        model.run(cmd, args: args, in: bottle, title: title, kind: .tool)
    }

    private func pickAndRun() {
        if let urls = FilePicker.pickWindowsFiles() { urls.forEach { model.run($0.path, in: bottle) } }
    }

    private func addManually() {
        let p = NSOpenPanel()
        p.title = L("Aggiungi un programma all'elenco")
        p.prompt = L("Aggiungi")
        p.directoryURL = bottle.driveC.appendingPathComponent("Program Files")
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [UTType(filenameExtension: "exe"), UTType(filenameExtension: "lnk"),
                                 UTType(filenameExtension: "bat")].compactMap { $0 }
        if p.runModal() == .OK {
            model.addPrograms(p.urls.map { Program(name: $0.deletingPathExtension().lastPathComponent, path: $0.path) }, to: bottle)
        }
    }
}

// MARK: - Components

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.title3.bold()) }
}

struct ProgramTile: View {
    @Environment(AppModel.self) private var model
    let program: Program
    let bottle: Bottle
    var onRename: () -> Void
    @State private var hover = false

    var body: some View {
        let missing = !FileManager.default.fileExists(atPath: program.path)
        Button { model.run(program.path, args: program.args ?? [], in: bottle, title: program.name) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: program.path))
                    .resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name).font(.headline).lineLimit(1)
                    Text(missing ? L("File non trovato") : URL(fileURLWithPath: program.path).lastPathComponent)
                        .font(.caption).foregroundStyle(missing ? .red : .secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill").foregroundStyle(hover ? Color.accentColor : .secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(missing)
        .onHover { hover = $0 }
        .help(([program.path] + (program.args ?? [])).joined(separator: " "))
        .contextMenu {
            Button(L("Avvia")) { model.run(program.path, args: program.args ?? [], in: bottle, title: program.name) }
            Button(L("Rinomina…"), action: onRename)
            Button(L("Mostra nel Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program.path)]) }
            Divider()
            Button(L("Rimuovi dall'elenco"), role: .destructive) { model.removeProgram(program, from: bottle) }
        }
    }
}

struct ToolTile: View {
    let title: String, icon: String, subtitle: String
    var destructive = false
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, _ icon: String, _ subtitle: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.subtitle = subtitle; self.destructive = destructive; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title3).frame(width: 26)
                    .foregroundStyle(destructive ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(destructive ? .red : .primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Sheets

struct ScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State private var found: [Program] = []
    @State private var selected = Set<String>()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Programmi trovati in «%@»", "\(bottle.name)"), systemImage: "magnifyingglass").font(.title2.bold())
            if !loaded {
                ProgressView(L("Cerco…")).frame(maxWidth: .infinity, minHeight: 200)
            } else if found.isEmpty {
                ContentUnavailableView(L("Nessun nuovo programma"), systemImage: "tray",
                                       description: Text(L("Installa qualcosa nella bottiglia, poi riprova.")))
                    .frame(minHeight: 200)
            } else {
                List(found) { p in
                    Toggle(isOn: Binding(get: { selected.contains(p.path) },
                                         set: { if $0 { selected.insert(p.path) } else { selected.remove(p.path) } })) {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p.path)).resizable().frame(width: 20, height: 20)
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(p.path.replacingOccurrences(of: bottle.driveC.path, with: "C:"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(minHeight: 280)
            }
            HStack {
                if !found.isEmpty {
                    Button(selected.count == found.count ? L("Deseleziona tutto") : L("Seleziona tutto")) {
                        selected = selected.count == found.count ? [] : Set(found.map(\.path))
                    }
                }
                Spacer()
                Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Aggiungi %@", "\(selected.count)")) {
                    model.addPrograms(found.filter { selected.contains($0.path) }, to: bottle); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            found = model.scanPrograms(in: bottle)
            // preselect shortcuts (.lnk): they are usually the "real" programs
            selected = Set(found.filter { $0.path.lowercased().hasSuffix(".lnk") }.map(\.path))
            loaded = true
        }
    }
}

struct ApplyPresetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State private var presetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Configurazioni predefinite"), systemImage: "sparkles.rectangle.stack").font(.title2.bold())
            Text(L("Applica a «%@» le impostazioni e i componenti consigliati. I programmi già installati restano intatti.", "\(bottle.name)"))
                .font(.callout).foregroundStyle(.secondary)
            PresetGallery(selection: $presetID)
            if let p = model.preset(presetID) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.description).font(.callout)
                    if !p.notes.isEmpty { Label(p.notes, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                PresetManageBar()
                Spacer()
                Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Applica")) {
                    if let p = model.preset(presetID) { model.applyPreset(p, to: bottle) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetID == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { if model.presets.isEmpty { await model.loadPresets() } }
    }
}

struct WinetricksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State private var chosen = Set<String>()
    @State private var custom = ""

    static var common: [(String, String)] { [
        ("corefonts", L("Font Microsoft di base (Arial, Times…)")),
        ("vcrun2022", L("Visual C++ 2015–2022")),
        ("vcrun2010", L("Visual C++ 2010")),
        ("dotnet48", ".NET Framework 4.8"),
        ("d3dx9", L("DirectX 9 (d3dx9)")),
        ("d3dcompiler_47", L("Compilatore shader DirectX")),
        ("xact", L("Audio XACT (giochi)")),
        ("gdiplus", L("GDI+")),
        ("mfc140", L("MFC 14")),
        ("cjkfonts", L("Font cinesi/giapponesi/coreani")),
    ] }

    var body: some View {
        let verbs = Array(chosen).sorted() + custom.split(separator: " ").map(String.init)
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Winetricks"), systemImage: "wand.and.stars").font(.title2.bold())
            Text(L("Installa componenti Windows nella bottiglia «%@». Alcuni pacchetti richiedono diversi minuti.", "\(bottle.name)"))
                .font(.callout).foregroundStyle(.secondary)
            Label(L("Molti pacchetti (font, Visual C++, .NET, DirectX) sono software Microsoft scaricato dai server del produttore: installandoli accetti le relative condizioni di licenza."), systemImage: "doc.text")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(Self.common, id: \.0) { verb, desc in
                    Toggle(isOn: Binding(get: { chosen.contains(verb) },
                                         set: { if $0 { chosen.insert(verb) } else { chosen.remove(verb) } })) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verb).font(.callout.monospaced())
                            Text(desc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            TextField(L("Altri pacchetti (separati da spazio)"), text: $custom, prompt: Text(L("es. vb6run dxvk")))
                .textFieldStyle(.roundedBorder)
            Link(L("Elenco completo dei pacchetti"), destination: URL(string: "https://github.com/Winetricks/winetricks/blob/master/files/verbs/all.txt")!)
                .font(.caption)
            HStack {
                Spacer()
                Button(L("Annulla")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Installa")) { model.winetricks(verbs, in: bottle); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(verbs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
