import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// iOS document picker that exports an already-written file (at `fileURL`) into the Files app.
///
/// Presents `UIDocumentPickerViewController` in export mode over the temp file the
/// `VariantExporter` produced. Reports success (the chosen destination URL) or cancellation
/// back to `ExportPickerView` via the completion closures so the existing success/error UI
/// can surface the result.
struct DocumentExporterView: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // `asCopy: true` exports a copy of the temp file, leaving the original for cleanup.
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (URL) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onComplete(url)
            } else {
                onCancel()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#endif
