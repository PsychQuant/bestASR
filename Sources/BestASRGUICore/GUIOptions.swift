import Foundation

import BestASRKit

/// Picker vocabularies + the production runner wiring for the GUI (#87).
/// Derived from the same core types the CLI uses so the surfaces cannot drift.
public enum GUIOptions {
    /// Benchmark-backed languages plus auto-detect (design D3; free-form codes later).
    public static let languages = ["auto", "zh", "ja", "en"]

    /// "auto" resolves per machine state in CommandCore; ordinals come straight
    /// from RouterProfile so a new profile appears here without GUI edits.
    public static var efforts: [String] { ["auto"] + RouterProfile.allCases.map(\.rawValue) }

    /// The formats TranscriptWriter already renders.
    public static var formats: [String] { OutputFormat.allNames }

    public static func requestedLanguage(fromSelection selection: String) -> String? {
        selection == "auto" ? nil : selection
    }
}

public enum GUITranscribe {
    /// Production seam: one warm CommandCore per app process so engine pipeline
    /// caches survive across GUI runs (same reuse rationale as the MCP server).
    public static func coreRunner(core: CommandCore = .live()) -> TranscribeRunner {
        { request in
            try await core.transcribe(
                audioPath: request.audioPath,
                selection: SelectionRequest(
                    profileName: request.profileName,
                    backendOverride: nil,
                    modelOverride: nil,
                    requestedLanguage: request.requestedLanguage),
                formatName: request.formatName,
                outputPath: request.outputPath)
        }
    }
}
