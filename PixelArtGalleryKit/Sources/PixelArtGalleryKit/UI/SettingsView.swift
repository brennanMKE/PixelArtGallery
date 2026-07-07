import SwiftData
import SwiftUI

/// App settings surface for the default Flaschen Taschen display (#0021).
///
/// Edits the persisted `source == "default"` ``FlaschenTaschenDisplay`` record
/// that is seeded on first launch, so the "Send to Display" picker always has a
/// target out of the box. The same view backs both platforms: macOS presents it
/// in a `Settings` scene (⌘,), iOS in a sheet reached from the gallery toolbar.
///
/// Raw field text is validated through ``ManualDisplayInput`` — the same
/// unit-tested rules used by the manual display entry form — before anything is
/// written back to the record.
public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    /// The seeded default display record, if it still exists. Filtered on the
    /// string literal `"default"` because `#Predicate` cannot reference
    /// ``FlaschenTaschenDisplay/defaultSource`` — keep the two in sync.
    @Query(filter: #Predicate<FlaschenTaschenDisplay> { $0.source == "default" })
    private var defaultDisplays: [FlaschenTaschenDisplay]

    @State private var host: String = ""
    @State private var port: String = ""
    @State private var displayName: String = ""
    @State private var width: String = ""
    @State private var height: String = ""
    @State private var layer: Int = FlaschenTaschenDisplay.defaultLayer
    @State private var errorMessage: String?
    @State private var savedConfirmation = false

    public init() {}

    private var defaultDisplay: FlaschenTaschenDisplay? {
        defaultDisplays.first
    }

    private var input: ManualDisplayInput {
        ManualDisplayInput(
            host: host,
            port: port,
            displayName: displayName,
            width: width,
            height: height
        )
    }

    public var body: some View {
        Form {
            if let display = defaultDisplay {
                editorSections(for: display)
            } else {
                missingDefaultSection
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
        .onAppear {
            loadFields()
        }
        .onChange(of: defaultDisplay?.id) {
            loadFields()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func editorSections(for display: FlaschenTaschenDisplay) -> some View {
        Section("Default Flaschen Taschen Display") {
            labeledField("Name", prompt: "Flaschen Taschen", text: $displayName)
            labeledField("Host", prompt: "flaschentaschen.local", text: $host, isHostField: true)
            labeledField("Port", prompt: "1337", text: $port, numeric: true)
            labeledField("Width (pixels)", prompt: "45", text: $width, numeric: true)
            labeledField("Height (pixels)", prompt: "35", text: $height, numeric: true)
            Stepper(value: $layer, in: FlaschenTaschenDisplay.layerRange) {
                HStack {
                    Text("Default Layer")
                    Spacer()
                    Text("\(layer)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: layer) {
                savedConfirmation = false
            }
        }

        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }

        Section {
            Button("Save Changes") {
                save(to: display)
            }
            .disabled(!input.isValid)

            if savedConfirmation {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } footer: {
            Text("This display is always available in the Send to Display picker and the display registry.")
        }
    }

    private var missingDefaultSection: some View {
        Section {
            HStack(alignment: .top) {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                Text("No default display is configured.")
                    .foregroundStyle(.secondary)
            }
            Button("Restore Default Display") {
                restoreDefault()
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } footer: {
            Text("Restores the built-in Flaschen Taschen display (flaschentaschen.local, 45×35, port 1337).")
        }
    }

    /// A labeled trailing text-field row matching ``ManualDisplayEntryView``'s
    /// styling, so Settings feels consistent with the rest of the display UI.
    private func labeledField(
        _ label: String,
        prompt: String,
        text: Binding<String>,
        numeric: Bool = false,
        isHostField: Bool = false
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                #if os(macOS)
                .labelsHidden()
                #endif
                #if os(iOS)
                .keyboardType(numeric ? .numberPad : (isHostField ? .URL : .default))
                .textInputAutocapitalization(isHostField ? .never : nil)
                .autocorrectionDisabled(isHostField)
                #endif
                .frame(maxWidth: numeric ? 100 : 220)
        }
        .onChange(of: text.wrappedValue) {
            savedConfirmation = false
        }
    }

    // MARK: - Actions

    /// Populate the working field text from the persisted default record.
    private func loadFields() {
        guard let display = defaultDisplay else { return }
        host = display.host
        port = String(display.port)
        displayName = display.displayName
        width = String(display.displayWidth)
        height = String(display.displayHeight)
        layer = FlaschenTaschenDisplay.clampedLayer(display.layer)
        errorMessage = nil
        savedConfirmation = false
    }

    /// Validate the field text and write it back to the persisted record.
    private func save(to display: FlaschenTaschenDisplay) {
        switch input.validate() {
        case .failure(let error):
            errorMessage = error.message
            savedConfirmation = false
        case .success(let validated):
            display.host = validated.host
            display.port = validated.port
            display.displayName = validated.displayName
            display.displayWidth = validated.width
            display.displayHeight = validated.height
            display.layer = FlaschenTaschenDisplay.clampedLayer(layer)
            do {
                try modelContext.save()
                errorMessage = nil
                savedConfirmation = true
                AppLog.ftDiscovery.info("Updated default display: \(validated.displayName, privacy: .public) at \(validated.host, privacy: .public):\(validated.port) (\(validated.width)×\(validated.height))")
            } catch {
                errorMessage = error.localizedDescription
                AppLog.ftDiscovery.error("Failed to save default display: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Re-create the built-in default record after the user deleted it.
    private func restoreDefault() {
        let display = FlaschenTaschenDisplay.makeDefault()
        modelContext.insert(display)
        do {
            try modelContext.save()
            errorMessage = nil
            AppLog.ftDiscovery.info("Restored default display from Settings")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to restore default display: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    SettingsView()
}
