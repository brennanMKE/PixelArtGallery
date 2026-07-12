import Foundation
import Observation

/// Drives a continuous FT send loop: repeatedly paints a payload to a display
/// every ``sendRefreshInterval``, reading the current layer/offset fresh each
/// frame via a caller-supplied closure so those can stay live-editable during
/// a send (#0057).
///
/// Extracted from `VariantDetailView` (#0067) so the send popover
/// (`GallerySendPopoverView`) can drive the identical loop for a transient
/// `FittedPreview` instead of only a persisted `Variant` — the loop itself
/// (mid-send clear-on-change, cancellation, the #0053 stop-clear) is not
/// duplicated between the two call sites.
@Observable
final class FTSendController {
    /// Whether a continuous send is currently in flight.
    private(set) var isSending = false

    /// The in-flight send, retained so ``stop()`` can cancel it.
    private var sendTask: Task<Void, Never>?

    /// The endpoint/geometry/layer/offset last actually *painted*. Layer and
    /// x/y are read live each frame, so this is updated after every
    /// successful paint — not captured once at start — which lets ``stop()``
    /// clear exactly what is on the display right now, even after a mid-send
    /// switch to a different layer or offset (#0057).
    private var activeSend: FTPaintTarget?

    /// How often the loop re-pushes the frame. FT servers drop a layer after
    /// their layer-timeout (commonly ~15s) if it isn't refreshed, so frames
    /// are resent well inside that window to keep the image up.
    static let sendRefreshInterval: Duration = .seconds(2)

    init() {}

    /// Start the continuous send loop. A no-op if a send is already running.
    /// - Parameters:
    ///   - payload: The endpoint + pixel data to paint. Captured once at
    ///     start — only `frameOffset`'s layer/x/y are read live each frame.
    ///   - frameOffset: Invoked once per frame for the current
    ///     `(layer, offsetX, offsetY)`; callers whose offset never changes
    ///     during a send (e.g. the popover) can return a constant tuple,
    ///     while `VariantDetailView` reads its live `@State` steppers here.
    ///   - onError: Called on the main actor when the loop ends because of a
    ///     genuine send failure, with a user-facing message.
    ///   - onStopped: Called on the main actor when the loop ends normally
    ///     (a user stop or cancellation), with a status message.
    func start(
        payload: FTSendPayload,
        frameOffset: @escaping @MainActor () -> (layer: Int, offsetX: Int, offsetY: Int),
        onError: @escaping @MainActor (String) -> Void,
        onStopped: @escaping @MainActor (String) -> Void
    ) {
        guard !isSending else { return }
        isSending = true

        AppLog.ftDiscovery.info("Starting continuous send to \(payload.host, privacy: .public):\(payload.port)")

        sendTask = Task {
            defer {
                isSending = false
                sendTask = nil
                // Clear the last-painted target on any loop end (including a
                // network error that wasn't a user stop) so a later stop()
                // doesn't fire a spurious clear (#0053).
                activeSend = nil
            }
            let client = FTDisplayClient()
            var frameCount = 0
            // What was last actually painted (nil until the first frame
            // succeeds), so a mid-send layer/offset change can be detected
            // and the old target cleared before painting the new one (#0057).
            var painted: FTPaintTarget?
            do {
                // Keep pushing the frame until the caller cancels (Stop).
                while !Task.isCancelled {
                    // Read + clamp the *current* layer/x/y each iteration —
                    // this is what makes them live-editable during a send.
                    let rawOffset = frameOffset()
                    let layer = FlaschenTaschenDisplay.clampedLayer(rawOffset.layer)
                    let offsetX = FlaschenTaschenDisplay.clampedOffset(rawOffset.offsetX)
                    let offsetY = FlaschenTaschenDisplay.clampedOffset(rawOffset.offsetY)

                    if let previous = painted,
                       previous.requiresClear(beforePaintingLayer: layer, offsetX: offsetX, offsetY: offsetY) {
                        // The layer/offset changed since the last frame:
                        // erase the old target first so nothing is stranded
                        // on a layer/region we're about to stop refreshing.
                        await client.sendClearFrame(to: previous)
                    }

                    try await client.send(
                        width: payload.width,
                        height: payload.height,
                        pixelGridData: payload.pixelGridData,
                        scaleFactor: payload.scaleFactor,
                        to: payload.host,
                        port: payload.port,
                        offset: (x: offsetX, y: offsetY, z: layer)
                    )
                    frameCount += 1

                    let target = FTPaintTarget(
                        host: payload.host, port: payload.port, width: payload.width, height: payload.height,
                        scaleFactor: payload.scaleFactor, layer: layer, offsetX: offsetX, offsetY: offsetY
                    )
                    painted = target
                    activeSend = target

                    // Sleeping is a cancellation point, so Stop ends the loop promptly.
                    try await Task.sleep(for: Self.sendRefreshInterval)
                }
            } catch let error as FTDisplayError where error == .cancelled {
                // User tapped Stop mid-packet — normal exit, fall through below.
            } catch is CancellationError {
                // User tapped Stop during the inter-frame sleep — normal exit.
            } catch {
                let message = (error as? FTDisplayError)?.errorDescription ?? error.localizedDescription
                AppLog.ftDiscovery.error("Continuous send failed after \(frameCount) frame(s): \(error.localizedDescription, privacy: .public)")
                onError(message)
                return
            }
            AppLog.ftDiscovery.info("Stopped continuous send to \(payload.host, privacy: .public):\(payload.port) after \(frameCount) frame(s)")
            onStopped("Stopped sending after \(frameCount) frame(s)")
        }
    }

    /// Stop the continuous send and clear the painted layer.
    ///
    /// Cancels the refresh loop, then sends a final all-black frame to the
    /// exact endpoint/layer/offset that was last *painted* — which, since
    /// layer/x/y are live-editable mid-send (#0057), may differ from what the
    /// send started with. FlaschenTaschen treats black on any layer above the
    /// background as transparent, so this erases the overlay immediately
    /// instead of waiting for the server's layer timeout (#0053). The clear
    /// runs in a detached task so it completes even as the caller's view is
    /// torn down (#0052) and isn't killed by the loop's cancellation.
    func stop() {
        // Capture before cancelling — the loop's `defer` also nils this out.
        let clearTarget = activeSend
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        activeSend = nil

        guard let target = clearTarget else { return }
        Task.detached {
            let client = FTDisplayClient()
            await client.sendClearFrame(to: target)
            AppLog.ftDiscovery.info("Cleared FT layer \(target.layer) on \(target.host, privacy: .public):\(target.port)")
        }
    }
}
