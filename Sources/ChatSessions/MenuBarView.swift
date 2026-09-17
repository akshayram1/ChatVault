import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.blockedFolders.isEmpty {
                Button("macOS blocked some folders — click to fix") {
                    model.showPermissions = true
                }
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.2))
                Divider()
            }
            List(model.filtered, selection: $model.selectedID) { session in
                SessionRow(session: session, date: model.format(session.updated))
                    .tag(session.id)
                    .contextMenu {
                        Button("Copy path") { model.copyPath(session) }
                        Button("Reveal in Finder") { model.reveal(session) }
                    }
            }
            .listStyle(.sidebar)
            Divider()
            if let session = model.selected {
                detail(session)
                Divider()
            }
            footer
        }
        .frame(width: 420, height: 560)
        .sheet(isPresented: $model.showPermissions) {
            PermissionsView(model: model)
        }
        .onChange(of: model.includeSubagents) { _, _ in
            Task { await model.scan() }
        }
        .onChange(of: model.selectedID) { _, _ in
            model.grepHits = []
            model.grepPattern = ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search chats", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await model.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Rescan")
            }
            Picker("Source", selection: $model.sourceFilter) {
                ForEach(SourceFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(10)
    }

    private func detail(_ session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title)
                .font(.headline)
                .lineLimit(2)
            Text(session.source.label + (session.project.isEmpty ? "" : " · \(session.project)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                Button("Copy path") { model.copyPath(session) }
                Button("Finder") { model.reveal(session) }
            }
            HStack {
                TextField("Grep this chat", text: $model.grepPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.grepSelected() }
                Button(model.isGrepping ? "…" : "Grep") {
                    model.grepSelected()
                }
                .disabled(model.grepPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGrepping)
                .keyboardShortcut(.defaultAction)
            }
            if !model.grepHits.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.grepHits.prefix(8)) { hit in
                            Text(hit.text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
        }
        .padding(10)
    }

    private var footer: some View {
        HStack {
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            Text(model.progress.isEmpty ? "\(model.filtered.count) chats" : model.progress)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
    }
}
