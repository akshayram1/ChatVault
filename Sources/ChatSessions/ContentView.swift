import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if !model.blockedFolders.isEmpty {
                    HStack {
                        Text("macOS blocked some chat folders.")
                            .font(.caption)
                        Spacer()
                        Button("Fix access") { model.showPermissions = true }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.2))
                }
                List(model.filtered, selection: $model.selectedID) { session in
                    SessionRow(session: session, date: model.format(session.updated))
                        .tag(session.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            if let session = model.selected {
                SessionDetail(model: model, session: session)
            } else {
                Text("Pick a chat")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $model.query, prompt: "Search title, project, or first message")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Source", selection: $model.sourceFilter) {
                    ForEach(SourceFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Toggle("Subagents", isOn: $model.includeSubagents)
                Button {
                    model.showPermissions = true
                } label: {
                    Label("Access", systemImage: "lock.shield")
                }
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
            }
        }
        .navigationTitle("Chat Sessions")
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Text(model.progress.isEmpty ? "\(model.filtered.count) chats" : model.progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onChange(of: model.includeSubagents) { _, _ in
            Task { await model.scan() }
        }
        .onChange(of: model.selectedID) { _, _ in
            model.grepHits = []
        }
        .sheet(isPresented: $model.showPermissions) {
            PermissionsView(model: model)
        }
    }
}

struct SessionRow: View {
    let session: ChatSession
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.source.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(date).font(.caption).foregroundStyle(.secondary)
                if session.isSubagent {
                    Text("subagent").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(session.title).font(.headline).lineLimit(1)
            Text(session.firstPrompt.isEmpty ? session.project : session.firstPrompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetail: View {
    @ObservedObject var model: AppModel
    let session: ChatSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(session.title).font(.title2.bold())
                    Spacer()
                    Button("Copy path") { model.copyPath(session) }
                    Button("Reveal in Finder") { model.reveal(session) }
                }
                LabeledContent("Tool", value: session.source.label)
                LabeledContent("Updated", value: model.format(session.updated))
                LabeledContent("Project", value: session.project.isEmpty ? "—" : session.project)
                LabeledContent("ID", value: session.sessionId)
                LabeledContent("File", value: session.path.path)
                    .textSelection(.enabled)
                if !session.firstPrompt.isEmpty {
                    Text("First prompt").font(.headline)
                    Text(session.firstPrompt).textSelection(.enabled)
                }
                Divider()
                Text("Grep this chat").font(.headline)
                Text("Search the jsonl and copy snippets into any agent. The old thread is not reopened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Pattern", text: $model.grepPattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.grepSelected() }
                    Button(model.isGrepping ? "Searching…" : "Grep") {
                        model.grepSelected()
                    }
                    .disabled(model.grepPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGrepping)
                    .keyboardShortcut(.defaultAction)
                }
                if model.grepHits.isEmpty && !model.grepPattern.isEmpty && !model.isGrepping {
                    Text("No matches").foregroundStyle(.secondary)
                }
                ForEach(model.grepHits) { hit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line \(hit.line)\(hit.role.isEmpty ? "" : " · \(hit.role)")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(hit.text)
                            .textSelection(.enabled)
                            .font(.body)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }
}
