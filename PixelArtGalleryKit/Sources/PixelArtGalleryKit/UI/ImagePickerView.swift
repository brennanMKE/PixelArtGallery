import SwiftUI

/// The fallback name used for an imported image when no source filename is
/// available (e.g. some Photos picker selections).
nonisolated let defaultImportedImageName = "Imported Image"

/// Resolve the effective name for an imported image from an optional suggested
/// name supplied by the picker.
///
/// The picker may hand back a filename (macOS) or `itemProvider.suggestedName`
/// (iOS). This strips a trailing file extension and trims whitespace; if the
/// result is empty or no suggestion was supplied it falls back to
/// ``defaultImportedImageName``. Pure and `nonisolated` so it can be unit-tested
/// without standing up a picker.
/// - Parameter suggestedName: The raw name the picker offered, if any. May
///   include a file extension (e.g. `"sunset.png"`).
/// - Returns: A trimmed, extension-free name, or the default fallback.
nonisolated func effectiveImportedImageName(from suggestedName: String?) -> String {
    guard let suggestedName else { return defaultImportedImageName }
    let base = (suggestedName as NSString).deletingPathExtension
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultImportedImageName : trimmed
}

// On macOS the gallery uses SwiftUI's `.fileImporter` directly (see
// `GalleryListView`), so no picker view is needed there.
#if canImport(UIKit)
import UIKit
import PhotosUI

/// iOS file picker for selecting images
struct ImagePickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    /// Called with the selected image bytes and, when available, the picker's
    /// `itemProvider.suggestedName`.
    var onImageSelected: (Data, String?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected, dismiss: dismiss)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (Data, String?) -> Void
        let dismiss: DismissAction

        init(onImageSelected: @escaping (Data, String?) -> Void, dismiss: DismissAction) {
            self.onImageSelected = onImageSelected
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { dismiss() }

            guard let result = results.first else { return }

            let itemProvider = result.itemProvider
            let suggestedName = itemProvider.suggestedName
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    guard let uiImage = image as? UIImage, error == nil else { return }

                    if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                        DispatchQueue.main.async {
                            self.onImageSelected(jpegData, suggestedName)
                        }
                    }
                }
            }
        }
    }
}

#endif
