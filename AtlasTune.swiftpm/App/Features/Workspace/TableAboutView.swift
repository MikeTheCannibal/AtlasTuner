import SwiftUI
import AtlasTuneCore

/// The inspector "About" panel for the open table: an English name (auto-translated from German),
/// a plain-English explanation of what it does for the S58 tune, and one-tap links to look the
/// parameter up online (web search or ChatGPT) for a deeper explanation.
struct TableAboutView: View {
    @Bindable var model: WorkspaceModel
    let table: TableDefinition
    @Environment(\.openURL) private var openURL

    private var englishName: String { model.translatedName(table) }
    private var insight: CalibrationInsight { model.insight(for: table) }
    private var isGerman: Bool { model.looksGerman(table.name) }

    var body: some View {
        Group {
            Section("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(englishName).font(.headline)
                    if isGerman, englishName != table.name {
                        Text(table.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                Text(insight.summary)
                VStack(alignment: .leading, spacing: 4) {
                    Label("For the S58", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(insight.tuningNote).font(.callout)
                }
            }

            Section("Translation") {
                Toggle(isOn: $model.translationEnabled) {
                    Label("Auto-translate German → English", systemImage: "globe")
                }
            }

            Section("Look It Up") {
                Button { open(searchURL) } label: {
                    Label("Search the web", systemImage: "safari")
                }
                Button { open(chatGPTURL) } label: {
                    Label("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
        }
    }

    // MARK: Online lookup

    private var question: String {
        "What does the \"\(englishName)\" table do in a BMW S58 (MG1CS049) ECU tune?"
    }

    private var searchURL: URL? {
        encoded("https://www.google.com/search?q=", question + " BMW S58 calibration")
    }

    private var chatGPTURL: URL? {
        encoded("https://chatgpt.com/?q=", question)
    }

    private func encoded(_ base: String, _ text: String) -> URL? {
        guard let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: base + q)
    }

    private func open(_ url: URL?) {
        if let url { openURL(url) }
    }
}

private extension CharacterSet {
    /// URL query value safe set (stricter than `.urlQueryAllowed`, which permits `&`, `=`, `+`).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}
