import SwiftData
import SwiftUI

/// Modal view for creating a new variant with custom dimensions.
///
/// Dimensions can be typed freely, or prefilled from a discovered Flaschen
/// Taschen display (PRD §3 "Dimension Matching", User Workflow step 5 Option A).
/// Picking a display fills the width/height fields from its native size and tags
/// the created variant with that display's `id`; choosing "Custom" leaves the
/// typed values untouched and records no association.
struct VariantCreationView: View {
    @Environment(\.dismiss) var dismiss

    /// Persisted FT displays, available since #0011, used to offer native sizes.
    @Query(sort: \FlaschenTaschenDisplay.displayName) private var displays: [FlaschenTaschenDisplay]

    @State private var width: String = "32"
    @State private var height: String = "32"
    /// The display whose dimensions were used, or `nil` for custom entry.
    @State private var selectedDisplayId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Creates the variant at the given dimensions, tagged with the optional
    /// associated FT display id.
    var onCreateVariant: (Int, Int, UUID?) async -> Void

    var isValid: Bool {
        if let w = Int(width), let h = Int(height) {
            return w > 0 && w <= 512 && h > 0 && h <= 512
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                if !displays.isEmpty {
                    Section("Flaschen Taschen Display") {
                        Picker("Match Display", selection: $selectedDisplayId) {
                            Text("Custom").tag(UUID?.none)
                            ForEach(displays) { display in
                                Text("\(display.displayName) (\(display.resolution))")
                                    .tag(UUID?.some(display.id))
                            }
                        }
                        .onChange(of: selectedDisplayId) { _, newValue in
                            prefillDimensions(for: newValue)
                        }
                    }
                }

                Section("Target Dimensions") {
                    HStack {
                        Text("Width (pixels)")
                        Spacer()
                        TextField("Width", text: $width)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #else
                            .labelsHidden()
                            #endif
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Height (pixels)")
                        Spacer()
                        TextField("Height", text: $height)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #else
                            .labelsHidden()
                            #endif
                            .frame(width: 100)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Constraints") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Width and height must be between 1 and 512 pixels")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Smaller dimensions create more abstract pixel art")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Variant")
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
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Create Variant") {
                            createVariant()
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
        #if os(macOS)
        // Sheets on macOS don't size themselves to a Form's content; without an
        // explicit frame the sheet collapses and the form rows are invisible (#0024).
        .frame(minWidth: 440, minHeight: 440)
        #endif
    }

    /// Fill the dimension fields from the chosen display's native size. A `nil`
    /// selection ("Custom") leaves the typed values as-is so manual entry is
    /// preserved.
    private func prefillDimensions(for displayId: UUID?) {
        guard let displayId,
              let display = displays.first(where: { $0.id == displayId }) else {
            return
        }
        width = String(display.displayWidth)
        height = String(display.displayHeight)
    }

    /// The display id to record on the variant. A selected display only counts
    /// if the typed dimensions still match its native size — if the user edited
    /// a field after picking, the variant is treated as custom (no association).
    private var associatedDisplayId: UUID? {
        guard let selectedDisplayId,
              let display = displays.first(where: { $0.id == selectedDisplayId }),
              Int(width) == display.displayWidth,
              Int(height) == display.displayHeight else {
            return nil
        }
        return selectedDisplayId
    }

    private func createVariant() {
        guard let targetWidth = Int(width), let targetHeight = Int(height) else {
            errorMessage = "Invalid dimensions"
            return
        }

        guard targetWidth > 0, targetWidth <= 512, targetHeight > 0, targetHeight <= 512 else {
            errorMessage = "Dimensions must be between 1 and 512"
            return
        }

        errorMessage = nil
        isLoading = true

        let displayId = associatedDisplayId
        Task {
            await onCreateVariant(targetWidth, targetHeight, displayId)
            isLoading = false
            dismiss()
        }
    }
}

#Preview {
    VariantCreationView(onCreateVariant: { _, _, _ in })
}
