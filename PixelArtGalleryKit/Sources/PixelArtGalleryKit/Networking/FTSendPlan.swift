import Foundation

/// Pure assembly of the FT send parameters for a transient ``FittedPreview``
/// (#0067): the payload to paint plus the paint offset/layer.
///
/// **Offset convention.** `FittedPreview.offsetX`/`offsetY` are the
/// *centering* placement of the fit image within the display's own
/// `displayWidth x displayHeight` canvas (``AspectFit``). The display's
/// stored `offsetX`/`offsetY` (#0056) is a separate, independently
/// configured base offset for that display. Per #0066's `FittedPreview`
/// field justification ("the centering placement the send adds to the
/// display's stored offsetX/offsetY"), the two are additive, not
/// alternatives: the final paint offset is the preview's centering offset
/// **plus** the display's stored offset. For the common case of a display
/// with no configured base offset (`offsetX == offsetY == 0`, the default),
/// this reduces to exactly the centering offset, so the fitted image still
/// lands centered.
///
/// `nonisolated` (and all its inputs/outputs are value types) because
/// `Package.swift` default-isolates the main target to `@MainActor` — a pure
/// helper consumed from nonisolated tests must opt out explicitly (the
/// `AspectFit`/`FittedPreview` pattern, #0057/#0060/#0066).
nonisolated enum FTSendPlan {
    /// Assemble the send payload + paint offset for `preview` on the display
    /// reachable at `host:port`, whose stored default layer/offset are
    /// `layer`/`displayOffsetX`/`displayOffsetY`.
    /// - Parameters:
    ///   - preview: The transient fitted preview to send (fit dims + grid +
    ///     centering offset).
    ///   - host: The destination display's host.
    ///   - port: The destination display's port.
    ///   - layer: The display's stored default paint layer (unclamped —
    ///     clamped here into ``FlaschenTaschenDisplay/layerRange``).
    ///   - displayOffsetX: The display's stored default horizontal offset
    ///     (unclamped — clamped here to non-negative).
    ///   - displayOffsetY: The display's stored default vertical offset
    ///     (unclamped — clamped here to non-negative).
    /// - Returns: The payload to paint (the preview's fit dims/grid verbatim,
    ///   `scaleFactor` 1.0 — a `FittedPreview` is always native scale) and
    ///   the `(x, y, z)` paint offset.
    nonisolated static func make(
        preview: FittedPreview,
        host: String,
        port: Int,
        layer: Int,
        displayOffsetX: Int,
        displayOffsetY: Int
    ) -> (payload: FTSendPayload, offset: (x: Int, y: Int, z: Int)) {
        let payload = FTSendPayload(
            host: host,
            port: port,
            width: preview.width,
            height: preview.height,
            pixelGridData: preview.pixelGridData,
            scaleFactor: 1.0
        )

        let x = FlaschenTaschenDisplay.clampedOffset(preview.offsetX)
            + FlaschenTaschenDisplay.clampedOffset(displayOffsetX)
        let y = FlaschenTaschenDisplay.clampedOffset(preview.offsetY)
            + FlaschenTaschenDisplay.clampedOffset(displayOffsetY)
        let z = FlaschenTaschenDisplay.clampedLayer(layer)

        return (payload: payload, offset: (x: x, y: y, z: z))
    }
}
