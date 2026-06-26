import Foundation
import Network
import os.log

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
    private static let logger = Logger(
        subsystem: "com.pixelartgallery.networking",
        category: "FTSend"
    )

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
            throw FTDisplayError.invalidPort(port)
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw FTDisplayError.invalidHost(host)
        }

        onProgress?(.encoding)
        let packet = try Self.makePacket(
            width: width,
            height: height,
            pixelGridData: pixelGridData,
            scaleFactor: scaleFactor,
            offset: offset
        )
        Self.logger.debug("Encoded FT packet: \(packet.count) bytes for \(width)x\(height) -> \(trimmedHost, privacy: .public):\(port)")

        let nwHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: nwHost, port: nwPort, using: .udp)

        onProgress?(.connecting)
        try await withConnectionReady(connection)

        onProgress?(.sending)
        try await sendPacket(packet, over: connection)

        connection.cancel()
        onProgress?(.completed)
        Self.logger.info("Sent FT image (\(packet.count) bytes) to \(trimmedHost, privacy: .public):\(port)")
    }

    // MARK: - Packet construction

    /// FT footer command-byte prefix. The footer is `0x00` followed by the ASCII
    /// offsets, allowing the receiver to distinguish it from PPM pixel data.
    private static let footerStart: UInt8 = 0x00

    /// Build the full FT datagram: a P6 PPM payload plus an offset footer.
    ///
    /// The PPM payload is produced by ``VariantExporter`` so the encoding matches
    /// the file-export path exactly. The footer is `<0x00><x>\n<y>\n<z>\n`, which
    /// is the form the FT server parses for paint offsets; an all-zero offset is a
    /// full-frame paint at the origin and is always safe.
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

        var packet = ppm
        packet.append(footerStart)
        packet.append(Data("\(offset.x)\n\(offset.y)\n\(offset.z)\n".utf8))
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
