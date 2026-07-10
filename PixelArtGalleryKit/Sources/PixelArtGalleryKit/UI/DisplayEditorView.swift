import SwiftUI

/// Pure, testable validation of the raw text a user types into the display
/// editor form. Holding this apart from the SwiftUI view keeps the
/// parsing/validation rules unit-testable without standing up a view. Shared
/// by both add and edit modes of ``DisplayEditorView`` and by the retired
/// per-display Settings editor (#0054).
nonisolated struct ManualDisplayInput: Equatable {
    var host: String
    var port: String
    var displayName: String
    var width: String
    var height: String
    /// Default horizontal paint offset (FT x-offset), as raw text (#0056).
    var offsetX: String = "0"
    /// Default vertical paint offset (FT y-offset), as raw text (#0056).
    var offsetY: String = "0"

    /// A fully validated set of values ready to persist.
    struct Validated: Equatable {
        var host: String
        var port: Int
        var displayName: String
        var width: Int
        var height: Int
        var offsetX: Int = 0
        var offsetY: Int = 0
    }

    /// Reasons the input cannot be turned into a display, in priority order.
    enum ValidationError: Error, Equatable {
        case emptyHost
        case invalidPort
        case invalidWidth
        case invalidHeight
        case invalidOffsetX
        case invalidOffsetY

        var message: String {
            switch self {
            case .emptyHost: return "Enter a host name or IP address."
            case .invalidPort: return "Port must be a number between 1 and 65535."
            case .invalidWidth: return "Width must be a positive number."
            case .invalidHeight: return "Height must be a positive number."
            case .invalidOffsetX: return "X offset must be zero or a positive number."
            case .invalidOffsetY: return "Y offset must be zero or a positive number."
            }
        }
    }

    /// Validate and normalize the raw input.
    ///
    /// Rules:
    /// - `host` must be non-empty once trimmed.
    /// - `port` must parse to an integer in 1...65535.
    /// - `width`/`height` must parse to positive integers.
    /// - `offsetX`/`offsetY` must parse to integers ≥ 0 (#0056).
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

        guard let offsetXValue = Int(offsetX.trimmingCharacters(in: .whitespacesAndNewlines)), offsetXValue >= 0 else {
            return .failure(ValidationError.invalidOffsetX)
        }

        guard let offsetYValue = Int(offsetY.trimmingCharacters(in: .whitespacesAndNewlines)), offsetYValue >= 0 else {
            return .failure(ValidationError.invalidOffsetY)
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? trimmedHost : trimmedName

        return .success(
            Validated(
                host: trimmedHost,
                port: portValue,
                displayName: name,
                width: widthValue,
                height: heightValue,
                offsetX: offsetXValue,
                offsetY: offsetYValue
            )
        )
    }

    /// Convenience flag for enabling/disabling the confirm button.
    var isValid: Bool {
        if case .success = validate() { return true }
        return false
    }
}

/// Modal form for adding a Flaschen Taschen display by hand, or editing an
/// existing one in place (#0054). One reusable editor backs both flows so a
/// display is never a delete-and-recreate operation:
///
/// - **Add** — used when mDNS discovery fails or isn't available; fields start
///   blank/defaulted.
/// - **Edit** — fields are prefilled from an existing ``FlaschenTaschenDisplay``
///   (including its default paint layer) and the confirm button reads "Save".
///
/// Mirrors ``VariantCreationView`` in style. Validation always goes through
/// ``ManualDisplayInput`` regardless of mode.
struct DisplayEditorView: View {
    /// Which display, if any, is being edited. `add` starts from blank/default
    /// fields; `edit` prefills from the given display and writes back to it.
    enum Mode {
        case add
        case edit(FlaschenTaschenDisplay)

        var title: String {
            switch self {
            case .add: return "Add Display"
            case .edit: return "Edit Display"
            }
        }

        var confirmTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var host: String
    @State private var port: String
    @State private var displayName: String
    @State private var width: String
    @State private var height: String
    @State private var layer: Int
    @State private var offsetX: String
    @State private var offsetY: String
    @State private var errorMessage: String?

    /// Persists the validated fields (including default x/y offsets, #0056)
    /// plus the chosen layer. Throws so persistence failures surface to the
    /// user without dismissing.
    var onSave: (ManualDisplayInput.Validated, Int) throws -> Void

    init(mode: Mode, onSave: @escaping (ManualDisplayInput.Validated, Int) throws -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _host = State(initialValue: "")
            _port = State(initialValue: "1337")
            _displayName = State(initialValue: "")
            _width = State(initialValue: "64")
            _height = State(initialValue: "64")
            _layer = State(initialValue: FlaschenTaschenDisplay.defaultLayer)
            _offsetX = State(initialValue: "0")
            _offsetY = State(initialValue: "0")
        case .edit(let display):
            _host = State(initialValue: display.host)
            _port = State(initialValue: String(display.port))
            _displayName = State(initialValue: display.displayName)
            _width = State(initialValue: String(display.displayWidth))
            _height = State(initialValue: String(display.displayHeight))
            _layer = State(initialValue: FlaschenTaschenDisplay.clampedLayer(display.layer))
            _offsetX = State(initialValue: String(FlaschenTaschenDisplay.clampedOffset(display.offsetX)))
            _offsetY = State(initialValue: String(FlaschenTaschenDisplay.clampedOffset(display.offsetY)))
        }
    }

    private var input: ManualDisplayInput {
        ManualDisplayInput(
            host: host,
            port: port,
            displayName: displayName,
            width: width,
            height: height,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("192.168.1.50", text: $host, prompt: Text("192.168.1.50"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            #endif
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("1337", text: $port, prompt: Text("1337"))
                            .textFieldStyle(.roundedBorder)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
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
                        TextField("Office Wall", text: $displayName, prompt: Text("Office Wall"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                    }

                    HStack {
                        Text("Width (pixels)")
                        Spacer()
                        TextField("64", text: $width, prompt: Text("64"))
                            .textFieldStyle(.roundedBorder)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Height (pixels)")
                        Spacer()
                        TextField("64", text: $height, prompt: Text("64"))
                            .textFieldStyle(.roundedBorder)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }
                }

                Section {
                    Stepper(value: $layer, in: FlaschenTaschenDisplay.layerRange) {
                        HStack {
                            Text("Default Layer")
                            Spacer()
                            Text("\(layer)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Default X Offset")
                        Spacer()
                        TextField("0", text: $offsetX, prompt: Text("0"))
                            .textFieldStyle(.roundedBorder)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Default Y Offset")
                        Spacer()
                        TextField("0", text: $offsetY, prompt: Text("0"))
                            .textFieldStyle(.roundedBorder)
                            #if os(macOS)
                            .labelsHidden()
                            #endif
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 100)
                    }
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("The paint layer (z-offset) and x/y offset used when sending to this display.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("About") {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Use this to add a display by hand when it isn't found automatically on your network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
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
                    Button(mode.confirmTitle) {
                        save()
                    }
                    .disabled(!input.isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
    }

    private func save() {
        switch input.validate() {
        case .failure(let error):
            errorMessage = error.message
        case .success(let validated):
            do {
                try onSave(validated, layer)
                errorMessage = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Add") {
    DisplayEditorView(mode: .add, onSave: { _, _ in })
}
