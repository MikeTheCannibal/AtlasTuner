import SwiftUI
import SwiftData

/// Application entry point. Atlas Tune is a document-style, multi-window iPadOS app: each
/// window hosts one calibration workspace, and Stage Manager / external displays are supported
/// for free via `WindowGroup` and adaptive layout.
@main
struct AtlasTuneApp: App {
    /// SwiftData container backing project library + revision metadata, synced via CloudKit.
    let modelContainer: ModelContainer = {
        let schema = Schema([
            StoredProject.self,
            StoredRevision.self,
            StoredLogSession.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
        }
        .modelContainer(modelContainer)
    }
}
