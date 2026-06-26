import Foundation

/// Pure planning logic for merging mDNS-discovered displays into the persisted
/// registry, de-duplicated by host+port.
///
/// Holding the decision-making apart from the SwiftData mutations keeps the
/// de-dupe rules unit-testable: ``build(existing:discovered:)`` is a pure
/// function over the inputs that decides which existing records to update and
/// which discoveries to insert, without touching a `ModelContext`. The
/// coordinator applies the resulting plan (mutating models, inserting, saving).
///
/// De-dupe key is the normalized endpoint (`host:port`, host lowercased) so
/// `FT.local:1337` and `ft.local:1337` collapse to one record. A discovery that
/// matches an existing record updates it; an unmatched discovery is inserted.
/// Multiple discoveries that share an endpoint within one scan collapse to a
/// single action (last one wins) so a flapping browser can't create duplicates.
struct DisplayMergePlan {
    /// An existing record to refresh from a discovered value.
    struct Update {
        let target: FlaschenTaschenDisplay
        let discovered: DiscoveredFTDisplay
    }

    /// Discoveries with no matching existing record, to be inserted.
    let insertions: [DiscoveredFTDisplay]

    /// Existing records matched by a discovery, to be updated in place.
    let updates: [Update]

    /// Normalize an endpoint into a stable de-dupe key.
    static func key(host: String, port: Int) -> String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    }

    /// Decide, purely, how a set of discovered displays should be merged into the
    /// existing registry.
    ///
    /// - Parameters:
    ///   - existing: The current persisted displays.
    ///   - discovered: Displays found in this scan.
    /// - Returns: A plan of insertions (new endpoints) and updates (matched
    ///   endpoints). The plan never references the same existing record twice.
    static func build(
        existing: [FlaschenTaschenDisplay],
        discovered: [DiscoveredFTDisplay]
    ) -> DisplayMergePlan {
        // Index existing records by endpoint key. If duplicates already exist in
        // the store, the first one wins as the merge target.
        var existingByKey: [String: FlaschenTaschenDisplay] = [:]
        for record in existing {
            let k = key(host: record.host, port: record.port)
            if existingByKey[k] == nil { existingByKey[k] = record }
        }

        // Collapse discoveries that share an endpoint (last seen wins).
        var discoveredByKey: [String: DiscoveredFTDisplay] = [:]
        var order: [String] = []
        for value in discovered {
            let k = key(host: value.host, port: value.port)
            if discoveredByKey[k] == nil { order.append(k) }
            discoveredByKey[k] = value
        }

        var insertions: [DiscoveredFTDisplay] = []
        var updates: [Update] = []
        for k in order {
            guard let value = discoveredByKey[k] else { continue }
            if let target = existingByKey[k] {
                updates.append(Update(target: target, discovered: value))
            } else {
                insertions.append(value)
            }
        }

        return DisplayMergePlan(insertions: insertions, updates: updates)
    }
}
