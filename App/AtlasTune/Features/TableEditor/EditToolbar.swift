import SwiftUI
import AtlasTuneCore

/// The math edit bar: enter a value and apply an operation to the current selection. Covers the
/// spec's set / add / subtract / multiply / divide / percent plus interpolate, smooth and flatten.
struct EditToolbar: View {
    let apply: (EditOperation) -> Void

    @State private var amount: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            TextField("Value", value: $amount, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
            #endif

            Group {
                opButton("Set", "equal") { .set(amount) }
                opButton("Add", "plus") { .add(amount) }
                opButton("Sub", "minus") { .subtract(amount) }
                opButton("Mul", "multiply") { .multiply(amount) }
                opButton("Div", "divide") { .divide(amount) }
                opButton("%", "percent") { .percentChange(amount) }
            }

            Divider().frame(height: 24)

            Group {
                opButton("Interp", "arrow.left.and.right") { .interpolate(.horizontal) }
                opButton("Smooth", "wand.and.stars") { .smooth(passes: 1) }
                opButton("Flatten", "rectangle.compress.vertical") { .flatten }
            }
            Spacer()
        }
    }

    private func opButton(_ title: String, _ symbol: String, _ make: @escaping () -> EditOperation) -> some View {
        Button { apply(make()) } label: {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
                .frame(minWidth: 36, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .help(title)
    }
}
