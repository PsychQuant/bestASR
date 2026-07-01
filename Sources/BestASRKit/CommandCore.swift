import Foundation

/// The outcome of a `transcribe` invocation, for the CLI to report.
public struct TranscribeOutcome: Sendable {
    public let outputPath: String
    public let format: String
    public let explanation: String

    public init(outputPath: String, format: String, explanation: String) {
        self.outputPath = outputPath
        self.format = format
        self.explanation = explanation
    }
}

/// Library-side command handlers (design D1: the executable is a thin
/// argument-parsing shell; every behavior lives here where tests can reach it).
///
/// Command bodies are wired in the CLI-integration phase; the surface exists
/// from the skeleton so `bestasr --help` is stable from day one.
public struct CommandCore: Sendable {
    public let engines: [any Engine]

    public init(engines: [any Engine]) {
        self.engines = engines
    }

    /// The production wiring: real engines, real detection, real cache.
    public static func live() -> CommandCore {
        CommandCore(engines: [])
    }

    public func diagnose() async throws -> String {
        throw BestASRError.runtime("diagnose is not wired yet (CLI integration phase)")
    }

    public func recommendJSON(audioPath: String, selection: SelectionRequest) async throws -> String {
        throw BestASRError.runtime("recommend is not wired yet (CLI integration phase)")
    }

    public func transcribe(
        audioPath: String,
        selection: SelectionRequest,
        formatName: String,
        outputPath: String?
    ) async throws -> TranscribeOutcome {
        throw BestASRError.runtime("transcribe is not wired yet (CLI integration phase)")
    }

    public func benchmark(
        audioPath: String,
        referencePath: String,
        language: String,
        backendFilter: [String]?,
        modelFilter: [String]?,
        profileName: String,
        asJSON: Bool
    ) async throws -> String {
        throw BestASRError.runtime("benchmark is not wired yet (CLI integration phase)")
    }

    public func listBackends() async -> String {
        "list-backends is not wired yet (CLI integration phase)"
    }

    public func listModels() -> String {
        "list-models is not wired yet (CLI integration phase)"
    }
}
