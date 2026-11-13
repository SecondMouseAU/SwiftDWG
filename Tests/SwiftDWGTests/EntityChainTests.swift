import Testing

@testable import SwiftDWG

/// A block of a file before R2004, made up of handles and links, so that the recovery of its
/// entities runs without a file.
struct MadeUpFile {
    static let record: UInt64 = 0x100
    static let blockEntity: UInt64 = 0x1F
    static let endBlockEntity: UInt64 = 0x40

    /// The entities of the block, in order, with gaps in the handles where other objects sit.
    static let chain: [UInt64] = [
        0x20, 0x21, 0x22, 0x25, 0x26, 0x27, 0x30, 0x31, 0x32, 0x33,
    ]

    var links: [UInt64: EntityChain.Links] = [:]
    var owners: [UInt64: UInt64] = [:]
    /// Every handle of the file.
    var handles: [UInt64] = []

    /// What a recovery returned, and whether it had to scan the file.
    struct Recovery {
        var entities: [UInt64]
        var scanned: Bool
    }

    /// The entities of `chain`, linked as AutoCAD writes them: a neighbour is left implied (0, 0)
    /// only when both are the handles next to the entity's own, and the first has no previous and
    /// the last no next.
    ///
    /// Beside them sit a BLOCK and an ENDBLK that name the block as their owner, two vertices
    /// that a polyline of the block owns, and two entities of another block.
    init(chain: [UInt64] = MadeUpFile.chain) {
        for (index, handle) in chain.enumerated() {
            let previous = index > 0 ? chain[index - 1] : 0
            let next = index + 1 < chain.count ? chain[index + 1] : 0
            let implied = previous == handle - 1 && next == handle + 1
            links[handle] =
                implied ? (previous: 0, next: 0) : (previous: previous, next: next)
            owners[handle] = Self.record
        }
        links[Self.blockEntity] = (previous: 0, next: 0)
        links[Self.endBlockEntity] = (previous: 0, next: 0)
        owners[Self.blockEntity] = Self.record
        owners[Self.endBlockEntity] = Self.record
        for vertex: UInt64 in [0x23, 0x24] {
            links[vertex] = (previous: 0, next: 0)
            owners[vertex] = 0x22
        }
        for other: UInt64 in [0x28, 0x29] {
            links[other] = (previous: 0, next: 0)
            owners[other] = 0x200
        }
        handles = links.keys.sorted()
    }

    /// Makes entities unreadable: they are in the file and have no links or owner to read.
    mutating func damage(_ damaged: [UInt64]) {
        for handle in damaged {
            links[handle] = nil
            owners[handle] = nil
        }
    }

    /// Takes entities out of the file altogether.
    mutating func remove(_ removed: [UInt64]) {
        damage(removed)
        handles.removeAll { removed.contains($0) }
    }

    func recover(
        first: UInt64, last: UInt64,
        excluding: Set<UInt64> = [MadeUpFile.blockEntity, MadeUpFile.endBlockEntity],
        limit: Int = EntityChain.walkLimit
    ) -> Recovery {
        var scanned = false
        let entities = EntityChain.entities(
            first: first, last: last, record: Self.record, excluding: excluding,
            links: { links[$0] }, owner: { owners[$0] },
            candidates: {
                scanned = true
                return handles
            }, limit: limit)
        return Recovery(entities: entities, scanned: scanned)
    }

    /// The recovery for the whole block, as its record names it.
    func recover() -> Recovery {
        recover(first: Self.chain[0], last: Self.chain[Self.chain.count - 1])
    }
}

@Suite("Entity chain")
struct EntityChainTests {
    static let chain = MadeUpFile.chain

    @Test("a chain with no break comes back as it is, without a scan of the file")
    func noBreak() {
        let result = MadeUpFile().recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("a break in the middle loses nothing: the walk back from the last entity meets the first")
    func breakInTheMiddle() {
        var file = MadeUpFile()
        file.damage([0x26])
        let result = file.recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("a break at the first entity loses nothing, and the entity stays in the list")
    func breakAtTheFirst() {
        var file = MadeUpFile()
        file.damage([0x20])
        let result = file.recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("a break at the last entity loses nothing, and the entity stays in the list")
    func breakAtTheLast() {
        var file = MadeUpFile()
        file.damage([0x33])
        let result = file.recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("a break at any one entity loses nothing", arguments: MadeUpFile.chain)
    func breakAtAnyEntity(_ handle: UInt64) {
        var file = MadeUpFile()
        file.damage([handle])
        let result = file.recover()
        #expect(result.entities == Self.chain, "\(handle)")
        #expect(!result.scanned, "\(handle)")
    }

    @Test("an entity that is not in the file at all stays in the list, so it is counted")
    func absentEntity() {
        var file = MadeUpFile()
        file.remove([0x26])
        let result = file.recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("two breaks leave the entities between them to the scan of the file")
    func twoBreaks() {
        var file = MadeUpFile()
        file.damage([0x22, 0x31])
        let result = file.recover()
        #expect(result.scanned)
        // The vertices, the other block's entities, the BLOCK and the ENDBLK are not picked up.
        #expect(result.entities == Self.chain)
    }

    @Test("two breaks next to each other lose nothing and list nothing twice")
    func adjacentBreaks() {
        var file = MadeUpFile()
        file.damage([0x26, 0x27])
        let result = file.recover()
        #expect(result.entities == Self.chain)
    }

    @Test("the first and the last entity both unreadable: the entities between are scanned for")
    func firstAndLastUnreadable() {
        var file = MadeUpFile()
        file.damage([0x20, 0x33])
        let result = file.recover()
        #expect(result.scanned)
        #expect(result.entities == Self.chain)
    }

    @Test("the first and the last entity both missing from the file are still listed")
    func firstAndLastMissing() {
        var file = MadeUpFile()
        file.remove([0x20, 0x33])
        let result = file.recover()
        #expect(result.entities == Self.chain)
    }

    @Test("an unreadable entity between two other breaks has no owner to find it by")
    func threeBreaks() {
        var file = MadeUpFile()
        file.damage([0x22, 0x26, 0x31])
        let result = file.recover()
        // Its own header is what cannot be read, so it is not found, and not counted. The two
        // walks and the scan give everything else.
        #expect(result.entities == Self.chain.filter { $0 != 0x26 })
    }

    @Test("entities written without links are followed and walked back by their handles")
    func entitiesWithoutLinks() {
        // Consecutive handles, so every one between the first and the last has implied links.
        let chain: [UInt64] = Array(0x50...0x59)
        var file = MadeUpFile(chain: chain)
        #expect(file.links[0x55]?.previous == 0 && file.links[0x55]?.next == 0)
        let whole = file.recover(first: 0x50, last: 0x59)
        #expect(whole.entities == chain)
        #expect(!whole.scanned)

        file.damage([0x54])
        let broken = file.recover(first: 0x50, last: 0x59)
        #expect(broken.entities == chain)
        #expect(!broken.scanned)
    }

    @Test("a record that names no first entity has no entities, and nothing is read")
    func noFirst() {
        let file = MadeUpFile()
        var read = 0
        let result = EntityChain.entities(
            first: 0, last: 0x33, record: MadeUpFile.record, excluding: [],
            links: { _ in
                read += 1
                return nil
            }, owner: { _ in nil },
            candidates: { [] })
        #expect(result == [])
        #expect(read == 0)
        #expect(file.recover(first: 0, last: 0).entities == [])
    }

    @Test("a record that names no last entity is walked forward only, up to the ENDBLK")
    func noLast() {
        var file = MadeUpFile()
        let afterLast = Self.chain[Self.chain.count - 1] + 1
        file.links[afterLast] = (previous: 0, next: 0)
        file.links[afterLast + 1] = (previous: 0, next: 0)
        let result = file.recover(
            first: Self.chain[0], last: 0,
            excluding: [MadeUpFile.blockEntity, afterLast])
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("a first entity that is not in the file is listed, and the walk back finds the rest")
    func firstNotInTheFile() {
        var file = MadeUpFile()
        file.remove([0x20])
        let result = file.recover()
        #expect(result.entities == Self.chain)
        #expect(!result.scanned)
    }

    @Test("links that loop back on the way forward end the walk, and the scan finds the rest")
    func forwardLoop() {
        var file = MadeUpFile()
        // 0x25 names 0x20 as the next, and 0x30 and 0x31 name each other as the previous, so
        // the walk forward cycles and the walk back is cut short.
        file.links[0x25] = (previous: 0x22, next: 0x20)
        file.links[0x30] = (previous: 0x31, next: 0x31)
        let result = file.recover()
        #expect(result.scanned)
        #expect(result.entities == Self.chain)
    }

    @Test("an entity that names itself as the next ends the walk")
    func selfLoop() {
        var file = MadeUpFile()
        file.links[0x21] = (previous: 0x20, next: 0x21)
        let result = file.recover()
        #expect(result.entities == Self.chain)
    }

    @Test("links that loop on the way back end the walk back, and the scan finds the rest")
    func backwardLoop() {
        var file = MadeUpFile()
        file.damage([0x22])
        // 0x32 and 0x33 each name the other as the previous.
        file.links[0x32] = (previous: 0x33, next: 0x33)
        file.links[0x33] = (previous: 0x32, next: 0)
        let result = file.recover()
        #expect(result.scanned)
        #expect(result.entities == Self.chain)
    }

    @Test("walks that cross without meeting leave what they skipped to the scan")
    func crossingWalks() {
        var file = MadeUpFile()
        file.damage([0x22])
        // The walk back skips 0x25: 0x26 names 0x21, which the walk forward has already found.
        file.links[0x26] = (previous: 0x21, next: 0x27)
        let result = file.recover()
        #expect(result.scanned)
        #expect(result.entities == Self.chain)
    }

    @Test("a walk that never ends is cut at the limit")
    func runawayChain() {
        // Every handle has implied links, so the walk goes on up the handles for ever.
        var calls = 0
        let result = EntityChain.entities(
            first: 1, last: 0x7FFF_FFFF, record: MadeUpFile.record, excluding: [],
            links: { _ in
                calls += 1
                return (previous: 0, next: 0)
            }, owner: { _ in nil }, candidates: { [] }, limit: 50)
        #expect(result.count <= 100)
        #expect(calls <= 100)
        #expect(Set(result).count == result.count)
    }

    @Test("the BLOCK and the ENDBLK are never taken for entities of the block")
    func blockAndEndBlockLeftOut() {
        var file = MadeUpFile()
        file.damage([0x22, 0x31])
        let result = file.recover()
        #expect(!result.entities.contains(MadeUpFile.blockEntity))
        #expect(!result.entities.contains(MadeUpFile.endBlockEntity))
    }
}
