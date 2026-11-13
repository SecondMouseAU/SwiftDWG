extension DWG {
    /// Why a DWG could not be read.
    public enum Error: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        /// The bytes do not start like a DWG.
        case notADWG
        /// The file is a DWG of a release this package does not read yet.
        case unsupportedVersion(String)
        /// The data ended before a field did.
        case truncated(String)
        /// A field has a value the format does not allow, or a structure does not add up.
        case invalid(String)

        public var description: String {
            switch self {
            case .notADWG: return "not a DWG file"
            case .unsupportedVersion(let code): return "DWG version \(code) is not supported"
            case .truncated(let what): return "DWG data ended while reading \(what)"
            case .invalid(let what): return "invalid DWG data: \(what)"
            }
        }
    }
}
