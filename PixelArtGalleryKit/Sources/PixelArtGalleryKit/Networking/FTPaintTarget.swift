import Foundation

/// A snapshot of exactly what has been painted on an FT display: the
/// endpoint/geometry used to reach it, plus the layer and x/y offset the last
/// frame was painted at.
///
/// Both the continuous-send loop and its stop-clear (#0053) key off this so
/// they always erase precisely what is currently on the display — even after
/// a mid-send switch to a different layer or offset (#0057). The endpoint and
/// geometry never change once a send starts; only the layer/offset can, so
/// `requiresClear`/`painted` only ever compare/update those three fields.
nonisolated public struct FTPaintTarget: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let width: Int
    public let height: Int
    public let scaleFactor: Double
    public let layer: Int
    public let offsetX: Int
    public let offsetY: Int

    public init(
        host: String,
        port: Int,
        width: Int,
        height: Int,
        scaleFactor: Double,
        layer: Int,
        offsetX: Int,
        offsetY: Int
    ) {
        self.host = host
        self.port = port
        self.width = width
        self.height = height
        self.scaleFactor = scaleFactor
        self.layer = layer
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// Whether painting at `layer`/`offsetX`/`offsetY` next, instead of this
    /// target's values, would strand pixels on the display that must be
    /// cleared first — true whenever the layer or either offset actually
    /// changes from what was last painted here.
    public func requiresClear(beforePaintingLayer layer: Int, offsetX: Int, offsetY: Int) -> Bool {
        self.layer != layer || self.offsetX != offsetX || self.offsetY != offsetY
    }

    /// A copy of this target reflecting what was just painted: the layer and
    /// offset updated, endpoint and geometry carried over unchanged.
    public func painted(layer: Int, offsetX: Int, offsetY: Int) -> FTPaintTarget {
        FTPaintTarget(
            host: host, port: port, width: width, height: height, scaleFactor: scaleFactor,
            layer: layer, offsetX: offsetX, offsetY: offsetY
        )
    }
}
