// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI

struct VersionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let s = model.status, !s.rosetta {
                    Banner(icon: "exclamationmark.triangle.fill", color: .orange,
                           title: L("Rosetta 2 non è installato"),
                           text: L("Le build di Wine per macOS sono per Intel e su Apple Silicon hanno bisogno di Rosetta 2.")) {
                        Button(L("Installa Rosetta")) { model.installRosetta() }
                    }
                }
                if let e = model.statusError {
                    Banner(icon: "wifi.exclamationmark", color: .secondary,
                           title: L("Impossibile controllare gli aggiornamenti"), text: e) {
                        Button(L("Riprova")) { Task { await model.refreshStatus(force: true) } }
                    }
                }
                if model.updatesCount > 0 {
                    Banner(icon: "arrow.down.circle.fill", color: .accentColor,
                           title: model.updatesCount == 1 ? L("È disponibile un aggiornamento") : L("Sono disponibili %@ aggiornamenti", "\(model.updatesCount)"),
                           text: L("Le bottiglie e i programmi installati restano intatti.")) {
                        Button(L("Aggiorna tutto")) { model.updateAll() }.buttonStyle(.borderedProminent)
                    }
                }

                ForEach(Branch.allCases) { b in BranchCard(branch: b) }

                if let s = model.status {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text(L("Le versioni vengono installate in %@ · fonte: build ufficiali WineHQ per macOS (Gcenx/macOS_Wine_builds)", "\(s.installDir)"))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("Versioni di Wine"))
        .toolbar {
            ToolbarItem {
                Button { Task { await model.refreshStatus(force: true) } } label: {
                    if model.checking { ProgressView().controlSize(.small) } else { Label(L("Controlla aggiornamenti"), systemImage: "arrow.clockwise") }
                }
                .help(L("Controlla aggiornamenti (⌘R)"))
                .disabled(model.checking)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIconView(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Wine per macOS")).font(.largeTitle.bold())
                Text(L("Esegui programmi Windows sul Mac. Scegli quali versioni installare e quale usare come predefinita."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct BranchCard: View {
    @Environment(AppModel.self) private var model
    let branch: Branch
    @State private var confirmUninstall = false

    var body: some View {
        let st = model.status(for: branch)
        let job = model.job(forBranch: branch)
        let isDefault = model.defaultBranch == branch

        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(branch.color.gradient)
                    Text(String(branch.title.prefix(1))).font(.title2.bold()).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(L("Wine %@", "\(branch.title)")).font(.title3.bold())
                        if isDefault { Pill(text: L("Predefinita"), color: .accentColor) }
                        if st?.running == true { Pill(text: L("In uso"), color: .green) }
                        if st?.hasUpdate == true { Pill(text: L("Aggiornamento"), color: .orange) }
                    }
                    Text(branch.subtitle).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        VersionLabel(title: L("Installata"), value: st?.installed.isEmpty == false ? st!.installed : "—")
                        VersionLabel(title: L("Ultima"), value: latestText(st))
                    }
                    .padding(.top, 2)

                    if let job {
                        VStack(alignment: .leading, spacing: 4) {
                            if let p = job.progress, p < 1 {
                                ProgressView(value: p)
                            } else {
                                ProgressView().progressViewStyle(.linear)
                            }
                            Text(job.step.isEmpty ? L("Avvio…") : job.step).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                actions(st: st, job: job, isDefault: isDefault)
            }
            .padding(6)
        }
        .confirmationDialog(L("Disinstallare Wine %@?", "\(branch.title)"), isPresented: $confirmUninstall) {
            Button(L("Disinstalla"), role: .destructive) { model.uninstall(branch) }
        } message: {
            Text(L("Le bottiglie non vengono eliminate. Quelle che usano questa versione dovranno usarne un'altra."))
        }
    }

    private func latestText(_ st: BranchStatus?) -> String {
        guard let st, !st.latest.isEmpty else { return "—" }
        if let d = Self.parse.date(from: st.date) { return "\(st.latest) · \(d.formatted(date: .abbreviated, time: .omitted))" }
        return st.latest
    }
    private static let parse: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    @ViewBuilder
    private func actions(st: BranchStatus?, job: Job?, isDefault: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let job {
                Button(L("Annulla")) { job.stop() }
            } else if st?.isInstalled != true {
                Button { model.install(branch) } label: { Label(L("Installa"), systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(st?.latest.isEmpty ?? true)
            } else {
                if st?.hasUpdate == true {
                    Button { model.install(branch) } label: { Label(L("Aggiorna a %@", "\(st!.latest)"), systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                }
                Menu {
                    if !isDefault { Button(L("Usa come predefinita")) { model.setDefault(branch) } }
                    Button(L("Mostra nel Finder")) {
                        if let p = st?.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                    }
                    Button(L("Reinstalla")) { model.install(branch, force: true) }
                    Divider()
                    Button(L("Disinstalla…"), role: .destructive) { confirmUninstall = true }
                } label: { Label(L("Opzioni"), systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if st?.isInstalled != true, !isDefault, job == nil {
                Button(L("Imposta predefinita")) { model.setDefault(branch) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}

// MARK: - Components

struct VersionLabel: View {
    let title: String, value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

struct Pill: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Banner<Actions: View>: View {
    let icon: String, color: Color, title: String, text: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.25)))
    }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        if let img = NSApp.applicationIconImage, Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22).fill(LinearGradient(colors: [Color(red: 0.55, green: 0.1, blue: 0.2), Color(red: 0.3, green: 0.05, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "wineglass.fill").font(.system(size: size * 0.5)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}
