// StorageFolder.swift

import Foundation

/// Resolves the Application Support folder name for the current build
/// identity (#0045).
///
/// Debug builds carry the beta bundle ID (`co.sstools.PixelArtGallery.beta`)
/// and must keep their SwiftData store and image files separate from the
/// released app's data. Release builds — and any context without a `.beta`
/// bundle ID, such as test runners — keep using the original
/// `PixelArtGallery` folder so existing user data is never orphaned.
public enum StorageFolder {
    /// Folder name for a given bundle identifier: a bundle ID with the
    /// `.beta` suffix gets its own folder; anything else (including `nil`)
    /// uses the production folder.
    public nonisolated static func name(forBundleIdentifier bundleIdentifier: String?) -> String {
        if let bundleIdentifier, bundleIdentifier.hasSuffix(".beta") {
            return "PixelArtGallery-Beta"
        }
        return "PixelArtGallery"
    }

    /// Folder name for the current process's main bundle.
    public nonisolated static var current: String {
        name(forBundleIdentifier: Bundle.main.bundleIdentifier)
    }
}
