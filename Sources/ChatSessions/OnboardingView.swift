import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folder access").font(.title2.bold())
            Text("Chat Sessions only reads files already on this Mac. If a tool is not installed, that row stays unused.")
                .foregroundStyle(.secondary)
            ForEach(AccessKind.allCases) { kind in
                AccessRow(kind: kind, status: model.access.status[kind] ?? .denied) {
                    model.access.requestAccess(for: kind)
                }
            }
            HStack {
                Button("Select Home folder…") { model.access.requestHomeFolderAccess() }
                Button("Full Disk Access…") { model.access.openFullDiskAccessSettings() }
                Spacer()
                Button("Rescan") {
                    model.access.refreshStatus()
                    Task { await model.scan() }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480)
    }
}

struct AccessRow: View {
    let kind: AccessKind
    let status: AccessStatus
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.headline)
                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
            if status == .denied {
                Button("Grant Access", action: grant)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var label: String {
        switch status {
        case .granted: return "Allowed"
        case .missing: return "Not installed"
        case .denied: return "Needs access"
        }
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .missing: return .secondary
        case .denied: return .orange
        }
    }
}
