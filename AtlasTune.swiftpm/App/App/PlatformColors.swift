import SwiftUI

extension Color {
    /// `UIColor.secondarySystemBackground` has no AppKit counterpart; use the closest semantic
    /// AppKit color on macOS.
    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
