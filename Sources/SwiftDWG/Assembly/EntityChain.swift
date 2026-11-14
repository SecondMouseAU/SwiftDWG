/// Finds the entities of a block in a file before R2004, where they are a chain.
///
/// The block record names the first and the last entity, and each entity names the one before and
/// the one after. What an entity's links are, and which block an entity is in, come in as
/// closures, so that the recovery is a pure function that a test runs over a made-up chain.
enum EntityChain {
    /// The neighbours an entity names.
    ///
    /// A 0 stands for the handle next to the entity's own: an entity written without links is
    /// followed by the handle after it and preceded by the one before it.
    typealias Links = (previous: UInt64, next: UInt64)

    /// The most entities one walk follows, which no chain of a real file comes near.
    static let walkLimit = 1 << 24

    /// The handles of the entities of a block, in order.
    ///
    /// The chain is walked forward from `first`. If that does not reach `last`, it is walked back
    /// from `last`, and the two walks together give every entity but the one the chain is broken
    /// at. If they do not meet, the entities of the file that are in the block and were not found
    /// are put between them, in handle order. An entity that cannot be read stays in the list, so
    /// that it is counted.
    ///
    /// - Parameters:
    ///   - first: The first entity of the block, or 0 when the record names none.
    ///   - last: The last entity of the block, or 0 when the record names none.
    ///   - record: The handle of the block's record, which an entity names as its owner.
    ///   - excluding: Handles that are never entities of the block, its BLOCK and ENDBLK.
    ///   - links: The links of an entity, or `nil` when it cannot be read or is not in the file.
    ///   - owner: The block record an entity is in, or `nil` when it cannot be read or is not an
    ///     entity.
    ///   - candidates: Every handle of the file, ascending. Called only if the walks do not meet.
    ///   - limit: The most entities a walk follows.
    /// - Returns: The block's entity handles, with the unreadable ones among them.
    static func entities(
        first: UInt64, last: UInt64, record: UInt64, excluding: Set<UInt64>,
        links: (UInt64) -> Links?, owner: (UInt64) -> UInt64?, candidates: () -> [UInt64],
        limit: Int = walkLimit
    ) -> [UInt64] {
        guard first != 0 else { return [] }
        let forward = walkForward(
            from: first, to: last, excluding: excluding, links: links, limit: limit)
        // Without a last entity there is nothing to walk back from or to check the walk against.
        if last == 0 || forward.last == last { return forward }

        let known = Set(forward)
        var back: [UInt64] = []
        var seen = Set<UInt64>()
        var met = false
        var handle = last
        while handle != 0, !excluding.contains(handle) {
            if known.contains(handle) {
                met = handle == forward.last
                break
            }
            guard seen.insert(handle).inserted, back.count < limit else { break }
            back.append(handle)
            guard let neighbours = links(handle) else { break }
            handle = neighbours.previous != 0 ? neighbours.previous : handle &- 1
        }
        if met { return forward + back.reversed() }

        var found = known.union(back)
        var between: [UInt64] = []
        for candidate in candidates() where !found.contains(candidate) {
            guard !excluding.contains(candidate), let block = owner(candidate), block == record
            else { continue }
            found.insert(candidate)
            between.append(candidate)
        }
        return forward + between + back.reversed()
    }

    /// The entities from `first` along the `next` links, up to `last` when the chain reaches it.
    private static func walkForward(
        from first: UInt64, to last: UInt64, excluding: Set<UInt64>, links: (UInt64) -> Links?,
        limit: Int
    ) -> [UInt64] {
        var out: [UInt64] = []
        var seen = Set<UInt64>()
        var handle = first
        while handle != 0, !excluding.contains(handle), seen.insert(handle).inserted,
            out.count < limit
        {
            out.append(handle)
            if handle == last { break }
            guard let neighbours = links(handle) else { break }
            handle = neighbours.next != 0 ? neighbours.next : handle &+ 1
        }
        return out
    }
}
