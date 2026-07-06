import SwiftUI

/// Lightweight modal that lets the user confirm or edit the name of a freshly
/// picked image before it's imported. Prefilled with a suggested name (the
/// source filename where the picker provides one) and falling back to
/// ``defaultImportedImageName``. Mirrors ``ManualDisplayEntryView`` in style.
struct ImportNamingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String

    /// Persists the import under the supplied (trimmed) name. `async` because the
    /// coordinator's import path is async.
    var onConfirm: (String) async -> Void

    /// - Parameters:
    ///   - suggestedName: The picker's suggested name, used to prefill the field.
    ///   - onConfirm: Called with the user's chosen name when they confirm.
    init(suggestedName: String?, onConfirm: @escaping (String) async -> Void) {
        _name = State(initialValue: effectiveImportedImageName(from: suggestedName))
        self.onConfirm = onConfirm
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name to import under: the trimmed entry, or the default if empty.
    private var effectiveName: String {
        trimmedName.isEmpty ? defaultImportedImageName : trimmedName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(defaultImportedImageName, text: $name, prompt: Text(defaultImportedImageName))
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #else
                        .labelsHidden()
                        #endif
                }

                Section("About") {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Give this image a name so you can tell it apart in the gallery. You can rename it later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Name Image")
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
                    Button("Import") {
                        let chosen = effectiveName
                        dismiss()
                        Task { await onConfirm(chosen) }
                    }
                }
            }
        }
        #if os(macOS)
        // Sheets on macOS don't size themselves to a Form's content; without an
        // explicit frame the sheet collapses and the form rows are invisible (#0026,
        // same defect as #0024/#0025). Short sheet — just the Name field + About hint.
        .frame(minWidth: 440, minHeight: 300)
        #endif
    }
}

#Preview {
    ImportNamingView(suggestedName: "sunset.png", onConfirm: { _ in })
}
