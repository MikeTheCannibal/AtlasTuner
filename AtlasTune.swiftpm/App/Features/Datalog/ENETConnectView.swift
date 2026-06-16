import SwiftUI
import AtlasTuneCore

/// Connection sheet for live ENET (DoIP) capture. Collects the gateway address and poll rate,
/// then hands a configured `ENETDatalogSource` back to the caller to start.
struct ENETConnectView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("atlas.enet.host") private var host = "169.254.187.20"
    @AppStorage("atlas.enet.port") private var port = 13400
    @AppStorage("atlas.enet.rate") private var rate = 20.0
    @AppStorage("atlas.enet.extended") private var extendedSession = true

    let onConnect: (ENETDatalogSource) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    LabeledContent("Host") {
                        TextField("169.254.x.x", text: $host)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Port") {
                        TextField("13400", value: $port, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
                Section("Logging") {
                    Stepper("Poll rate: \(Int(rate)) Hz", value: $rate, in: 1...50, step: 1)
                    Toggle("Enter extended session", isOn: $extendedSession)
                }
                Section {
                    Text("Connects over a BMW ENET cable using DoIP + UDS ReadMemoryByAddress. Channels and scaling come from the vehicle A2L. The device must be on the vehicle's network and allow local-network access. Addresses are from software variant F4C2L8R6B — validate against your vehicle before trusting values.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Live ENET Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        let source = ENETDatalogSource(
                            host: host,
                            port: UInt16(clamping: port),
                            rate: rate,
                            extendedSession: extendedSession
                        )
                        onConnect(source)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
