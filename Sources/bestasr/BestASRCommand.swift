import ArgumentParser
import BestASRKit
import Foundation

@main
struct BestASR: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bestasr",
        abstract: "Benchmark-driven local ASR router for Apple Silicon.",
        discussion: """
            bestASR measures how ASR backends and models actually perform on THIS \
            machine (bestasr benchmark), then recommends and runs the best setup — \
            and explains why.
            """,
        version: BestASRVersion.current,
        subcommands: [
            Diagnose.self,
            Recommend.self,
            Transcribe.self,
            Benchmark.self,
            ListBackends.self,
            ListModels.self,
        ]
    )
}

// Command handlers delegate to BestASRKit.CommandCore (design D1: the executable
// stays a thin argument-parsing shell; behavior lives in the library where the
// test target can reach it).

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Detect this machine and print a recommendation"
    )

    func run() async throws {
        let core = CommandCore.live()
        print(try await core.diagnose())
    }
}

struct Recommend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recommend",
        abstract: "Print a JSON recommendation for an audio file (no transcription)"
    )

    @Argument(help: "Path to the input audio file")
    var audio: String

    @OptionGroup var selection: SelectionOptions

    func run() async throws {
        let core = CommandCore.live()
        print(try await core.recommendJSON(audioPath: audio, selection: selection.resolved()))
    }
}

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file with the best setup for this machine"
    )

    @Argument(help: "Path to the input audio file")
    var audio: String

    @OptionGroup var selection: SelectionOptions

    @Option(help: "Output format: \(OutputFormat.allNames.joined(separator: " | "))")
    var format: String = OutputFormat.txt.rawValue

    @Option(help: "Output file path (default: derived from the input file name)")
    var output: String?

    @Flag(help: "Explain why this backend/model was chosen (printed to stderr)")
    var explain = false

    func run() async throws {
        let core = CommandCore.live()
        let result = try await core.transcribe(
            audioPath: audio,
            selection: selection.resolved(),
            formatName: format,
            outputPath: output
        )
        print("Wrote \(result.format) transcript to \(result.outputPath)")
        if explain {
            FileHandle.standardError.write(Data((result.explanation + "\n").utf8))
        }
    }
}

struct Benchmark: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure every available backend/model/quantization on this machine"
    )

    @Argument(help: "Path to the input audio file")
    var audio: String

    @Option(help: "Path to the ground-truth .srt reference file")
    var reference: String

    @Option(help: "Language code for metric selection (cer for zh/ja/ko, wer otherwise)")
    var language: String = "auto"

    @Option(help: "Comma-separated backend filter (e.g. whisperkit,whisper.cpp)")
    var backends: String?

    @Option(help: "Comma-separated model filter (e.g. tiny,large-v3-turbo)")
    var models: String?

    @Option(help: "Optimization profile: fast | balanced | accurate")
    var profile: String = RouterProfile.balanced.rawValue

    @Flag(help: "Emit machine-readable JSON instead of the table")
    var json = false

    func run() async throws {
        let core = CommandCore.live()
        print(
            try await core.benchmark(
                audioPath: audio,
                referencePath: reference,
                language: language,
                backendFilter: Benchmark.parseList(backends),
                modelFilter: Benchmark.parseList(models),
                profileName: profile,
                asJSON: json
            )
        )
    }

    static func parseList(_ raw: String?) -> [String]? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct ListBackends: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-backends",
        abstract: "List supported backends and their availability"
    )

    func run() async throws {
        print(await CommandCore.live().listBackends())
    }
}

struct ListModels: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-models",
        abstract: "List supported model sizes and quantization variants"
    )

    func run() async throws {
        print(CommandCore.live().listModels())
    }
}

/// Shared selection flags for `recommend` and `transcribe`.
struct SelectionOptions: ParsableArguments {
    @Option(help: "Optimization profile: fast | balanced | accurate")
    var profile: String = RouterProfile.balanced.rawValue

    @Option(help: "Force a backend: auto | whisperkit | whisper.cpp")
    var backend: String = "auto"

    @Option(help: "Force a model size: auto | \(ModelRegistry.supportedModels.joined(separator: " | "))")
    var model: String = "auto"

    @Option(help: "Audio language code, or 'auto'")
    var language: String = "auto"

    func resolved() -> SelectionRequest {
        SelectionRequest(
            profileName: profile,
            backendOverride: backend == "auto" ? nil : backend,
            modelOverride: model == "auto" ? nil : model,
            requestedLanguage: language
        )
    }
}
