// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Job.ID?

    var body: some View {
        HSplitView {
            List(model.jobs, selection: $selected) { j in
                HStack(spacing: 8) {
                    statusIcon(j)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(j.title).lineLimit(1)
                        Text([j.bottle.map { "«\($0)»" }, j.started.formatted(date: .omitted, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(j.id)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            .overlay {
                if model.jobs.isEmpty {
                    ContentUnavailableView(L("Nessuna attività"), systemImage: "list.bullet.rectangle.portrait",
                                           description: Text(L("Installazioni e programmi avviati compariranno qui.")))
                }
            }

            Group {
                if let j = model.jobs.first(where: { $0.id == selected }) ?? model.jobs.first {
                    JobLogView(job: j)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("Attività"))
        .toolbar {
            ToolbarItem {
                Button { model.jobs.removeAll { !$0.running } } label: { Label(L("Pulisci completate"), systemImage: "trash") }
                    .disabled(model.jobs.allSatisfy(\.running))
            }
        }
    }

    @ViewBuilder func statusIcon(_ j: Job) -> some View {
        if j.running { ProgressView().controlSize(.small).frame(width: 16) }
        else if j.error != nil || (j.exitCode ?? 0) != 0 { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
        else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
    }
}

struct JobLogView: View {
    let job: Job

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.headline)
                    Text(statusText).font(.caption).foregroundStyle(job.error != nil ? .red : .secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.lines.joined(separator: "\n"), forType: .string)
                } label: { Label(L("Copia"), systemImage: "doc.on.doc") }
                if job.running { Button(L("Interrompi")) { job.stop() } }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(job.lines.isEmpty ? (job.running ? L("In attesa di output…") : L("Nessun output.")) : job.lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: job.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    var statusText: String {
        if job.running { return job.step.isEmpty ? L("In esecuzione…") : job.step }
        if let e = job.error { return L("Errore: %@", "\(e)") }
        if let c = job.exitCode, c != 0 { return L("Terminato con codice %@", "\(c)") }
        return L("Completato")
    }
}
