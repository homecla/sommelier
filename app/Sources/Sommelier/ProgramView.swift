// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI

/// Sidebar row for a saved program: file icon, name, bottle, running indicator.
struct ProgramSidebarRow: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    let program: Program

    var body: some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(program.name).lineLimit(1)
                    Text(bottle.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !model.runningJobs(for: program, in: bottle).isEmpty {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                        .help(L("In esecuzione"))
                }
            }
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: program.path))
                .resizable().frame(width: 18, height: 18)
        }
        .contextMenu {
            Button(L("Avvia")) { model.run(program.path, args: program.args ?? [], in: bottle, title: program.name) }
            Button(L("Apri bottiglia")) { model.selection = .bottle(bottle.name) }
            Button(L("Mostra nel Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program.path)])
            }
        }
    }
}

/// Detail page of a saved program: launch it, see where it lives and how it starts.
struct ProgramDetailView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    let program: Program

    var body: some View {
        let running = model.runningJobs(for: program, in: bottle)
        let missing = !FileManager.default.fileExists(atPath: program.path)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: program.path))
                        .resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name).font(.largeTitle.bold())
                        Label(bottle.name, systemImage: "wineglass").foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button { model.run(program.path, args: program.args ?? [], in: bottle, title: program.name) } label: {
                        Label(L("Avvia"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(missing)
                    if !running.isEmpty {
                        Button(L("Chiudi")) { running.forEach { $0.stop() } }.controlSize(.large)
                    }
                    Button(L("Apri bottiglia")) { model.selection = .bottle(bottle.name) }.controlSize(.large)
                    Button(L("Mostra nel Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program.path)])
                    }
                    .controlSize(.large)
                    .disabled(missing)
                }

                if !running.isEmpty {
                    Label(L("In esecuzione"), systemImage: "circle.fill")
                        .foregroundStyle(.green).font(.callout)
                }
                if missing {
                    Label(L("File non trovato"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }

                GroupBox {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                        row(L("Bottiglia"), bottle.name)
                        row(L("Versione di Wine"), branchText)
                        row(L("Percorso"), program.path, mono: true)
                        row(L("Argomenti di avvio"), (program.args ?? []).isEmpty ? "—" : (program.args ?? []).joined(separator: " "), mono: true)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(program.name)
    }

    private var branchText: String {
        if bottle.branch == "default" { return L("Predefinita (%@)", "\(model.defaultBranch.title)") }
        return Branch(rawValue: bottle.branch)?.title ?? bottle.branch
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String, mono: Bool = false) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
