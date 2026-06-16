import SwiftUI
import SwiftData

/// Application entry point. Atlas Tune is a document-style, multi-window iPadOS app: each
/// window hosts one calibration workspace, and Stage Manager / external displays are supported
/// for free via `WindowGroup` and adaptive layout.
@main
struct AtlasTuneApp: App {
    /// SwiftData container backing project library + revision metadata.
    ///
    /// Prefers a CloudKit-synced store, but degrades gracefully: when the iCloud entitlement is
    /// unavailable (e.g. running inside Swift Playgrounds without a provisioning profile) it falls
    /// back to a local store, then to an in-memory store, so the app always launches.
    let modelContainer: ModelContainer = {
        let schema = Schema([
            StoredProject.self,
            StoredRevision.self,
            StoredLogSession.self,
        ])
        let candidates: [ModelConfiguration] = [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic),
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false),
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
        ]
        for configuration in candidates {
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return container
            }
        }
        fatalError("Unable to create ModelContainer for Atlas Tune")
    }()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
        }
        .modelContainer(modelContainer)
    }
}
