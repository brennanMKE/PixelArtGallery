import Foundation
import Network

/// Errors raised while sending a variant to a Flaschen Taschen display.
public enum FTDisplayError: LocalizedError, Equatable {
    /// The supplied host string could not be parsed into a network endpoint.
    case invalidHost(String)
    /// The supplied port is outside the valid 1...65535 range.
    case invalidPort(Int)
    /// The variant's pixel data could not be encoded into an FT packet.
    case encodingFailed(String)
    /// The UDP connection failed before/while sending (with the underlying reason).
    case connectionFailed(String)
    /// The send itself failed (with the underlying reason).
    case sendFailed(String)
    /// The connection did not become ready within the allotted time.
    case timedOut
    /// The send was cancelled (e.g. the user tapped Stop) before it completed.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Invalid display host: \(host)"
        case .invalidPort(let port):
            return "Invalid display port: \(port)"
        case .encodingFailed(let reason):
            return "Could not encode image for the display: \(reason)"
        case .connectionFailed(let reason):
            return "Could not connect to the display: \(reason)"
        case .sendFailed(let reason):
            return "Failed to send image to the display: \(reason)"
        case .timedOut:
            return "Timed out connecting to the display."
        case .cancelled:
            return "The send was cancelled."
        }
    }
}

/// Stages of an in-flight send, surfaced to callers for genuine progress reporting.
public enum FTSendProgress: Equatable, Sendable {
    /// Encoding the variant into an FT packet.
    case encoding
    /// Opening the UDP connection to the display.
    case connecting
    /// Writing the packet to the connection.
    case sending
    /// The packet was handed off to the network stack successfully.
    case completed
}

/// Sends pixel-art variants to Flaschen Taschen (FT) displays over the network.
///
/// FT's wire protocol is intentionally simple: a display receives a single PPM
/// ("P6") image in one UDP datagram on its service port. An optional trailing
/// footer carries an x/y/z paint offset; this client appends a footer with the
/// requested offset (defaulting to `0,0,0`, i.e. a full-frame paint at the origin).
///
/// This is implemented directly on top of `Network.framework`'s `NWConnection`
/// rather than depending on the external `ft-swift` package, so the build does
/// not rely on external package resolution. The PPM payload is produced by the
/// existing ``VariantExporter`` (the same tested `P6` path used for file export),
/// keeping a single source of truth for the encoding.
///
/// The client is an `actor`, so it forms its own isolation domain off the main
/// actor (the package defaults to `@MainActor` isolation) — satisfying the PRD
/// rule that network I/O stays off the main actor.
public actor FTDisplayClient {
    /// How long to wait for the UDP connection to become ready before giving up.
    private let connectionTimeout: Duration

    /// - Parameter connectionTimeout: Maximum time to wait for the connection to
    ///   become ready. Defaults to 5 seconds.
    public init(connectionTimeout: Duration = .seconds(5)) {
        self.connectionTimeout = connectionTimeout
    }

    // MARK: - Sending

    /// Send a variant's pixels to a display, reporting progress through `onProgress`.
    ///
    /// Reads the variant's plain value fields up front (it is a main-actor-bound
    /// SwiftData `@Model`) and delegates to the value-typed overload, which runs
    /// entirely off the main actor.
    ///
    /// - Parameters:
    ///   - variant: The variant whose pixel grid should be painted.
    ///   - host: The display's hostname or IP address.
    ///   - port: The display's UDP service port.
    ///   - offset: Paint offset `(x, y, z)` on the display. Defaults to the origin.
    ///   - onProgress: Optional progress callback invoked for each ``FTSendProgress`` stage.
    /// - Throws: ``FTDisplayError`` on any failure.
    public func send(
        width: Int,
        height: Int,
        pixelGridData: Data,
        scaleFactor: Double,
        to host: String,
        port: Int,
        offset: (x: Int, y: Int, z: Int) = (0, 0, 0),
        onProgress: (@Sendable (FTSendProgress) -> Void)? = nil
    ) async throws {
        guard port > 0, port <= 65_535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            AppLog.ftDiscovery.warning("Send rejected: invalid port \(port)")
            throw FTDisplayError.invalidPort(port)
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            AppLog.ftDiscovery.warning("Send rejected: empty host")
            throw FTDisplayError.invalidHost(host)
        }

        AppLog.ftDiscovery.info("Sending \(width)×\(height) variant to \(trimmedHost, privacy: .public):\(port)")

        try Self.throwIfCancelled()
        onProgress?(.encoding)
        let packet = try Self.makePacket(
            width: width,
            height: height,
            pixelGridData: pixelGridData,
            scaleFactor: scaleFactor,
            offset: offset
        )
        AppLog.ftDiscovery.debug("Encoded FT packet: \(packet.count) bytes for \(width)x\(height) -> \(trimmedHost, privacy: .public):\(port)")

        try Self.throwIfCancelled()
        let nwHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: nwHost, port: nwPort, using: .udp)

        // Tear the connection down if the surrounding task is cancelled while we
        // await connect/send. Cancelling the connection surfaces as a thrown
        // error from the awaits below; we translate that to `.cancelled` when the
        // task was in fact cancelled, so callers can tell a user stop apart from a
        // genuine network failure.
        do {
            try await withTaskCancellationHandler {
                onProgress?(.connecting)
                try await withConnectionReady(connection)

                try Self.throwIfCancelled()
                onProgress?(.sending)
                try await sendPacket(packet, over: connection)

                connection.cancel()
                onProgress?(.completed)
            } onCancel: {
                connection.cancel()
            }
        } catch {
            connection.cancel()
            if Task.isCancelled {
                AppLog.ftDiscovery.info("Send to \(trimmedHost, privacy: .public):\(port) cancelled")
                throw FTDisplayError.cancelled
            }
            throw error
        }

        AppLog.ftDiscovery.info("Sent FT image (\(packet.count) bytes) to \(trimmedHost, privacy: .public):\(port)")
    }

    /// Throw ``FTDisplayError/cancelled`` if the current task has been cancelled.
    /// Used at checkpoints so a stop request is honored promptly between stages.
    private static func throwIfCancelled() throws {
        if Task.isCancelled { throw FTDisplayError.cancelled }
    }

    // MARK: - Packet construction

    /// Build the full FT datagram: a P6 PPM payload carrying the paint offset and
    /// layer as a `#FT:` header comment.
    ///
    /// The PPM payload is produced by ``VariantExporter`` so the pixel encoding
    /// matches the file-export path exactly. The offset/layer is then injected as
    /// a PPM header comment `#FT: <x> <y> <z>` (placed between the dimensions line
    /// and the `255` maxval), which is the exact form the reference FT client
    /// emits and every FT server parses (`server/ppm-reader.cc`).
    ///
    /// This replaces an earlier trailing footer that prefixed the offsets with a
    /// `0x00` byte: the server parses trailing offsets with `strtol` after
    /// `isspace`-skipping, and a NUL is neither a digit nor whitespace, so the
    /// parser bailed on the first field and the layer silently fell back to 0
    /// (the background). See #0051.
    ///
    /// `nonisolated` so it can be unit-tested without entering the actor.
    nonisolated static func makePacket(
        width: Int,
        height: Int,
        pixelGridData: Data,
        scaleFactor: Double,
        offset: (x: Int, y: Int, z: Int) = (0, 0, 0)
    ) throws -> Data {
        let ppm: Data
        do {
            ppm = try VariantExporter().data(
                width: width,
                height: height,
                pixelGridData: pixelGridData,
                scaleFactor: scaleFactor,
                format: .ppm
            )
        } catch {
            throw FTDisplayError.encodingFailed(error.localizedDescription)
        }

        return insertingFTComment(into: ppm, offset: offset)
    }

    /// Insert `#FT: <x> <y> <z>\n` into a P6 PPM header, right after the
    /// `<width> <height>` line (i.e. just past the second newline) so the result
    /// is `P6\n<W> <H>\n#FT: <x> <y> <z>\n255\n<pixels>`. If the header does not
    /// have the expected two leading newlines it is returned unchanged.
    nonisolated private static func insertingFTComment(
        into ppm: Data,
        offset: (x: Int, y: Int, z: Int)
    ) -> Data {
        let newline: UInt8 = 0x0A
        // Count of bytes up to and including the second newline (end of the
        // `P6\n<W> <H>\n` prefix). enumerated() yields 0-based positions, so the
        // count is that index + 1 — independent of Data's slice base.
        var newlineCount = 0
        var prefixLength: Int?
        for (position, byte) in ppm.enumerated() where byte == newline {
            newlineCount += 1
            if newlineCount == 2 {
                prefixLength = position + 1
                break
            }
        }
        guard let prefixLength else { return ppm }

        let comment = Data("#FT: \(offset.x) \(offset.y) \(offset.z)\n".utf8)
        var packet = Data()
        packet.reserveCapacity(ppm.count + comment.count)
        packet.append(ppm.prefix(prefixLength))
        packet.append(comment)
        packet.append(ppm.dropFirst(prefixLength))
        return packet
    }

    // MARK: - Connection helpers

    /// Resume the connection and await its `.ready` state (or fail/time out).
    private func withConnectionReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = ResumeOnce()

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if state.tryResume() { continuation.resume() }
                case .failed(let error):
                    if state.tryResume() {
                        continuation.resume(throwing: FTDisplayError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    if state.tryResume() {
                        continuation.resume(throwing: FTDisplayError.connectionFailed("connection cancelled"))
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            // Bound the wait so a silent/unreachable host can't hang the send.
            let timeout = connectionTimeout
            Task {
                try? await Task.sleep(for: timeout)
                if state.tryResume() {
                    connection.cancel()
                    continuation.resume(throwing: FTDisplayError.timedOut)
                }
            }
        }
    }

    /// Send a single datagram over a ready connection.
    private func sendPacket(_ packet: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: FTDisplayError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

/// Tiny thread-safe latch ensuring a continuation is resumed exactly once across
/// the connection state handler and the timeout task.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var resumed = false

    nonisolated init() {}

    /// - Returns: `true` the first time it's called, `false` thereafter.
    nonisolated func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
