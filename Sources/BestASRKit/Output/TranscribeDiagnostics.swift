import Foundation

/// What a `transcribe` run tells the reader besides the transcript path, and
/// where it goes (#136).
///
/// This lives in the library rather than in `Sources/bestasr/` for one reason:
/// the executable target has no test coverage at all, and #136's third
/// acceptance line asks for *"a test [that] asserts the warning reaches stderr
/// on the default path — the current suite would not have caught this."* The
/// first fix satisfied that at the data layer (`TranscribeOutcome.warnings` is
/// populated) and left the layer the bug actually lived in untested: deleting
/// the CLI's entire printing branch kept the whole suite green, which is the
/// same failure mode one level up.
///
/// The split below is deliberate. `lines(for:explain:)` is pure, so the branch
/// and the prefix are cheap to assert — but a test of it alone cannot see a
/// regression that sends the same strings to *stdout*, which for anyone piping
/// a transcript is #136 again. `emit(for:explain:to:)` adds the destination.
///
/// `report(_:explain:out:err:)` is what the CLI calls; `emit` has no production
/// caller of its own. `report` exists because neither of the two above
/// establishes that the CLI still calls any of this, or without an override, or
/// before the success line. Those are properties of the *wiring*, and #136 was a
/// wiring bug: a call-site `if explain` guard. Re-adding that guard restored the
/// reported behaviour verbatim with the whole suite green, so `report` moves
/// both statements behind one testable call and a source-level lock pins its
/// position at the call site.
///
/// Three layers, and it took three rounds to notice they were not the same
/// layer: *what* is rendered (`lines`), *where* it goes (`emit` + `destination`),
/// and *whether the CLI invokes it* (`report` + the lock). A fourth was hiding
/// between the third and the second — `report`'s stream **defaults**, which the
/// CLI relies on by passing neither and which every test overrode. Changing
/// `err:`'s default alone put every warning on stdout with the whole suite
/// green. `bestasr-diagnostics-probe` now executes those defaults in a real
/// process so a test can watch which fd each byte reaches.
public enum TranscribeDiagnostics {

    /// The lines a run should surface, in order. Pure: no I/O, no globals.
    ///
    /// `--explain` renders the explanation block, which already contains the
    /// warnings inline and in context with the reasons; printing them again
    /// would duplicate. The default path renders the warnings alone, prefixed.
    /// The two are mutually exclusive by construction rather than by content
    /// comparison, so duplication is not merely absent, it is unrepresentable.
    public static func lines(for outcome: TranscribeOutcome, explain: Bool) -> [String] {
        if explain {
            return outcome.explanation.isEmpty ? [] : [outcome.explanation]
        }
        return outcome.warnings.map { "warning: \($0)" }
    }

    /// Where diagnostics go.
    ///
    /// Named rather than inlined so a test can assert it — the destination is
    /// precisely the half that a pure test of `lines(for:explain:)` cannot see,
    /// and a one-word change to `stdout` would reintroduce #136 for anyone
    /// piping a transcript while every string-level assertion stayed green.
    ///
    /// That protection was fitted one level away from where production reads,
    /// though, and the gap it left was real: `report` names this constant as its
    /// `err:` default, the CLI passes no streams, and *changing the default*
    /// leaves this assertion green because the constant itself is untouched.
    /// Measured: **461/461 green** with every warning on stdout. Asserting a
    /// constant only helps where something asserts that the constant is what
    /// runs — which is now `TranscribeDiagnosticsDefaultStreamTests`.
    ///
    /// The alternative — redirecting the process's real fd 2 around a call —
    /// tests the same property more directly and must not be used *here*:
    /// inside a test bundle, `close(2)` hands fd 2 to whatever the harness opens
    /// next, and restoring it then closes that resource out from under the
    /// harness. Correct technique, wrong host.
    public static let destination: UnsafeMutablePointer<FILE> = stderr

    /// Writes those lines to `stream`.
    ///
    /// Through `ConsoleLine`, which documents why neither
    /// `FileHandle.write(_:)` nor `fputs` is usable here and what the choice
    /// does not buy. The misuse it replaces predates #136, but #136 promoted it
    /// from `--explain`-only to the default path, and this repo ships skill
    /// templates that gate on `$?`. An exit code that stops describing what
    /// happened is the same defect this issue is named after, one layer out.
    public static func emit(
        for outcome: TranscribeOutcome, explain: Bool,
        to stream: UnsafeMutablePointer<FILE> = destination
    ) {
        for line in lines(for: outcome, explain: explain) {
            ConsoleLine.write(line + "\n", to: stream)
        }
    }

    /// Everything a completed `transcribe` run reports: diagnostics first, then
    /// the success line.
    ///
    /// Both statements live here rather than at the call site so the *ordering*
    /// is a property of tested code rather than of two adjacent lines nobody
    /// asserts on. Warnings precede the success line because stderr is
    /// unbuffered while stdout is at best line-buffered — under `2>&1` that
    /// makes warning-first the order a merged reader sees. (Across two separate
    /// pipes there is no global ordering guarantee at all, which is why this is
    /// a presentation choice and not a cross-stream contract.)
    public static func report(
        _ outcome: TranscribeOutcome, explain: Bool,
        out: UnsafeMutablePointer<FILE> = stdout,
        err: UnsafeMutablePointer<FILE> = destination
    ) {
        emit(for: outcome, explain: explain, to: err)
        ConsoleLine.write(
            "Wrote \(outcome.format) transcript to \(outcome.outputPath)\n", to: out)
    }
}
