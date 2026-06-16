import SwiftUI
import AtlasTuneCore

/// Lists the revision tree and offers a compare-to-stock diff. Saving a revision snapshots the
/// current working image (handled by the engine), so the list is the project's history.
struct RevisionListView: View {
    @Bindable var model: WorkspaceModel
    @State private var newName = ""
    @State private var comparison: CalibrationDifference?
    @State private var comparingTo: Revision?

    var body: some View {
        List {
            Section("Save") {
                HStack {
                    TextField("Revision name", text: $newName)
                    Button("Save") {
                        _ = model.saveRevision(name: newName.isEmpty ? "Revision" : newName)
                        newName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("History") {
                ForEach(model.project?.revisions.all ?? []) { revision in
                    Button {
                        compare(revision)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(revision.name).font(.body)
                            Text(revision.timestamp, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let comparison, let comparingTo {
                Section("Changes vs \(comparingTo.name)") {
                    if comparison.isIdentical {
                        Text("No differences").foregroundStyle(.secondary)
                    } else {
                        Text("\(comparison.changedTables.count) tables, \(comparison.totalChangedCells) cells")
                            .font(.caption)
                        ForEach(comparison.changedTables, id: \.tableID) { diff in
                            LabeledContent(diff.tableName, value: "\(diff.changedCount) cells")
                        }
                    }
                }
            }
        }
    }

    private func compare(_ revision: Revision) {
        comparingTo = revision
        comparison = model.project?.differenceFromWorking(to: revision.id)
    }
}
