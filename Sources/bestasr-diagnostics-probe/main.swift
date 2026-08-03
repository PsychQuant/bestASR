import BestASRKit
import Foundation

// A hermetic stand-in for the last statement of `Transcribe.run()`, so a test
// can EXECUTE the stream defaults that the CLI relies on and observe which file
// descriptor each byte actually reaches (#136).
//
// Why this target exists rather than a test that spawns `bestasr` itself:
// `Transcribe.run()` calls `CommandCore.live()` unconditionally — six hard-wired
// engines plus `ExternalEngineRegistry` — and `$HOME` is not a seam, because
// `NSHomeDirectory()` ignores it on Darwin. A subprocess test on that path
// silently reads the developer's real `~/.bestasr/engines.json` and can spawn a
// real model. But *which fd a byte lands on* does not depend on any of that: it
// depends only on `report`'s two stream defaults. This binary reads those same
// defaults and nothing else.
//
// What it therefore proves, and what it does not: it proves the defaults send
// diagnostics to fd 2 and the success line to fd 1 in a real process. It does
// NOT prove `Transcribe.run()` calls `report` — that is a property of the
// executable's wiring, and `TranscribeDiagnosticsWiringTests` pins it as source
// text. The two halves are separate on purpose; neither substitutes for the
// other.
//
// argv: <0|1 explain> <outputPath> <format> <explanation> [warning...]

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 4, let explainFlag = Int(args[0]), explainFlag == 0 || explainFlag == 1 else {
    fputs(
        "usage: bestasr-diagnostics-probe <0|1 explain> <outputPath> <format> "
            + "<explanation> [warning...]\n", stderr)
    exit(64)
}

let outcome = TranscribeOutcome(
    outputPath: args[1],
    format: args[2],
    explanation: args[3],
    warnings: Array(args.dropFirst(4))
)

// No stream arguments. That is the whole point of this binary: this call reads
// the same two defaults `Sources/bestasr/BestASRCommand.swift` reads, so a test
// that spawns this process with separate pipes on fd 1 and fd 2 observes them.
// Passing streams here would test the arguments and leave the defaults exactly
// as unexamined as they were before this target existed.
TranscribeDiagnostics.report(outcome, explain: explainFlag == 1)
