import Foundation

/// Everything a continuous FT send loop (``FTSendController``) needs to paint
/// repeatedly, independent of whether the source is a persisted `Variant`
/// (`VariantDetailView`) or a transient `FittedPreview` (the popover flow,
/// #0067).
///
/// `nonisolated`/`Sendable` because `Package.swift` default-isolates the main
/// target to `@MainActor` and the payload crosses into the controller's
/// off-main send task — the same reasoning as `AspectFit`/`FittedPreview`
/// (#0057/#0060/#0066).
nonisolated struct FTSendPayload: Sendable {
    let host: String
    let port: Int
    let width: Int
    let height: Int
    let pixelGridData: Data
    let scaleFactor: Double
}
