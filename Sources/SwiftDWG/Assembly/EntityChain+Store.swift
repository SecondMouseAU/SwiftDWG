extension EntityCommon {
    /// The block record the entity is in, or `nil` when it names none.
    ///
    /// Mode 0 gives the owner's handle, 1 is the paper space block and 2 the model space block.
    func block(modelSpace: UInt64, paperSpace: UInt64) -> UInt64? {
        let found: UInt64
        switch entityMode {
        case 0: found = owner
        case 1: found = paperSpace
        case 2: found = modelSpace
        default: return nil
        }
        return found != 0 ? found : nil
    }
}

extension ObjectStore {
    /// The neighbours of the entity with this handle in its block's chain, or `nil` when the file
    /// does not hold it or its data cannot be read as far as the links.
    ///
    /// Only the data up to the links is read, so a field after them that is damaged does not break
    /// the chain.
    func chainLinks(of handle: UInt64) -> EntityChain.Links? {
        guard var reader = try? reader(for: handle),
            let common = try? reader.readEntityCommonThroughLinks()
        else { return nil }
        return (common.previous, common.next)
    }

    /// The block record the object with this handle is an entity in, or `nil` when the file does
    /// not hold it, it is not an entity, or its data cannot be read as far as its owner.
    func block(ofEntity handle: UInt64, modelSpace: UInt64, paperSpace: UInt64) -> UInt64? {
        guard var reader = try? reader(for: handle),
            ObjectType.isEntity(reader.type, classes: classes),
            let common = try? reader.readEntityCommonThroughLinks()
        else { return nil }
        return common.block(modelSpace: modelSpace, paperSpace: paperSpace)
    }
}
