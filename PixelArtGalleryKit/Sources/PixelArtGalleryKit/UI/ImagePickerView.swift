import SwiftUI

#if canImport(AppKit)
import AppKit

/// macOS file picker for selecting images
struct ImagePickerView: NSViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onImageSelected: (Data) -> Void

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = NSViewController()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Select an image to import"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if panel.runModal() == .OK, let url = panel.urls.first {
                if let imageData = try? Data(contentsOf: url) {
                    onImageSelected(imageData)
                }
            }
            dismiss()
        }

        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}

#elseif canImport(UIKit)
import UIKit
import PhotosUI

/// iOS file picker for selecting images
struct ImagePickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onImageSelected: (Data) -> Void

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
        let onImageSelected: (Data) -> Void
        let dismiss: DismissAction

        init(onImageSelected: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onImageSelected = onImageSelected
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { dismiss() }

            guard let result = results.first else { return }

            let itemProvider = result.itemProvider
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    guard let uiImage = image as? UIImage, error == nil else { return }

                    if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                        DispatchQueue.main.async {
                            self.onImageSelected(jpegData)
                        }
                    }
                }
            }
        }
    }
}

#endif
