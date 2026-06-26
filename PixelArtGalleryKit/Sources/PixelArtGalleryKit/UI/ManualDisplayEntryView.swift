import SwiftUI

/// Pure, testable validation of the raw text a user types into the manual
/// display entry form. Holding this apart from the SwiftUI view keeps the
/// parsing/validation rules unit-testable without standing up a view.
nonisolated struct ManualDisplayInput: Equatable {
    var host: String
    var port: String
    var displayName: String
    var width: String
    var height: String

    /// A fully validated set of values ready to persist.
    struct Validated: Equatable {
        var host: String
        var port: Int
        var displayName: String
        var width: Int
        var height: Int
    }

    /// Reasons the input cannot be turned into a display, in priority order.
    enum ValidationError: Error, Equatable {
        case emptyHost
        case invalidPort
        case invalidWidth
        case invalidHeight

        var message: String {
            switch self {
            case .emptyHost: return "Enter a host name or IP address."
            case .invalidPort: return "Port must be a number between 1 and 65535."
            case .invalidWidth: return "Width must be a positive number."
            case .invalidHeight: return "Height must be a positive number."
            }
        }
    }

    /// Validate and normalize the raw input.
    ///
    /// Rules:
    /// - `host` must be non-empty once trimmed.
    /// - `port` must parse to an integer in 1...65535.
    /// - `width`/`height` must parse to positive integers.
    /// - `displayName` is trimmed; if empty it falls back to the host so a
    ///   display always has a usable label.
    func validate() -> Result<Validated, ValidationError> {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return .failure(ValidationError.emptyHost) }

        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portValue = Int(trimmedPort), (1...65535).contains(portValue) else {
            return .failure(ValidationError.invalidPort)
        }

        guard let widthValue = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)), widthValue > 0 else {
            return .failure(ValidationError.invalidWidth)
        }

        guard let heightValue = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)), heightValue > 0 else {
            return .failure(ValidationError.invalidHeight)
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? trimmedHost : trimmedName

        return .success(
            Validated(
                host: trimmedHost,
                port: portValue,
                displayName: name,
                width: widthValue,
                height: heightValue
            )
        )
    }

    /// Convenience flag for enabling/disabling the confirm button.
    var isValid: Bool {
        if case .success = validate() { return true }
        return false
    }
}

/// Modal form for manually adding a Flaschen Taschen display when mDNS
/// discovery fails or isn't available. Mirrors ``VariantCreationView`` in style.
struct ManualDisplayEntryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var port: String = "1337"
    @State private var displayName: String = ""
    @State private var width: String = "64"
    @State private var height: String = "64"
    @State private var errorMessage: String?

    /// Persists the validated display. Throws so persistence failures surface
    /// to the user without dismissing.
    var onAddDisplay: (ManualDisplayInput.Validated) throws -> Void

    private var input: ManualDisplayInput {
        ManualDisplayInput(
            host: host,
            port: port,
            displayName: displayName,
            width: width,
            height: height
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("192.168.1.50", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            #endif
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("1337", text: $port)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }
                }

                Section("Display") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Office Wall", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Width (pixels)")
                        Spacer()
                        TextField("64", text: $width)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Height (pixels)")
                        Spacer()
                        TextField("64", text: $height)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section("About") {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Use this to add a display by hand when it isn't found automatically on your network.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Display")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addDisplay()
                    }
                    .disabled(!input.isValid)
                }
            }
        }
    }

    private func addDisplay() {
        switch input.validate() {
        case .failure(let error):
            errorMessage = error.message
        case .success(let validated):
            do {
                try onAddDisplay(validated)
                errorMessage = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ManualDisplayEntryView(onAddDisplay: { _ in })
}
