import Foundation
import Network

/// Errors raised while browsing for Flaschen Taschen displays.
///
/// Discovery is designed to fail gracefully: callers should treat any error as
/// "no displays found" and fall back to manual entry (issue 0010).
enum FTDiscoveryError: LocalizedError, Equatable {
    /// The `NWBrowser` reported a failed state (e.g. the service type is
    /// malformed or the network is unavailable).
    case browserFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserFailed(let reason):
            return "Display discovery failed: \(reason)"
        }
    }
}

/// On-demand mDNS/Bonjour discovery for Flaschen Taschen displays.
///
/// Browses the local network for the `_flaschen-taschen._udp` service type using
/// `Network.framework`'s `NWBrowser`, resolves each found endpoint to host/port,
/// reads any advertised TXT metadata (display width/height), and yields plain
/// ``DiscoveredFTDisplay`` values via an `AsyncStream`.
///
/// `NWBrowser` delivers Bonjour results as unresolved `.service` endpoints, not
/// resolved `.hostPort` values, so each `.service` result is resolved with a
/// short-lived UDP `NWConnection` to the service endpoint (mirroring
/// ``FTDisplayClient``'s connect-with-timeout idiom): connecting makes
/// Network.framework perform the SRV/A resolution internally, and reading
/// `currentPath?.remoteEndpoint` once the connection is `.ready` yields the
/// resolved host/port (issue 0060).
///
/// The service is an `actor`, so it runs off the main actor (the package defaults
/// to `@MainActor` isolation, but `actor` declarations form their own isolation
/// domain) — satisfying the PRD rule that mDNS operations live in an
/// `actor`/`nonisolated` context. It is decoupled from SwiftData: persisting and
/// merging results into the registry is issue 0011.
///
/// Typical use:
/// ```swift
/// let service = FTDiscoveryService()
/// for await display in await service.scan(duration: .seconds(5)) {
///     // handle each discovered display
/// }
/// ```
actor FTDiscoveryService {
    /// The default Bonjour service type advertised by Flaschen Taschen displays.
    static let defaultServiceType = "_flaschen-taschen._udp"

    /// How long to wait for a single `.service` endpoint to resolve to
    /// host/port before giving up on it. Shorter than the default scan
    /// `duration` so one silent host can't pin a connection past the scan.
    private static let resolveTimeout: Duration = .seconds(3)

    private let serviceType: String
    private var browser: NWBrowser?
    private var resolverPool: FTResolverPool?

    /// - Parameter serviceType: Bonjour service type to browse. Defaults to
    ///   ``defaultServiceType``; injectable for testing.
    init(serviceType: String = FTDiscoveryService.defaultServiceType) {
        self.serviceType = serviceType
    }

    /// Start an on-demand scan and stream discovered displays as they resolve.
    ///
    /// Returns an `AsyncStream` that yields a ``DiscoveredFTDisplay`` for each
    /// resolved endpoint, then finishes automatically after `duration` elapses
    /// (or when ``stop()`` is called). A failed browser also finishes the stream
    /// rather than throwing, so callers degrade gracefully to manual entry.
    ///
    /// Already-resolved `.hostPort` results yield immediately; unresolved
    /// `.service` results are resolved asynchronously (see the type doc) and
    /// yielded as each one completes, within the scan window.
    ///
    /// - Parameter duration: How long to browse before stopping the scan.
    /// - Returns: A stream of discovered displays.
    func scan(duration: Duration = .seconds(5)) -> AsyncStream<DiscoveredFTDisplay> {
        stop()

        AppLog.ftDiscovery.info("Browsing \(self.serviceType, privacy: .public) for \(duration.components.seconds)s")

        let pool = FTResolverPool()
        self.resolverPool = pool

        return AsyncStream { continuation in
            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
                type: serviceType,
                domain: nil
            )
            let newBrowser = NWBrowser(for: descriptor, using: parameters)
            self.browser = newBrowser

            newBrowser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLog.ftDiscovery.debug("Browser ready for \(self.serviceType, privacy: .public)")
                case .failed(let error):
                    AppLog.ftDiscovery.error("Browser failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                case .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }

            newBrowser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    let name = Self.serviceName(for: result.endpoint)
                    let txt = Self.txtRecord(from: result.metadata)

                    switch result.endpoint {
                    case .hostPort:
                        // Already resolved; yield immediately.
                        if let discovered = Self.display(
                            fromResolvedEndpoint: result.endpoint,
                            serviceName: name,
                            txtRecord: txt
                        ) {
                            AppLog.ftDiscovery.debug("Found \(discovered.serviceName, privacy: .public) at \(discovered.host, privacy: .public):\(discovered.port)")
                            continuation.yield(discovered)
                        }
                    case .service:
                        // A bare Bonjour service reference; resolve it before
                        // yielding. Dedup by service name so a result seen
                        // again (e.g. on another interface) doesn't open a
                        // second connection.
                        guard pool.beginResolving(name: name) else { continue }
                        Self.resolve(result: result, serviceName: name, txtRecord: txt, pool: pool, into: continuation)
                    default:
                        break
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                Task { await self.stop() }
            }

            newBrowser.start(queue: .global(qos: .userInitiated))

            // Bound the scan so the stream finishes on its own.
            Task {
                try? await Task.sleep(for: duration)
                continuation.finish()
            }
        }
    }

    /// Stop any in-flight scan and release the browser, cancelling every
    /// still-resolving connection so none leak past this scan.
    func stop() {
        browser?.cancel()
        browser = nil
        resolverPool?.cancelAll()
        resolverPool = nil
    }

    /// Resolve a single unresolved `.service` browse result to host/port via a
    /// short-lived UDP `NWConnection`, then yield the result to `continuation`.
    ///
    /// Mirrors ``FTDisplayClient``'s connect-with-timeout idiom: connecting to a
    /// `.service` endpoint makes Network.framework perform the Bonjour SRV/A
    /// resolution internally, and `currentPath?.remoteEndpoint` on `.ready` is
    /// the resolved `.hostPort`. `pool.complete(_:)` is a once-only latch, so
    /// `.ready`/`.failed`/`.cancelled` and the timeout task can each attempt to
    /// finish the connection without double-cancelling or double-yielding.
    ///
    /// Runs entirely off the actor (called from the browser's callback queue);
    /// `AsyncStream.Continuation` is `Sendable` and safe to yield from any queue.
    private static func resolve(
        result: NWBrowser.Result,
        serviceName: String,
        txtRecord: [String: String],
        pool: FTResolverPool,
        into continuation: AsyncStream<DiscoveredFTDisplay>.Continuation
    ) {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: result.endpoint, using: parameters)
        pool.register(connection)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard pool.complete(connection) else { return }
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   let discovered = Self.display(
                       fromResolvedEndpoint: remoteEndpoint,
                       serviceName: serviceName,
                       txtRecord: txtRecord
                   ) {
                    AppLog.ftDiscovery.debug("Found \(discovered.serviceName, privacy: .public) at \(discovered.host, privacy: .public):\(discovered.port)")
                    continuation.yield(discovered)
                }
            case .failed, .cancelled:
                pool.complete(connection)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))

        // Bound the resolve so a silent host can't hold a connection open
        // past the scan window.
        Task {
            try? await Task.sleep(for: resolveTimeout)
            pool.complete(connection)
        }
    }

    /// Build a ``DiscoveredFTDisplay`` from a resolved endpoint, folding in the
    /// advertised service name and TXT metadata. Returns `nil` if `endpoint`
    /// isn't a resolved `.hostPort` (e.g. a bare Bonjour service reference that
    /// hasn't been resolved yet).
    ///
    /// This is the pure extraction step shared by the live `.ready` handler
    /// (both the already-resolved `.hostPort` fast path and ``resolve``'s
    /// `currentPath?.remoteEndpoint` result) and unit tests — `internal` rather
    /// than `private` so tests can exercise it directly without a real network.
    static func display(
        fromResolvedEndpoint endpoint: NWEndpoint,
        serviceName: String,
        txtRecord: [String: String]
    ) -> DiscoveredFTDisplay? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        return DiscoveredFTDisplay.make(
            host: hostString(host),
            port: Int(port.rawValue),
            serviceName: serviceName,
            txtRecord: txtRecord
        )
    }

    /// Best-effort friendly name from an endpoint.
    private static func serviceName(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        case .hostPort(let host, _):
            return hostString(host)
        default:
            return endpoint.debugDescription
        }
    }

    /// Render an `NWEndpoint.Host` as a plain string without interface suffixes.
    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return "\(host)"
        }
    }

    /// Extract TXT-record key/value pairs from browse metadata, if present.
    private static func txtRecord(from metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case .bonjour(let record) = metadata else { return [:] }
        var values: [String: String] = [:]
        for (key, entry) in record.dictionary {
            values[key] = entry
        }
        return values
    }
}

/// Tracks in-flight resolution connections for a single scan so they can all
/// be torn down together on `stop()`/stream termination, and dedups repeat
/// browse results by Bonjour service name so each service is only resolved
/// once per scan.
///
/// Mirrors `FTDisplayClient`'s `ResumeOnce` latch pattern: `NSLock`-guarded
/// state accessed from arbitrary dispatch queues (the browser's callback queue
/// and each connection's own state-update queue), never from the actor.
private nonisolated final class FTResolverPool: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var seenServiceNames: Set<String> = []
    private var completedIDs: Set<ObjectIdentifier> = []

    /// - Returns: `true` the first time `name` is seen for this scan (the
    ///   caller should start resolving it); `false` if a resolve for it is
    ///   already in flight or already completed.
    func beginResolving(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if seenServiceNames.contains(name) { return false }
        seenServiceNames.insert(name)
        return true
    }

    /// Track a connection so `cancelAll()` can cancel it if the scan ends
    /// before it resolves.
    func register(_ connection: NWConnection) {
        lock.lock()
        defer { lock.unlock() }
        connections[ObjectIdentifier(connection)] = connection
    }

    /// Complete a connection's resolution exactly once: cancel it and stop
    /// tracking it. Safe to call redundantly — `.ready`, `.failed`,
    /// `.cancelled`, and the per-resolve timeout task can each call this for
    /// the same connection; only the first call actually cancels/untracks it.
    ///
    /// - Returns: `true` if this call was the one that completed it (so the
    ///   caller may act on the result), `false` if it was already completed.
    @discardableResult
    func complete(_ connection: NWConnection) -> Bool {
        lock.lock()
        let id = ObjectIdentifier(connection)
        guard !completedIDs.contains(id) else {
            lock.unlock()
            return false
        }
        completedIDs.insert(id)
        connections.removeValue(forKey: id)
        lock.unlock()
        connection.cancel()
        return true
    }

    /// Cancel every still-tracked connection (scan stopped/stream terminated).
    func cancelAll() {
        lock.lock()
        let remaining = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        for connection in remaining {
            connection.cancel()
        }
    }
}
