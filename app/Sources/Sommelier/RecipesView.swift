// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI

/// Recipes: those installed on the Mac and the online catalog to download more from.
struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @State private var urlField = ""
    @State private var urlError: String?
    @State private var editingURL = false
    @State private var confirmRemove: Preset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                catalogSection
                installedSection
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("Ricette"))
        .toolbar {
            ToolbarItem {
                Button { Task { await model.loadCatalog(refresh: true) } } label: {
                    if model.catalogLoading { ProgressView().controlSize(.small) }
                    else { Label(L("Aggiorna catalogo"), systemImage: "arrow.clockwise") }
                }
                .disabled(model.catalogURL.isEmpty || model.catalogLoading)
                .help(L("Riscarica il catalogo online"))
            }
        }
        .task {
            if model.presets.isEmpty { await model.loadPresets() }
            if model.catalog == nil { await model.loadCatalog() }
            urlField = model.catalogURL
        }
        .confirmationDialog(L("Eliminare la ricetta «%@»?", "\(confirmRemove?.title ?? "")"),
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button(L("Elimina"), role: .destructive) {
                if let p = confirmRemove { Task { await model.removeCatalogRecipe(p.id) } }
            }
        } message: { Text(L("Le bottiglie già configurate non cambiano.")) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.gradient)
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 24)).foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Ricette")).font(.largeTitle.bold())
                Text(L("Configurazioni pronte per preparare una bottiglia: impostazioni, componenti e, se serve, l'installazione del programma."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Online catalog

    @ViewBuilder private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(L("Catalogo online"))
                Spacer()
                if model.catalogUpdates > 0 {
                    Button(L("Aggiorna tutte (%@)", "\(model.catalogUpdates)")) {
                        let ids = model.catalog?.recipes.filter { $0.state == "update" }.map(\.id) ?? []
                        Task { await model.installFromCatalog(ids) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !model.catalogURL.isEmpty && !editingURL {
                    Button(L("Cambia indirizzo…")) { urlField = model.catalogURL; editingURL = true }.buttonStyle(.link)
                }
            }

            if model.catalogURL.isEmpty || editingURL {
                urlEditor
            } else if let e = model.catalogError, model.catalog == nil {
                Banner(icon: "wifi.exclamationmark", color: .orange, title: L("Catalogo non disponibile"), text: e) {
                    Button(L("Riprova")) { Task { await model.loadCatalog(refresh: true) } }
                }
            } else if let c = model.catalog {
                if c.recipes.isEmpty {
                    Text(L("Il catalogo è vuoto.")).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) { ForEach(c.recipes) { CatalogRow(recipe: $0) } }
                }
                Text(c.url).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            } else {
                ProgressView(L("Carico il catalogo…")).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private var urlEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Indica l'indirizzo del catalogo (il file catalog.json pubblicato su GitHub)."))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("https://raw.githubusercontent.com/…/main/catalog.json", text: $urlField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveURL)
                Button(L("Salva"), action: saveURL).disabled(urlField.isEmpty)
                if editingURL { Button(L("Annulla")) { editingURL = false; urlError = nil } }
            }
            if let urlError { Text(urlError).font(.caption).foregroundStyle(.red) }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func saveURL() {
        let u = urlField
        Task {
            urlError = await model.setCatalogURL(u)
            if urlError == nil { editingURL = false }
        }
    }

    // MARK: Installed

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(L("Sul tuo Mac"))
                Spacer()
                PresetManageBar()
            }
            VStack(spacing: 8) {
                ForEach(model.presets) { p in
                    HStack(spacing: 12) {
                        Image(systemName: p.icon.isEmpty ? "shippingbox" : p.icon)
                            .font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.title).font(.headline)
                                if p.user == true {
                                    Pill(text: p.source?.isEmpty == false ? L("Dal catalogo") : L("Personale"), color: .purple)
                                } else {
                                    Pill(text: L("Integrata"), color: .secondary)
                                }
                                if p.installs { Pill(text: L("Installa programma"), color: .accentColor) }
                            }
                            Text(p.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            if !p.steps.isEmpty {
                                Text(p.steps.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if p.user == true {
                            Button { if let path = p.path { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } } label: {
                                Image(systemName: "pencil")
                            }
                            .help(L("Modifica"))
                            Button(role: .destructive) { confirmRemove = p } label: { Image(systemName: "trash") }
                                .help(L("Elimina"))
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

struct CatalogRow: View {
    @Environment(AppModel.self) private var model
    let recipe: CatalogRecipe

    var body: some View {
        let busy = model.catalogBusy.contains(recipe.id)
        HStack(spacing: 12) {
            Image(systemName: recipe.icon.isEmpty ? "shippingbox" : recipe.icon)
                .font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(recipe.title).font(.headline)
                    if recipe.installs { Pill(text: L("Installa programma"), color: .accentColor) }
                    switch recipe.state {
                    case "installed": Pill(text: L("Installata"), color: .green)
                    case "update": Pill(text: L("Aggiornamento"), color: .orange)
                    case "builtin": Pill(text: L("Integrata"), color: .secondary)
                    default: EmptyView()
                    }
                }
                Text(recipe.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                let steps = [recipe.winver.isEmpty ? nil : L("Windows %@", "\(recipe.winver.replacingOccurrences(of: "win", with: ""))"),
                             recipe.winetricks.isEmpty ? nil : recipe.winetricks.split(separator: " ").joined(separator: ", ")]
                    .compactMap { $0 }
                if !steps.isEmpty { Text(steps.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else {
                switch recipe.state {
                case "installed":
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("Già installata"))
                case "update":
                    Button(L("Aggiorna")) { Task { await model.installFromCatalog([recipe.id]) } }.buttonStyle(.borderedProminent)
                case "builtin":
                    Button(L("Scarica versione online")) { Task { await model.installFromCatalog([recipe.id]) } }
                        .help(L("Sostituisce la ricetta integrata con quella del catalogo, che riceverà gli aggiornamenti"))
                default:
                    Button { Task { await model.installFromCatalog([recipe.id]) } } label: { Label(L("Installa"), systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .help(recipe.notes)
    }
}
