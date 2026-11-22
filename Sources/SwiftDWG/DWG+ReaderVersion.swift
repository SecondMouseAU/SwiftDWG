extension DWG {
    /// The release of this package, equal to its git tag, such as `0.2.0`.
    ///
    /// Keep it beside a drawing this package read, as a record of which release read it. Two
    /// releases can read the same file differently, and a changed result can be traced to a
    /// changed reader only if the release that read it is on the record.
    ///
    /// A release sets this to its own tag before it is tagged, and the `release-version` workflow
    /// fails the tag if the two differ. The value is a plain `major.minor.patch` string, with no
    /// leading `v`, the same as the tags (`ReaderVersionTests`, `Scripts/check-reader-version.sh`).
    /// A build of the main branch between two releases reports the last release made.
    public static let readerVersion = "0.2.0"
}
