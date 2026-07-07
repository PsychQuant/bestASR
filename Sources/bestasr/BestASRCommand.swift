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
            Corpus.self,
        ]
    )
}

// Command handlers delegate to BestASRKit.CommandCore (design D1: the executable
// stays a thin argument-parsing shell; behavior lives in the library where the
// test target can reach it).

/// Maps typed library errors to the design-D10 exit codes: usage → 2,
/// runtime/transcription → 1. Everything else falls through to ArgumentParser.
func runMapped(_ body: () async throws -> Void) async throws {
    do {
        try await body()
    } catch let error as BestASRError {
        FileHandle.standardError.write(Data("error: \(error.errorDescription ?? "failed")\n".utf8))
        throw ExitCode(error.exitCode)
    } catch let error as TranscriptionError {
        FileHandle.standardError.write(
            Data("error: \(error.errorDescription ?? "transcription failed")\n".utf8))
        throw ExitCode(1)
    }
}

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Detect this machine and print a recommendation"
    )

    func run() async throws {
        try await runMapped {
            print(try await CommandCore.live().diagnose())
        }
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
        try await runMapped {
            print(
                try await CommandCore.live().recommendJSON(
                    audioPath: audio, selection: selection.resolved()))
        }
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

    @Flag(help: "Label each cue with an acoustic speaker (SPEAKER_1…); downloads CoreML diarization models on first use")
    var diarize = false

    func run() async throws {
        try await runMapped {
            let result = try await CommandCore.live().transcribe(
                audioPath: audio,
                selection: selection.resolved(),
                formatName: format,
                outputPath: output,
                diarize: diarize
            )
            print("Wrote \(result.format) transcript to \(result.outputPath)")
            if explain {
                FileHandle.standardError.write(Data((result.explanation + "\n").utf8))
            }
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

    @Option(help: "Report-ranking profile: low | medium | high | xhigh | max")
    var profile: String = RouterProfile.medium.rawValue

    @Option(
        help: "Context documents directory for context biasing (top-down / prompt biasing: domain vocabulary, names, terms) — adds a with-context pass and delta columns"
    )
    var contextDir: String?

    @Flag(help: "Widen the sweep to every grid tier (default: priority-1 rows only)")
    var allGrid = false

    @Flag(
        help: """
            Disable temperature-fallback re-decoding so the same audio always \
            yields the same text (used by scripts/regression-gate.sh — the \
            canary must be reproducible; normal transcription keeps the fallback)
            """)
    var decodeDeterministic = false

    @Flag(help: "Emit machine-readable JSON instead of the table")
    var json = false

    func run() async throws {
        try await runMapped {
            print(
                try await CommandCore.live().benchmark(
                    audioPath: audio,
                    referencePath: reference,
                    language: language,
                    backendFilter: Benchmark.parseList(backends),
                    modelFilter: Benchmark.parseList(models),
                    profileName: profile,
                    asJSON: json,
                    contextDir: contextDir,
                    allGrid: allGrid,
                    decodeDeterministic: decodeDeterministic
                )
            )
        }
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
    @Option(
        help:
            "Effort profile: auto | low | medium | high | xhigh | max — auto adapts to machine pressure; max = most accurate regardless of time"
    )
    var profile: String = "auto"

    @Option(
        help: ArgumentHelp(
            "Force a backend: auto | "
                + BackendID.allCases.map(\.rawValue).joined(separator: " | ")))
    var backend: String = "auto"

    @Option(
        help: "Force a model size: auto | \(ModelRegistry.supportedModels.joined(separator: " | ")) | 0.6b-v3 (fluid-parakeet)")
    var model: String = "auto"

    @Option(help: "Audio language code, or 'auto'")
    var language: String = "auto"

    @Option(
        help: "Context documents directory for context biasing (top-down / prompt biasing: bias decoding toward your domain vocabulary, names, and terms; default: three-layer resolution)"
    )
    var contextDir: String?

    func resolved() -> SelectionRequest {
        SelectionRequest(
            profileName: profile,
            backendOverride: backend == "auto" ? nil : backend,
            modelOverride: model == "auto" ? nil : model,
            requestedLanguage: language,
            contextDir: contextDir
        )
    }
}


// MARK: - corpus (spec corpora, #14)

struct Corpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage ground-truth corpora for benchmarking",
        subcommands: [Add.self, List.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Register an audio + reference pair as a corpus")

        @Argument(help: "Audio file path") var audio: String
        @Argument(help: "Reference transcript (.srt) path") var reference: String
        @Option(help: "Two-letter language code (en/zh/ja/...)") var language: String
        @Option(help: "Display name (default: audio file name)") var name: String?

        func run() async throws {
            try await runMapped {
                let row = try CorpusRegistry.add(
                    audioPath: audio, referencePath: reference,
                    language: language, name: name, store: BenchmarkStore())
                print("Registered corpus \(row.corpusId): \(row.name) [\(row.language)] "
                    + String(format: "%.1fs", row.duration))
            }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List registered corpora")

        func run() async throws {
            try await runMapped {
                print(try CorpusRegistry.listTable(store: BenchmarkStore()))
            }
        }
    }
}
