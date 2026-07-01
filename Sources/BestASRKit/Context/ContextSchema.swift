import Foundation

/// The context.json v1 document — the frozen contract between the core and
/// the plugin workflows (spec context-calibration: Load and validate the
/// context.json schema; design D2). `names` absorbs speakers: a speaker is a
/// name with a role.
public struct ContextDocument: Codable, Sendable, Equatable {
    public struct Name: Codable, Sendable, Equatable {
        public let name: String
        public let aliases: [String]?
        public let role: String?

        public init(name: String, aliases: [String]? = nil, role: String? = nil) {
            self.name = name
            self.aliases = aliases
            self.role = role
        }
    }

    public static let supportedVersion = 1

    public let version: Int
    public let language: String?
    public let terms: [String]?
    public let names: [Name]?
    public let phrases: [String]?
    /// Free text for the proofreading agent only — never rendered into the prompt.
    public let notes: String?

    public init(
        version: Int = ContextDocument.supportedVersion,
        language: String? = nil,
        terms: [String]? = nil,
        names: [Name]? = nil,
        phrases: [String]? = nil,
        notes: String? = nil
    ) {
        self.version = version
        self.language = language
        self.terms = terms
        self.names = names
        self.phrases = phrases
        self.notes = notes
    }

    /// Decode + validate a context.json payload. Malformed JSON and unknown
    /// versions are usage errors naming the file (spec scenarios).
    public static func load(data: Data, fileName: String) throws -> ContextDocument {
        let document: ContextDocument
        do {
            document = try JSONDecoder().decode(ContextDocument.self, from: data)
        } catch {
            throw BestASRError.usage(
                "cannot parse \(fileName): \(error.localizedDescription); "
                    + "expected a version-\(supportedVersion) context document"
            )
        }
        guard document.version == supportedVersion else {
            throw BestASRError.usage(
                "\(fileName) declares version \(document.version); "
                    + "version \(supportedVersion) is supported"
            )
        }
        return document
    }
}
