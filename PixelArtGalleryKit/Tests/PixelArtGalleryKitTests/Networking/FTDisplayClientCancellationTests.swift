import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Cancellation contract for `FTDisplayClient.send` (#0050): a send that is
/// cancelled while in flight must report ``FTDisplayError/cancelled`` — never a
/// spurious network failure and never a silent success — so the UI can show a
/// neutral "cancelled" state and re-enable the Send button.
@Suite struct FTDisplayClientCancellationTests {
    /// Sends to an unresolvable `.invalid` host (RFC 6761 — it can never become
    /// ready), so the connection stays pending until we cancel it. A long
    /// connection timeout guarantees only the cancel — not the timeout — can end
    /// the wait, making the assertion deterministic.
    @Test func cancellingInFlightSendReportsCancelled() async {
        let client = FTDisplayClient(connectionTimeout: .seconds(30))
        let pixelData = PixelGrid(width: 2, height: 2).toRGBA8888()

        let task = Task { () -> FTDisplayError? in
            do {
                try await client.send(
                    width: 2,
                    height: 2,
                    pixelGridData: pixelData,
                    scaleFactor: 1,
                    to: "pixelartgallery-send.invalid",
                    port: 1337
                )
                return nil
            } catch let error as FTDisplayError {
                return error
            } catch {
                return nil
            }
        }

        // Let the send reach its connection wait, then stop it as the Stop button would.
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()

        let result = await task.value
        #expect(result == .cancelled,
                "A cancelled in-flight send must surface .cancelled, not \(String(describing: result))")
    }

    @Test func cancelledIsDistinctFromNetworkFailures() {
        // The UI branches on this case to choose a neutral banner over an error
        // banner, so it must not collide with the failure cases.
        #expect(FTDisplayError.cancelled != FTDisplayError.timedOut)
        #expect(FTDisplayError.cancelled != FTDisplayError.sendFailed("x"))
        #expect(FTDisplayError.cancelled != FTDisplayError.connectionFailed("x"))
        #expect(FTDisplayError.cancelled == FTDisplayError.cancelled)
    }
}
