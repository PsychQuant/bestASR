import Foundation

/// The set of licenses under which a corpus entry may be published to the
/// shared benchmark. Single source of truth for the contribution gate
/// (bench-contribute skill) and the manifest CI validator.
public enum CorpusLicense: String, CaseIterable, Codable, Sendable {
    case cc0 = "CC0"
    case ccBy = "CC-BY"
    case ccBySa = "CC-BY-SA"
    case publicDomain = "public-domain"
    case ownConsented = "own-consented"

    /// Parse a supplied license string (whitespace-trimmed); nil if not allowed.
    public static func parse(_ raw: String) -> CorpusLicense? {
        CorpusLicense(rawValue: raw.trimmingCharacters(in: .whitespaces))
    }

    public static var allowed: Set<String> { Set(allCases.map(\.rawValue)) }
}
