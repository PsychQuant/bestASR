import BestASRKit
import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// **The whole shape of every file is declared here, recursively, and not read
/// from the artifact** — every object's key set is exact in both directions,
/// every scalar has a kind, every array has an element kind, a minimum length
/// and a distinctness requirement.
///
/// Rounds 10 to 13 each found the same defect one level further out along one
/// axis: does the field exist → what is its name → how much of the file is
/// covered → what kind of thing does it hold. Round 14 found the axis none of
/// them touched — **what the value has to be worth**. The four identities were
/// a homogeneous system, so the zero vector solved them, and `text` meant only
/// "at least one non-space character": a 2,774-byte file whose every string was
/// `"x"` and every count `0` passed every rule, as did one built from U+2060
/// word joiners, which renders as empty.
///
/// So the declaration now constrains magnitude as well as form, and `laws`
/// derives what is derivable rather than asserting it:
/// `metric.value == edits / reference_words`, `merges == chunks - 1`,
/// `case_folded_canonical_id ∈ case_folded_matched_token_ids`. Those are laws
/// of the recording, not of this run; a re-measurement satisfies them or the
/// recording is wrong. `observations` is the separate, deliberate class for
/// checks that are true of *this* run and are not laws — among them the corpus
/// it was recorded on, the language it was transcribed in, the transcripts
/// being identical across arms, run-to-run equality, the `nm` counts differing.
/// Changing one of those means changing the declaration, on purpose. Both
/// arrays hold `Relation`s; *law* and *observation* name the claim, not the
/// type.
///
/// **The blind spots this leaves.** There is no sentence classifying or
/// counting the list below, because for seventeen
/// consecutive rounds every such sentence has been wrong — the vacuity case
/// stated backwards; figures called unbound when three of them fail on change; a
/// byte count that was a character count; *"that is the whole of the
/// constraint"* while five further rules constrained it; external checks counted
/// as "two, and only two" while naming three, then "four" in one paragraph and
/// "the only" four in another that meant five; a rule written as a prohibition
/// eight bullets after being written correctly; *"five rules"* introducing six;
/// and — in the round that added *"a summarising sentence over a list asserts a
/// completeness the list was never checked for"* — such a sentence three
/// sentences later, wrong on both of its counts.
///
/// The lesson is not to count more carefully. It is that a summary of a list
/// **is a second copy of the list**, maintained by nobody, and it drifts. The
/// same reasoning deleted a regex over shell source in round 23 and two command
/// relations in round 24: where a claim cannot be kept true, do not make it.
///
/// - **Prose *content* is mostly not under test**, and where it is, the pinning
///   is listed field by field further down rather than summarised here. Every
///   string not named there is still constrained in *form*, by rules that read
///   no relation at all: `.text`, `.hex`, array distinctness, the dangling-name
///   rule, the bare-name rule, the probe-citation rule, and the two
///   probe-method rules. Within those — and excepting the six digest strings,
///   which `.hex(64)` holds to 64 lowercase hex characters — any such string
///   may be replaced by a **short filler** — a file so built passes all eight tests at about **4 kB against
///   23,987**, losing the reproduction recipe, the commands that produced every
///   number, the provenance paragraph saying the verifier runs were not blind
///   and not independently designed, the four-cell `nm` table, sixteen of twenty
///   probe methods and every `method_limits` entry. A passing run does **not**
///   mean the file still says what it said.
///
///   *About* 4 kB, and the vagueness is the honest part. Three independent
///   reconstructions from this paragraph measured 4,155, 4,165 and 4,180 bytes,
///   and the same content re-serialised without indentation is 3,315 — an
///   840-byte swing the paragraph does not govern at all. A recipe in prose
///   underdetermines a file; quoting one of its outcomes to the byte is how a
///   character count once passed for a byte count.
///
///   The fillers are not free-form. What the smallest of those files had to
///   satisfy: each array's elements render differently from one another, and so
///   do the twenty probe methods; every probe method carries a backticked token
///   that is neither its own field name nor a key from another block; no filler
///   is blank-rendering, writes an underscored key without backticks, or
///   backticks an underscored name that is no field; `edit_list` still names
///   exactly `metric.edits` operation words; `metric.kind` still agrees with
///   `LanguageResolver`, and `session.corpus` and `session.language` with the
///   declaration; and the bound phrases below are still present — the figures,
///   not the sentences that carried them. That is what one measured file needed,
///   not a proof that nothing else constrains a filler. So `"x"` everywhere
///   **fails**, while `"a"`, `"b"`, … with `` `a` 0 ``, `` `a` 1 ``, … in the
///   probes passes.
/// - **Three probe entries are read by a relation and still drift.** The clauses
///   guarded `!quotes(…) || …` — `never nil`, `each 0`, `recorded true` — go
///   vacuous when their phrase is removed, so "a field a relation reads has its
///   content pinned" is not true of them. They are the exception to the bullet
///   above, which is why that bullet no longer states the rule as a dichotomy.
/// - **A declaration detects one-sided change.** A deletion, rename or typo
///   applied to both the artifact and the declaration agrees with itself. That
///   is the dual of a derived schema, which cannot detect absence at all.
/// - **`.text` is a floor, not a legibility test.** It rejects the empty
///   string, the Marks, and the ten blank-rendering scalars found so far. No
///   Foundation predicate answers "does this render", so a scalar nobody has
///   tried will pass — and a single `x` passes by design. It is also not sound
///   in the other direction: subtracting the non-base characters rejects a
///   lone spacing mark such as U+0903, which does render.
/// - **The prose anchors protect against numeric drift, not against false
///   prose.** A quoted figure must appear as a complete numeric token, with
///   nothing numeric continuing it on either side, and no minus in front:
///   `7730`, `1773`, `773,000`, `773.5`, `1,773`, `-773` and the same with an
///   en, em or soft-hyphen dash all fail a seek for `773`. `+773` passes,
///   because it *is* 773.
///
///   One admission is deliberate and is a real gap: a figure that a word or a
///   digit runs into keeps its hyphen, so `guard-773` reads as 773 — and so does
///   **`1000-773`, which a human reads as 227**. That was the price of accepting
///   `133+640` and `773-640`, the forms someone restating `_limits[1]` actually
///   writes. It is confined to the bare-number seek: the four probe phrases seek
///   a number inside a phrase, and `agree at 1000-773` fails.
///
///   Nothing reads affirmation, negation or subject: an entry saying "They do
///   not agree at 773" satisfies the anchor, and so does "All three disagree at
///   773". (The bare sentence alone still fails — a different rule catches it
///   for citing nothing.)
/// - **Removing a phrase makes three of the seven probe clauses vacuous** — the
///   ones guarded `!quotes(…) || …`, namely `never nil`, `each 0` and
///   `recorded true`. Removing any of the other four, or either quadruple, or
///   `_reproducing`'s figure, makes its law **fail**.
/// - **The quadruple parser is strict about syntax and blind to context.** It
///   needs exactly two parseable matches in textual order, and moving both into
///   a negated passage still passes. A third quadruple breaks it only if it
///   parses — one whose digits overflow `Int` is dropped and the law passes.
/// - **A probe entry's citation is checked for existence, not for aptness**, so
///   filler, a denial or mutual citation pass — except where a prose law pins
///   the entry. What it may *not* cite is a backticked name that is a key
///   somewhere else in the file: `` `edits` `` in a probe fails, because
///   `metric.edits` belongs to another block. In scope are the census
///   measurements, the declared `how` keys, `path_coverage` and `_limits`. The
///   twenty methods must also render differently from each other, and none may
///   name *only* its own field — naming it alongside something else is fine,
///   which is what the failure message ("names nothing but itself") says and
///   what the bullet above states correctly.
/// - **No rule checks a method is true of the code**, or that a citation is apt.
/// - **The two name rules are not one rule.** The dangling-name rule sees
///   underscored, all-lowercase, non-`__` names; the bare-name rule has no
///   lowercase filter and excludes any leading underscore, so `_limits`
///   may be written bare. `chunks` and `merges` are invisible to both, in
///   backticks or out — single words cannot be required to carry backticks,
///   since the file legitimately writes `nil`, `left`, `grep`.
/// - **Which prose figures are bound is an explicit list, not a region.**
///   Bound: the four `how.probes` phrases, both quadruples in
///   `isolating_the_counterfactual`, `_reproducing`'s recorded value, the five
///   figures restated in `_limits[1]`, and `edit_list`'s operation words.
///   Everything else drifts silently. Among them: `_limits[0]`'s token ids,
///   `_nm_note`'s four cells, `method_limits`' counts, the toolchain version,
///   `session.measured_at`, and the four figures in `_reproducing` other than
///   the recorded one. That list is examples, not an inventory.
/// - **The numbers are pinned; the conclusions stated in words are not.** The
///   `nm` counts are pinned to 0 and 4, and `_nm_note` three keys away may say
///   the arms came out the other way round. `cross_pin_cmp` may report the
///   transcripts differ while three observations assert they are identical.
///   Nothing here reads affirmation or negation, and binding English polarity
///   is not attempted — so the sentence a reader quotes is the part no test
///   defends, sitting beside the figure that is defended.
/// - **One relation reads another file, and one reads shipped code.** The arm
///   under test must carry the revision `Package.resolved` pins; `metric.kind`
///   must be what `LanguageResolver` returns for `session.language`. Nothing
///   else here opens anything outside `benchmarks/evidence/`.
///
///   There were four, until round 23. Three read `scripts/fetch-corpora.sh` by
///   regex, and 16 of 66 shell constructions left them **green while the script
///   and the evidence disagreed** — so the corpus name and its two digests are
///   now literals a reviewer read, declared in `observations`, and the parse is
///   deleted. `Package.resolved` earns its place by being different in the way
///   that matters: written by a **tool**, in a stable format, and the only thing
///   in the repository that independently knows what the arm was built from.
///
///   Everything else is checked against another value in the same JSON, prose
///   in the same JSON, or a literal here — so the suite is a **drift detector
///   on a reviewed snapshot**, not a measurement verifier. It does not rerun
///   the transcription, hash any transcript, recompute the WER **from the
///   transcripts**, or inspect the executable `executable_sha256` names. That
///   emphasis carries weight: `metric.value` *is* re-derived from
///   `edits / reference_words`. (The reference transcript used to be hashed
///   here; deleting the script parse deleted that too, and the reference digest
///   is now a reviewed literal like the other two.)
/// - **The `case_folded_*` counts are pinned by `observations`, not by any
///   law.** Not "the census": `chunks` and `merges` are in `measuredCensus`
///   too, and scaling them fires the law `merges == chunks - 1`, which is
///   affine rather than homogeneous. The `case_folded_*` sum identities *are*
///   homogeneous, so they hold under uniform scaling and under reallocation
///   between `matches` and `canonicals_differed`; the anchors pin the same
///   ratios. Nothing internal to the file can tell those apart from an
///   honest run, so re-measuring means editing this declaration, on purpose.
///   That is the cost, and it is the point.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    /// Every recorded transcript digest is a key beginning with this.
    static let transcriptPrefix = "transcript_sha256_"

    /// The corpus this evidence was measured on, as a reviewer read it out of
    /// `scripts/fetch-corpora.sh`: the name it registers, the WAV digest it
    /// verifies after conversion, and the digest of the reference SRT it writes.
    ///
    /// **These are literals, and nothing here reads that script.** Rounds 21 and
    /// 22 derived them with a regex; round 23 measured what the derivation was
    /// worth. Of 66 shell constructions run against real `bash`, 25 left the
    /// parse holding a value and **16 of those left the suite green while the
    /// script and the evidence disagreed** — a trailing `;` on a re-pin line, a
    /// stale one-liner above a reformatted definition, the two digest arguments
    /// transposed, a `\r\n` that made the reconstruction run into the *next*
    /// corpus. A regex over shell source models text adjacency; `bash` binds
    /// names. That gap does not close by widening the regex, and while it was
    /// open these checks asserted a corroboration they did not have — which is
    /// worse than a literal, because a literal never claimed one.
    ///
    /// So the claim is now the true one, and it is smaller: a human compared
    /// these values against the script, and this file records what they found.
    /// Two of them are read directly — the registered name and `OSR1_SHA`. The
    /// reference digest is not written down anywhere in that script: it is the
    /// SHA-256 of what `fetch_osr1`'s heredoc emits, so obtaining it is a
    /// computation, not a reading. `language` comes from the `--language`
    /// argument inside `fetch_osr_list`. That catches the evidence drifting away from what was reviewed —
    /// one of the two directions the derivation covered, and the one worth
    /// keeping. The other is genuinely gone: **no edit to
    /// `scripts/fetch-corpora.sh` is visible to this suite any more.** Rename
    /// the corpus, re-pin the WAV, change a word of the reference transcript,
    /// or register nothing at all, and every test still passes. These literals
    /// are a snapshot of a review performed once; nothing re-performs it.
    ///
    /// Re-pinning the corpus means editing these lines on purpose. Source:
    /// `scripts/fetch-corpora.sh` at `58420bf` — `fetch_osr1` for the name and
    /// the heredoc, `OSR1_SHA` for the WAV digest, `fetch_osr_list` for the
    /// language.
    static let reviewedCorpus = (
        name: "osr-harvard-1",
        audio: "0ed4ea79ee09b36f40235992b5bc03009f23167c0525930ddeafee0c04716a49",
        reference: "644c935af618dde484af146260166bb8c8d9be244ff467b1964b99d48d81c35e",
        language: "en")

    /// The FluidAudio pin as `Package.resolved` records it, or `nil` if it is
    /// unreadable or absent.
    ///
    /// Everything else in this file checks the artifact against itself. That
    /// leaves the one thing the artifact exists to establish unchecked: swapping
    /// the two arms' revisions passed every rule, and the file then said the
    /// 0.15.5 pin exports no case-variant symbol and 0.15.4 exports four — the
    /// reverse of this PR's conclusion. The evidence file already names the
    /// missing check; `_reproducing` says `fluidaudio_revision` is recomputable
    /// from `Package.resolved`.
    static let pinnedFluidAudio: (version: String, revision: String)? = {
        guard let data = try? Data(contentsOf: repoRoot.appendingPathComponent("Package.resolved")),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pins = root["pins"] as? [[String: Any]]
        else { return nil }
        for pin in pins where (pin["identity"] as? String) == "fluidaudio" {
            guard let state = pin["state"] as? [String: Any],
                let version = state["version"] as? String,
                let revision = state["revision"] as? String
            else { return nil }
            return (version, revision)
        }
        return nil
    }()

    // MARK: - The declaration

    indirect enum Node {
        /// Exact key set: missing and undeclared keys both fail.
        case object([String: Node])
        /// A non-empty string, counting only characters that render.
        case text
        /// Lowercase hex of exactly this length — a digest or a revision.
        case hex(Int)
        /// A whole number, at least `min`.
        case count(min: Int)
        /// A real number, at least `min`.
        case real(min: Double)
        case flag
        case array(of: Node, min: Int, distinct: Bool)
    }

    /// A relation over the whole file. `laws` must hold of any correct
    /// recording; `observations` hold of the recorded run and are not laws, so
    /// changing one means changing this declaration deliberately.
    struct Relation {
        let label: String
        let holds: ([String: Any]) -> Bool
    }

    struct Shape {
        let root: Node
        let measurements: [String]
        let laws: [Relation]
        let observations: [Relation]
    }

    // MARK: - Accessors used by the relations

    private static func value(_ json: [String: Any], _ path: String) -> Any? {
        path.split(separator: ".").reduce(json as Any?) { node, key in
            (node as? [String: Any])?[String(key)]
        }
    }
    private static func int(_ json: [String: Any], _ path: String) -> Int? {
        guard let n = value(json, path) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID()
        else { return nil }
        return n.intValue
    }
    private static func double(_ json: [String: Any], _ path: String) -> Double? {
        guard let n = value(json, path) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID()
        else { return nil }
        return n.doubleValue
    }
    private static func string(_ json: [String: Any], _ path: String) -> String? {
        value(json, path) as? String
    }
    private static func sum(_ json: [String: Any], _ paths: [String]) -> Int? {
        var total = 0
        for p in paths {
            guard let v = int(json, "path_coverage." + p) else { return nil }
            // Shape-valid Int.max values would trap here and crash the process
            // instead of failing the expectation.
            let (sum, overflow) = total.addingReportingOverflow(v)
            if overflow { return nil }
            total = sum
        }
        return total
    }
    private static func equalCounts(_ label: String, _ lhs: [String], _ rhs: [String]) -> Relation {
        Relation(label: label) { sum($0, lhs) != nil && sum($0, lhs) == sum($0, rhs) }
    }

    private static func armNode() -> Node {
        .object([
            "fluidaudio_revision": .hex(40), "executable_sha256": .hex(64),
            "nm_caseVariantCanonicalIds": .count(min: 0),
            "transcript_sha256_srt_run1": .hex(64), "transcript_sha256_srt_run2": .hex(64),
            "transcript_sha256_txt": .hex(64),
        ])
    }

    /// `path_coverage` is built from the measurement map, so the schema, the
    /// probe map and the measurement list cannot drift apart.
    private static func pathCoverageNode(_ measurements: [String: Node]) -> Node {
        var keys = measurements
        keys["how"] = .object([
            "patch": .text, "build": .text, "probe_implementation": .text,
            "isolating_the_counterfactual": .text,
            "method_limits": .array(of: .text, min: 5, distinct: true),
            // `.text` alone let all twenty methods be the same string.
            "probes": .object(measurements.mapValues { _ in Node.text }),
        ])
        keys["_limits"] = .array(of: .text, min: 5, distinct: true)
        return .object(keys)
    }

    /// A count's minimum is part of the recording's meaning: a run that
    /// produced no chunks produced no evidence, while a guard cause that never
    /// fired is a real zero.
    static let fluidAudioMeasurements: [String: Node] = [
        // `merges == chunks - 1`, so a single-chunk run has none.
        "chunks": .count(min: 1), "merges": .count(min: 0),
        "case_folded_calls": .count(min: 1),
        "case_folded_early_return_ids_equal": .count(min: 0),
        "case_folded_reached_guard": .count(min: 1),
        "case_folded_guard_else": .count(min: 0),
        "case_folded_guard_else_map_nil": .count(min: 0),
        "case_folded_guard_else_id_absent": .count(min: 0),
        "case_folded_both_ids_in_map": .count(min: 0),
        "case_folded_canonicals_differed": .count(min: 0),
        "case_folded_matches": .count(min: 0),
        "case_folded_canonical_id": .count(min: 0),
        "collapse_tokens_in": .count(min: 1), "collapse_tokens_out": .count(min: 1),
        "word_boundary_fallbacks_entered": .count(min: 0),
        "case_folded_matched_token_ids": .array(of: .count(min: 0), min: 2, distinct: true),
        "collapse_called": .flag,
        "case_folded_changed_merge_output": .flag,
        "counterfactual_tokens_equal": .flag,
        "counterfactual_timestamps_equal": .flag,
    ]

    /// Keyed by path relative to `benchmarks/evidence`.
    static let shapes: [String: Shape] = [
        "issue-122-fluidaudio-ab.json": Shape(
            root: .object([
                "_what_this_is": .text,
                "_reproducing": .text,
                "store_note": .text,
                "session": .object([
                    "measured_at": .text, "machine": .text, "toolchain": .text,
                    "toolchain_caveat": .text, "corpus": .text,
                    "corpus_duration_seconds": .real(min: 0.001), "language": .text,
                    "audio_sha256": .hex(64), "reference_sha256": .hex(64),
                    "transcribe_command": .text, "nm_command": .text,
                    "notes": .array(of: .text, min: 4, distinct: true),
                ]),
                "arms": .object([
                    "0.15.4": armNode(), "0.15.5": armNode(),
                    "cross_pin_cmp": .text,
                    "_executable_hash_note": .text, "_nm_note": .text,
                ]),
                "metric": .object([
                    "kind": .text, "edits": .count(min: 0),
                    "reference_words": .count(min: 1),
                    "value": .real(min: 0),
                    "edit_list": .array(of: .text, min: 2, distinct: true), "_note": .text,
                ]),
                "path_coverage": pathCoverageNode(fluidAudioMeasurements),
            ]),
            measurements: Array(fluidAudioMeasurements.keys),
            laws: [
                equalCounts("calls split at the early return",
                            ["case_folded_calls"],
                            ["case_folded_early_return_ids_equal", "case_folded_reached_guard"]),
                equalCounts("the guard's two outcomes",
                            ["case_folded_reached_guard"],
                            ["case_folded_guard_else", "case_folded_both_ids_in_map"]),
                equalCounts("the guard's else, by cause",
                            ["case_folded_guard_else"],
                            ["case_folded_guard_else_map_nil", "case_folded_guard_else_id_absent"]),
                equalCounts("both ids present, by outcome",
                            ["case_folded_both_ids_in_map"],
                            ["case_folded_matches", "case_folded_canonicals_differed"]),
                // One merge joins each chunk after the first — stated exactly in
                // `merges`' own probe entry. It pins `chunks` and `merges` to
                // each other and nothing else: the ten `case_folded_*` counts
                // are joined to them by no relation, which is why a uniform
                // scaling of the census satisfies every law here and has to be
                // stopped in `observations` instead.
                Relation(label: "merges == chunks - 1") {
                    guard let c = int($0, "path_coverage.chunks"),
                        let m = int($0, "path_coverage.merges") else { return false }
                    // `Int.min - 1` traps, and a trap is not a failed
                    // expectation: it kills the process before any of the eight
                    // tests reports, so the reader is told a signal happened and
                    // nothing else. Two relations in this array were given the
                    // reporting form when that was found; this third one, above
                    // both of them, was missed.
                    let (want, overflow) = c.subtractingReportingOverflow(1)
                    return !overflow && m == want
                },
                // The metric's own note says the numerator and denominator are
                // recorded so the value can be re-derived. So re-derive it.
                Relation(label: "metric.value == edits / reference_words") {
                    guard let e = double($0, "metric.edits"),
                        let w = double($0, "metric.reference_words"), w > 0,
                        let v = double($0, "metric.value") else { return false }
                    return abs(v - e / w) < 1e-12
                },
                // The canonical id is what both matched ids resolve to, so it
                // has to be one of them.
                Relation(label: "case_folded_canonical_id is one of case_folded_matched_token_ids") {
                    guard let id = int($0, "path_coverage.case_folded_canonical_id"),
                        let pair = value($0, "path_coverage.case_folded_matched_token_ids") as? [NSNumber]
                    else { return false }
                    return pair.map(\.intValue).contains(id)
                },
                // The file records its own census, in prose, twice over.
                // `isolating_the_counterfactual` states the untagged and the
                // two-invocation-summed quadruples, and both are pure functions
                // of the recorded counts. Round 15's comment claimed no relation
                // could pin this census and that the information was not in the
                // file; it was, one line above, in the prose that same comment
                // disclaimed as unbound. Nothing here is hardcoded — the figures
                // are parsed out of what the file says and compared to arithmetic
                // on what the file records.
                Relation(label: "the counterfactual figures in prose match the census") {
                    guard let pc = $0["path_coverage"] as? [String: Any],
                        let how = pc["how"] as? [String: Any],
                        let text = how["isolating_the_counterfactual"] as? String,
                        let calls = int($0, "path_coverage.case_folded_calls"),
                        let early = int($0, "path_coverage.case_folded_early_return_ids_equal"),
                        let reached = int($0, "path_coverage.case_folded_reached_guard"),
                        let guardElse = int($0, "path_coverage.case_folded_guard_else")
                    else { return false }
                    let quad = #/(\d+)\s*/\s*\*{0,2}(\d+)\*{0,2}\s*/\s*\*{0,2}(\d+)\*{0,2}\s*/\s*\*{0,2}(\d+)\*{0,2}/#
                    let found = text.matches(of: quad).compactMap { m -> [Int]? in
                        guard let a = Int(m.1), let b = Int(m.2), let c = Int(m.3), let d = Int(m.4)
                        else { return nil }
                        return [a, b, c, d]
                    }
                    guard found.count == 2 else { return false }
                    // Every construction reports overflow. `sum` was given this
                    // treatment when it was reported; the relation written beside
                    // it in the same commit was not, and Int.max is a valid count,
                    // so it terminated the process instead of failing.
                    func twice(_ v: Int) -> Int? {
                        let (r, o) = v.multipliedReportingOverflow(by: 2)
                        return o ? nil : r
                    }
                    func plus(_ a: Int, _ b: Int) -> Int? {
                        let (r, o) = a.addingReportingOverflow(b)
                        return o ? nil : r
                    }
                    guard let c2 = twice(calls), let e2 = twice(early), let r2 = twice(reached),
                        let g2 = twice(guardElse), let mixed = plus(guardElse, reached)
                    else { return false }
                    return found[0] == [c2, e2, r2, mixed] && found[1] == [c2, e2, r2, g2]
                },
                // Seven probe entries quote the value of the field they describe.
                Relation(label: "each probe entry agrees with the figure it quotes") {
                    guard let pc = $0["path_coverage"] as? [String: Any],
                        let probes = (pc["how"] as? [String: Any])?["probes"] as? [String: String]
                    else { return false }
                    func n(_ k: String) -> Int? { (pc[k] as? NSNumber)?.intValue }
                    /// Containment with a digit boundary. Plain `contains` let
                    /// prose that had drifted to "agree at 7730" satisfy a seek
                    /// for "agree at 773".
                    func quotes(_ entry: String, _ phrase: String) -> Bool {
                        guard let text = probes[entry] else { return false }
                        return statesWholeNumber(text, phrase)
                    }
                    guard let reached = n("case_folded_reached_guard"),
                        let both = n("case_folded_both_ids_in_map"),
                        let matches = n("case_folded_matches"),
                        let canonical = n("case_folded_canonical_id"),
                        let mapNil = n("case_folded_guard_else_map_nil"),
                        let fallbacks = n("word_boundary_fallbacks_entered"),
                        let tokensEqual = pc["counterfactual_tokens_equal"] as? Bool
                    else { return false }
                    return quotes("case_folded_reached_guard", "agree at \(reached)")
                        && quotes("case_folded_both_ids_in_map", "agree at \(both)")
                        && quotes("case_folded_matched_token_ids", "there were \(matches) match events")
                        && quotes("case_folded_canonical_id", "gave \(canonical)")
                        && (!quotes("case_folded_guard_else_map_nil", "never nil") || mapNil == 0)
                        && (!quotes("word_boundary_fallbacks_entered", "each 0") || fallbacks == 0)
                        && (!quotes("counterfactual_tokens_equal", "recorded true") || tokensEqual)
                },
                // `_limits[1]` restates five of the same counts in prose. Left
                // unbound, the file could hold two mutually contradictory
                // censuses two keys apart and report nothing.
                Relation(label: "the census restated in `_limits` matches the recorded one") {
                    guard let pc = $0["path_coverage"] as? [String: Any],
                        let limits = pc["_limits"] as? [String], limits.count > 1
                    else { return false }
                    let text = limits[1]
                    func n(_ k: String) -> Int? { (pc[k] as? NSNumber)?.intValue }
                    func statesDigitBounded(_ v: Int) -> Bool {
                        statesWholeNumber(text, String(v))
                    }
                    guard let reached = n("case_folded_reached_guard"),
                        let both = n("case_folded_both_ids_in_map"),
                        let matches = n("case_folded_matches"),
                        let mapNil = n("case_folded_guard_else_map_nil"),
                        let guardElse = n("case_folded_guard_else")
                    else { return false }
                    return [reached, both, matches, mapNil, guardElse].allSatisfy(statesDigitBounded)
                },
                // The array records the pair emitted AT the fold match, so its
                // presence is itself a lower bound on the match count.
                Relation(label: "a recorded matched pair implies at least one match") {
                    guard let pc = $0["path_coverage"] as? [String: Any],
                        let pair = pc["case_folded_matched_token_ids"] as? [Any],
                        let matches = int($0, "path_coverage.case_folded_matches")
                    else { return false }
                    return pair.isEmpty || matches >= 1
                },
                // Each `edit_list` entry names its operations in parentheses --
                // "(substitution + insertion)" is two edits, "(substitution)" is
                // one -- so the numerator is derivable from the list rather than
                // merely bounded by its length. With `metric.value` pinned by
                // `_reproducing`, this pins the denominator too, which is what
                // rules out rescaling all three together.
                Relation(label: "metric.edits equals the operations edit_list names") {
                    guard let list = value($0, "metric.edit_list") as? [String],
                        let edits = int($0, "metric.edits") else { return false }
                    // Word-bounded: the unbounded form counted `nonsubstitution`.
                    let op = #/\b(substitution|insertion|deletion)\b/#
                    let named = list.reduce(0) { $0 + $1.lowercased().matches(of: op).count }
                    return named > 0 && named == edits
                },
                // `_reproducing` walks through three wrong artifact pairings and
                // ends "Only the combination above gives the recorded 0.0375".
                // The ratio law alone cannot see a rescaled metric or the
                // documented wrong answer, because 30/800 and 6/80 are both
                // internally consistent; the prose is what distinguishes them.
                Relation(label: "metric.value is the figure `_reproducing` calls the recorded one") {
                    guard let prose = $0["_reproducing"] as? String,
                        let recorded = double($0, "metric.value") else { return false }
                    let stated = #/gives the recorded ([0-9]+\.[0-9]+)/#
                    guard let m = prose.firstMatch(of: stated), let want = Double(m.1)
                    else { return false }
                    return abs(recorded - want) < 1e-12
                },
                // Different byte streams cannot hash alike. This is arithmetic,
                // not measurement: it needs no hashing, no transcription and no
                // external file. Unstated, every transcript digest could be set
                // to `reference_sha256` — which says the ASR output was
                // byte-identical to the reference, so the WER is 0, while
                // `metric.value` two keys away says 0.0375 and `edit_list` names
                // three edits.
                //
                // **It compares across arms, not within one.** The previous
                // version built its set per arm, and round 24 set arm 0.15.5's
                // two SRT digests to arm 0.15.4's `executable_sha256`: a
                // transcript that hashes like a compiled binary, with only an
                // *observation* firing. Cross-arm collisions were held entirely
                // by the editable class.
                //
                // What it compares is **kinds of artifact**, because that is what
                // the arithmetic is about. Collisions *within* a kind are
                // legitimate and are the A/B result itself: the two SRT runs are
                // the same command run twice, and both arms producing identical
                // transcripts is the finding this evidence records. Requiring
                // every digest to differ would have made this law contradict
                // three observations. An SRT and a TXT are different formats of
                // one transcription, so those must differ within an arm.
                //
                // `fluidaudio_revision` is deliberately not here. It is a git
                // revision — a name for a commit, not a digest of a byte stream
                // this run produced — and at 40 hex characters it could not
                // collide with a 64-character digest anyway. Naming the exclusion
                // beats a sentence claiming the list is complete.
                Relation(label: "no digest of one kind of artifact equals a digest of another kind") { json in
                    guard let audio = string(json, "session.audio_sha256"),
                        let reference = string(json, "session.reference_sha256"),
                        let arms = json["arms"] as? [String: Any]
                    else { return false }
                    let armed = arms.values.compactMap { $0 as? [String: Any] }
                    guard !armed.isEmpty else { return false }
                    var transcripts: Set<String> = []
                    var byFormat: [String: Set<String>] = [:]
                    var executables: [String] = []
                    for arm in armed {
                        guard let exe = arm["executable_sha256"] as? String else { return false }
                        executables.append(exe)
                        // Collected by key prefix, not by a list of four names.
                        // The list was maintained here and in `armNode()` with
                        // nothing keeping the two in step, so a fifth digest
                        // field joined the schema without joining the law.
                        let recorded = arm.compactMap { key, value -> (String, String)? in
                            guard key.hasPrefix(transcriptPrefix), let s = value as? String
                            else { return nil }
                            return (String(key.dropFirst(transcriptPrefix.count)), s)
                        }
                        guard !recorded.isEmpty else { return false }
                        for (suffix, digest) in recorded {
                            transcripts.insert(digest)
                            let format = String(suffix.split(separator: "_").first ?? "")
                            byFormat[format, default: []].insert(digest)
                        }
                    }
                    // Two builds of two different pins are two byte streams. This
                    // was an observation, and it is not one an honest re-run
                    // rewrites — differing executables is true of every correct
                    // recording of an A/B, which is the tell that it is a law.
                    // A dependency bump that changed no emitted byte would trip
                    // it, and tripping is right: the comparison would be vacuous.
                    guard Set(executables).count == executables.count else { return false }
                    // One format is not another — **across arms**, not merely
                    // within one. This guard used to sit inside the loop above,
                    // which is the same per-arm mistake the kind partition was
                    // hoisted out of, left standing one level in: arm B's `.txt`
                    // could be byte-identical to arm A's `.srt`, timestamp blocks
                    // and all, with only two observations objecting.
                    let formats = Array(byFormat.values)
                    for (i, a) in formats.enumerated() {
                        for b in formats[(i + 1)...] where !a.isDisjoint(with: b) { return false }
                    }
                    // These are `Set<String>` comparisons, not digest
                    // comparisons: the same digest written in uppercase or with a
                    // fullwidth digit reads as a second byte stream here. What
                    // makes that sound is `.hex(64)`, which rejects both before
                    // this relation runs — a dependency worth naming, since the
                    // label reads as if it compared digests.
                    let kinds: [Set<String>] = [[audio], [reference], transcripts, Set(executables)]
                    for (i, a) in kinds.enumerated() {
                        for b in kinds[(i + 1)...] where !a.isDisjoint(with: b) { return false }
                    }
                    return true
                },
                // `metric.kind` names what every other figure in the block
                // means. Pinned to the literal `"wer"` it was still free of
                // everything around it: `session.language: "zh"` passed, and a
                // CER is what this package computes for Chinese. So ask the
                // shipped resolver — the code under test, not a regex over
                // prose, and the only anchor here that cannot be edited into
                // agreement without changing behaviour.
                Relation(label: "metric.kind is the kind `LanguageResolver` picks for `session.language`") {
                    guard let language = string($0, "session.language") else { return false }
                    return string($0, "metric.kind")
                        == LanguageResolver.metricKind(forLanguage: language).rawValue
                },
                // **The two recorded commands are unchecked prose.** There is no
                // relation here that reads them, and that is deliberate.
                //
                // Three rounds tried. Round 22 wrote `contains`, and round 23
                // walked through it four ways: `--language en` is a substring of
                // `--language english`, `--language z` of `--language zh`,
                // `caseVariantCanonicalIds` of `…LegacyShim`, and a symbol named
                // in a trailing `#` comment answered for the one being counted.
                // Round 23 replaced that with a token comparison, and round 24
                // walked through *that*: `grep -v caseVariantCanonicalIds |
                // grep -c tokenIdsMatch` passed, because the symbol was present —
                // in a **negating** position; `grep -cv` passed and inverted the
                // whole A/B conclusion; `--language en --language zh` passed
                // while argument parsing takes the last; and a `#` mid-word cut a
                // token the shell would not have cut.
                //
                // Each fix moved one step closer to the claim and left a gap one
                // step further out, because the claim — *this command produced
                // these numbers* — is about **what a program does with a string**
                // while every check was about **what is in the string**. A fourth
                // hand-rolled shell-adjacent parser would not close that.
                //
                // And it does not need to. Both commands restate facts the file
                // already carries as *data*: the language is `session.language`,
                // and the symbol is literally a field name,
                // `nm_caseVariantCanonicalIds`. The commands add no information a
                // rule can use — they document how the fields were obtained. So
                // they join the rest of the narrative fields, which this file has
                // always declared unchecked.
                //
                // **The other half of that sentence, which the round-24 version
                // left out.** "Restates a fact the file carries as data" also
                // means the restatement can now *diverge* from the data:
                // `--language en` sits beside `session.language: "en"`, which is
                // pinned, and a one-sided edit leaves the file internally
                // contradictory with nothing to notice. Measured in round 25 —
                // the command may say `zh`, name a different backend, or count a
                // different symbol, and every test passes. Two further sentences
                // in the evidence file lean on these strings and are likewise
                // unchecked: `isolating_the_counterfactual` says the census is
                // "per invocation of `session.transcribe_command`", and
                // `_nm_note` narrates the table the `nm` command produced. Binding them would need the run to
                // record `language` and `counted_symbol` as fields and let the
                // command be prose, which is a change to the evidence schema, not
                // to this test.
                // The conclusion follows from its two comparisons.
                Relation(label: "changed_merge_output == !(tokens_equal && timestamps_equal)") {
                    guard let t = value($0, "path_coverage.counterfactual_tokens_equal") as? Bool,
                        let s = value($0, "path_coverage.counterfactual_timestamps_equal") as? Bool,
                        let c = value($0, "path_coverage.case_folded_changed_merge_output") as? Bool
                    else { return false }
                    return c == !(t && s)
                },
            ],
            observations: measuredCensus + [
                // The corpus, against the literals a reviewer read out of
                // `scripts/fetch-corpora.sh`. These were laws while a regex
                // derived them; a literal cannot be a law, because "this file
                // names osr-harvard-1" is not true of any correct recording —
                // only of a recording on this corpus. Declaring them here says
                // the right thing about them and puts re-pinning where it
                // belongs: an edit to the declaration, on purpose.
                Relation(label: "session.corpus is the reviewed corpus name") {
                    string($0, "session.corpus") == reviewedCorpus.name
                },
                Relation(label: "session.audio_sha256 is the reviewed WAV digest") {
                    string($0, "session.audio_sha256") == reviewedCorpus.audio
                },
                Relation(label: "session.reference_sha256 is the reviewed reference digest") {
                    string($0, "session.reference_sha256") == reviewedCorpus.reference
                },
                // `session.language` became load-bearing the moment `metric.kind`
                // was derived from it, and nothing pinned it. That derivation
                // constrains the *pair* and neither member: `language: "zh"` with
                // `kind: "cer"` and `--language zh` satisfied every rule, and the
                // file then said the English Harvard sentences were transcribed
                // as Chinese and scored with a character error rate, beside
                // `reference_words: 80` and an `edit_list` of English word
                // substitutions. The corpus is English; that is a fact about
                // this recording, so it is declared like one.
                Relation(label: "session.language is the reviewed corpus language") {
                    string($0, "session.language") == reviewedCorpus.language
                },
                Relation(label: "collapse was called in this run") {
                    ($0["path_coverage"] as? [String: Any])?["collapse_called"] as? Bool == true
                },
                Relation(label: "collapse removed no token in this run") {
                    // Bound before comparing. `Optional == Optional` is true when
                    // both sides are nil, so an unguarded comparison of two
                    // accessors is satisfied by deleting both fields.
                    guard let a = int($0, "path_coverage.collapse_tokens_in"),
                        let b = int($0, "path_coverage.collapse_tokens_out") else { return false }
                    return a == b
                },
                Relation(label: "the fold matched on the pair [375, 518] in this run") {
                    guard let ids = value($0, "path_coverage.case_folded_matched_token_ids") as? [Any]
                    else { return false }
                    return ids.compactMap { ($0 as? NSNumber)?.intValue } == [375, 518]
                },
                Relation(label: "supplying the case-variant ids changed neither tokens nor timestamps") { json in
                    // The file's verdict. The only law touching these three
                    // derives one from the other two, which constrains them
                    // relative to each other and pins none: flipping
                    // `timestamps_equal` and the conclusion together satisfied it
                    // and inverted what the file concludes, while `arms` three
                    // keys away went on recording byte-identical SRT — and SRT
                    // carries timestamps.
                    let want = ["counterfactual_tokens_equal": true,
                                "counterfactual_timestamps_equal": true,
                                "case_folded_changed_merge_output": false]
                    return want.allSatisfy { field, expected in
                        value(json, "path_coverage." + field) as? Bool == expected
                    }
                },
                Relation(label: "the corpus was 33.623125 seconds long in this run") {
                    // `.real(min: 0.001)` was the only constraint, and nothing
                    // relates duration to the 3 chunks, 154 seam tokens or 80
                    // reference words recorded elsewhere — so one millisecond of
                    // audio yielding all three passed.
                    guard let d = double($0, "session.corpus_duration_seconds") else { return false }
                    return abs(d - 33.623125) < 1e-9
                },
                Relation(label: "the metric was 3 edits over 80 reference words in this run") {
                    // `value` is pinned by `_reproducing` and derived from these
                    // two, so the pair was free to scale: 6/160 is also 0.0375,
                    // and the operation count that was supposed to pin the
                    // numerator is read out of prose the same edit rewrites.
                    int($0, "metric.edits") == 3 && int($0, "metric.reference_words") == 80
                },
            ] + armObservations),
    ]

    /// The census as measured, one relation per field.
    ///
    /// The four sum identities are **homogeneous** — `both = matches + differed`
    /// holds at (2, 131) and at (133, 0); `reached = guard_else + both` holds at
    /// ×1 and at ×2 — so they constrain ratios and not magnitudes. The prose
    /// anchors added in rounds 17 to 19 anchor the same ratios (each recorded
    /// quadruple is exactly twice the counts), so three rounds of hardening
    /// landed inside one null space: a uniformly doubled census passed, and so
    /// did one that moved all 133 eligible calls into `matches`, which reverses
    /// what the file says about how often the new path decides anything.
    ///
    /// No relation internal to the file can separate a scaled or reallocated
    /// census from an honest one. That is what `observations` is for, and what
    /// `arms` has always done for the nm counts.
    private static let measuredCensus: [Relation] = ([
        "chunks": 3, "merges": 2,
        "case_folded_calls": 844,
        "case_folded_early_return_ids_equal": 71,
        "case_folded_reached_guard": 773,
        "case_folded_guard_else": 640,
        "case_folded_guard_else_map_nil": 0,
        "case_folded_guard_else_id_absent": 640,
        "case_folded_both_ids_in_map": 133,
        "case_folded_canonicals_differed": 131,
        "case_folded_matches": 2,
        "case_folded_canonical_id": 375,
        "collapse_tokens_in": 154, "collapse_tokens_out": 154,
        "word_boundary_fallbacks_entered": 0,
    ] as [String: Int]).sorted { $0.key < $1.key }.map { field, measured in
        Relation(label: "`\(field)` was measured as \(measured) in this run") {
            int($0, "path_coverage." + field) == measured
        }
    }

    /// `arms` keys contain dots, which the dotted-path accessor cannot address,
    /// so the arm relations are written directly.
    ///
    /// These belong to the FluidAudio A/B shape and are spliced into its
    /// `observations`. They used to be applied to every file in the directory,
    /// which would have failed all of them the moment a second evidence file for
    /// a different issue appeared.
    private static let armObservations: [Relation] = [
        Relation(label: "the srt transcripts are identical across arms") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = arms["0.15.4"] as? [String: Any], let b = arms["0.15.5"] as? [String: Any]
            else { return false }
            guard let x = a["transcript_sha256_srt_run1"] as? String,
                let y = b["transcript_sha256_srt_run1"] as? String else { return false }
            return x == y
        },
        Relation(label: "the txt transcripts are identical across arms") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = arms["0.15.4"] as? [String: Any], let b = arms["0.15.5"] as? [String: Any]
            else { return false }
            guard let x = a["transcript_sha256_txt"] as? String,
                let y = b["transcript_sha256_txt"] as? String else { return false }
            return x == y
        },
        Relation(label: "run 1 and run 2 agree within each arm") { json in
            guard let arms = json["arms"] as? [String: Any] else { return false }
            return ["0.15.4", "0.15.5"].allSatisfy { name in
                guard let arm = arms[name] as? [String: Any],
                    let one = arm["transcript_sha256_srt_run1"] as? String,
                    let two = arm["transcript_sha256_srt_run2"] as? String else { return false }
                return one == two
            }
        },
        // What must DIFFER. The previous set declared only what must match, so
        // both arms could carry the same revision and the same executable hash —
        // one binary measured twice — while reporting nm counts of 0 and 4. That
        // is the premise of the whole comparison, and it was unchecked.
        Relation(label: "the two arms are different builds of different pins") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = arms["0.15.4"] as? [String: Any], let b = arms["0.15.5"] as? [String: Any],
                let revA = a["fluidaudio_revision"] as? String,
                let revB = b["fluidaudio_revision"] as? String,
                let exeA = a["executable_sha256"] as? String,
                let exeB = b["executable_sha256"] as? String
            else { return false }
            return revA != revB && exeA != exeB
        },
        // …and which arm is which. Differing from each other left the labels
        // free: the two revisions could be exchanged, so the arm named for the
        // pin under test carried the revision of the pin it is being compared
        // against. The arm whose key is the version `Package.resolved` pins must
        // carry the revision it pins; the other must not. If the package is ever
        // bumped past both arms this fails, which is correct — the evidence then
        // describes a dependency the repo no longer builds against.
        //
        // This binds **one** arm. `Package.resolved` records the current pin and
        // nothing else, so the baseline arm is pinned separately below — the
        // label used to say "each arm" and claim both.
        Relation(label: "the arm under test carries the revision `Package.resolved` records") { json in
            guard let pin = pinnedFluidAudio,
                let arms = json["arms"] as? [String: Any],
                let underTest = arms[pin.version] as? [String: Any],
                underTest["fluidaudio_revision"] as? String == pin.revision
            else { return false }
            let others = arms.compactMap { key, value -> String? in
                guard key != pin.version, let arm = value as? [String: Any] else { return nil }
                return arm["fluidaudio_revision"] as? String
            }
            return !others.isEmpty && others.allSatisfy { $0 != pin.revision }
        },
        // The baseline arm, which `Package.resolved` cannot speak for. Left to
        // "differs from the other arm", it accepted any forty hex characters —
        // so the file could claim an A/B against 0.15.4 while naming a commit
        // that does not exist. This is the upstream `v0.15.4` tag, confirmed in
        // round 20 with `git ls-remote --tags` against FluidInference/FluidAudio.
        Relation(label: "the baseline arm carries the upstream v0.15.4 tag revision") { json in
            guard let arms = json["arms"] as? [String: Any],
                let baseline = arms["0.15.4"] as? [String: Any]
            else { return false }
            return baseline["fluidaudio_revision"] as? String
                == "b9d43724cbdb5a980e441fd54180964e94d470f7"
        },
        Relation(label: "the nm counts differ between arms — the A/B result itself") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = (arms["0.15.4"] as? [String: Any])?["nm_caseVariantCanonicalIds"] as? NSNumber,
                let b = (arms["0.15.5"] as? [String: Any])?["nm_caseVariantCanonicalIds"] as? NSNumber
            else { return false }
            // The magnitude, not just the sign. `> 0` let the count that carries
            // the whole A/B claim drift to any positive value while `_nm_note`
            // two keys away went on stating the measured cell.
            return a.intValue == 0 && b.intValue == 4
        },
    ]

    // MARK: - Loading

    private struct Evidence {
        let path: String
        let json: [String: Any]
        let text: String
        let strings: [String]
        let allKeys: Set<String>
    }

    /// Object keys that appear twice in the same object, found by scanning the
    /// text. `JSONSerialization` keeps one and discards the fact — and it keeps
    /// the *first*, while `jq`, `python3` and `node` all keep the last. A file
    /// with two `metric` blocks therefore validates here and reports a
    /// different error rate to every other consumer.
    static func duplicateKeys(in json: String) -> [String] {
        var duplicates: [String] = []
        var stack: [(isObject: Bool, keys: Set<String>)] = []
        let chars = Array(json.unicodeScalars)
        var i = 0

        /// Decodes JSON escapes, so `"\u0061"` and `"a"` are recognised as the
        /// same key and `"\/"` and `"\\"` as different ones. The previous
        /// version replaced every escape with a single `?`, which both missed
        /// real duplicates and invented false ones.
        func readString() -> String {
            var out = String.UnicodeScalarView()
            i += 1  // opening quote
            while i < chars.count {
                let c = chars[i]
                if c == "\\" {
                    i += 1
                    guard i < chars.count else { break }
                    switch chars[i] {
                    case "u":
                        let hex = String(String.UnicodeScalarView(chars[(i + 1)..<Swift.min(i + 5, chars.count)]))
                        i += 4
                        if var code = UInt32(hex, radix: 16) {
                            // A high surrogate takes the following \uXXXX with it.
                            if (0xD800...0xDBFF).contains(code), i + 6 < chars.count,
                                chars[i + 1] == "\\", chars[i + 2] == "u",
                                let low = UInt32(
                                    String(String.UnicodeScalarView(chars[(i + 3)..<Swift.min(i + 7, chars.count)])),
                                    radix: 16),
                                (0xDC00...0xDFFF).contains(low)
                            {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                i += 6
                            }
                            if let scalar = Unicode.Scalar(code) { out.append(scalar) }
                        }
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    default: out.append(chars[i])  // covers \" \\ \/
                    }
                    i += 1
                    continue
                }
                if c == "\"" { i += 1; return String(out) }
                out.append(c)
                i += 1
            }
            return String(out)
        }

        while i < chars.count {
            switch chars[i] {
            case "{": stack.append((isObject: true, keys: [])); i += 1
            case "[": stack.append((isObject: false, keys: [])); i += 1
            case "}", "]": if !stack.isEmpty { stack.removeLast() }; i += 1
            case "\"":
                let s = readString()
                // A string is a key when the next character — skipping all four
                // JSON whitespace characters, carriage return included — is a
                // colon, and the enclosing container is an object.
                var j = i
                while j < chars.count,
                    chars[j] == " " || chars[j] == "\n" || chars[j] == "\r" || chars[j] == "\t"
                { j += 1 }
                if j < chars.count, chars[j] == ":", let top = stack.last, top.isObject {
                    if stack[stack.count - 1].keys.contains(s) { duplicates.append(s) }
                    stack[stack.count - 1].keys.insert(s)
                }
            default: i += 1
            }
        }
        return duplicates.sorted()
    }

    /// Every entry under the directory. Non-regular entries are reported, not
    /// skipped: a symlink to a second, contradictory evidence file used to be
    /// invisible while the failure message claimed the directory held evidence
    /// and nothing else.
    private static func evidenceFiles() throws -> [Evidence] {
        let root = evidenceDirectory.standardizedFileURL
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.producesRelativePathURLs])
        var found: [Evidence] = []
        var unusable: [String] = []

        for case let url as URL in enumerator ?? .init() {
            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: root.path + "/", with: "")
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { unusable.append("\(relative) (not a regular file)"); continue }
            guard let data = try? Data(contentsOf: url),
                let text = String(data: data, encoding: .utf8),
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { unusable.append("\(relative) (not a JSON object)"); continue }

            var strings: [String] = []
            var keys = Set<String>()
            func walk(_ node: Any) {
                switch node {
                case let d as [String: Any]: for (k, v) in d { keys.insert(k); walk(v) }
                case let a as [Any]: a.forEach(walk)
                case let s as String: strings.append(s)
                default: break
                }
            }
            walk(json)
            found.append(
                Evidence(path: relative, json: json, text: text, strings: strings, allKeys: keys))
        }

        #expect(
            unusable.isEmpty,
            "\(evidenceDirectory.path) holds \(unusable.sorted()). This directory holds evidence and nothing else — a symlink or pipe here is invisible to every rule below.")
        #expect(!found.isEmpty, "no evidence files — every test here would pass vacuously")
        return found.sorted { $0.path < $1.path }
    }

    /// The declared shape for one file, or `nil` after reporting that there is
    /// none.
    ///
    /// This used to `try #require`, which throws — and the loops below iterate
    /// files in sorted order, so **one undeclared file aborted the whole test
    /// before any law ran**. Round 23 measured it: an empty `aaa-decoy.json`
    /// beside a falsified `session.corpus` reported three "has no entry in
    /// `shapes`" issues and *not* the corpus failure. The suite was red, so
    /// nothing false was certified — but "red" and "the laws ran" are different
    /// facts, and a reader had no way to tell them apart. Report and skip, so
    /// every other file is still checked.
    private static func shape(for e: Evidence) -> Shape? {
        let shape = shapes[e.path]
        #expect(
            shape != nil,
            "\(e.path) has no entry in `shapes`. Every evidence file must declare its shape here — the other files were still checked.")
        return shape
    }

    // MARK: - Matching a value against a declared node

    /// What counts as a character that renders. An **allowlist**: round 16
    /// showed a denylist cannot work, because Unicode's default-ignorable set is
    /// far larger than any enumeration of it — U+200C, U+200D, U+034F, U+FEFF,
    /// the directional isolates, variation selectors and tag characters all got
    /// through the previous list while rendering as nothing.
    /// Neither a denylist nor a category allowlist is sound on its own, so this
    /// is both. Round 16 replaced a denylist with an allowlist of general
    /// categories; the allowlist then re-admitted two scalars the denylist had
    /// caught — U+3164 HANGUL FILLER (`Lo`, so `alphanumerics`) and U+2800
    /// BRAILLE PATTERN BLANK (`So`, so `symbols`) — along with three more
    /// Hangul fillers: U+115F, U+1160 and U+FFA0, four in all with U+3164. General category is not a renderability predicate, and no
    /// predicate in Foundation is. **This is a floor, not a test for
    /// legibility**: it rejects the blank-rendering scalars that have actually
    /// been found, and a scalar nobody has thought of will pass.
    private static let knownBlank = CharacterSet(charactersIn:
        "\u{115F}\u{1160}\u{3164}\u{FFA0}\u{2800}\u{180E}\u{200B}\u{FEFF}\u{FFFC}\u{1D159}")
    private static let visible = CharacterSet.alphanumerics
        .union(.punctuationCharacters).union(.symbols)
        .subtracting(.nonBaseCharacters)
        .subtracting(knownBlank)

    /// What a reader sees, for the purpose of telling two strings apart. Every
    /// distinctness rule must go through this: `.array` already did, and the
    /// probe-method rule added beside it compared raw `String`s, so two methods
    /// differing only by a trailing space or a U+200B counted as two.
    static func rendered(_ s: String) -> String {
        String(String(s).unicodeScalars.filter { visible.contains($0) })
    }

    /// What `statesWholeNumber` reads: the text with everything that renders as
    /// nothing removed, then folded to NFKC.
    ///
    /// Unlike `rendered()` this keeps whitespace and letters, because the
    /// anchors match phrases (`agree at 773`) and not just figures. It removes
    /// the three families that let a character hide between a sign and its
    /// digits: `knownBlank`, the format scalars (U+200E, U+2060, U+00AD), and
    /// the combining marks, which also collapses a decorated dash back to a
    /// dash so `isSign` can see it.
    ///
    /// **Whitespace survives, and the exception is load-bearing.**
    /// `CharacterSet.controlCharacters` is `Cc` *and* `Cf`, so filtering it
    /// wholesale deletes newlines and tabs — and deleting a newline joins the
    /// words on either side of it. Measured both ways: a `_limits` entry
    /// reformatted to wrap between `773` and `133` reads as `773133`, and the
    /// census law fails on an honest line break (`rc=1`); with this line it
    /// passes. No field the anchors read carries a newline today, which is
    /// exactly why it would have been found late.
    static func normalisedForAnchoring(_ s: String) -> String {
        let stripped = String(s.unicodeScalars.filter {
            if $0.properties.isWhitespace { return true }
            return !knownBlank.contains($0)
                && !CharacterSet.controlCharacters.contains($0)
                && !CharacterSet.nonBaseCharacters.contains($0)
        })
        return stripped.precomposedStringWithCompatibilityMapping
    }

    static func mismatches(_ value: Any?, against node: Node, at path: String) -> [String] {
        func plain(_ v: Any?) -> NSNumber? {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            return n
        }
        let here = path.isEmpty ? "(root)" : path
        switch node {
        case .object(let declared):
            guard let actual = value as? [String: Any] else { return ["\(here): not an object"] }
            var out: [String] = []
            let missing = Set(declared.keys).subtracting(actual.keys).sorted()
            let undeclared = Set(actual.keys).subtracting(declared.keys).sorted()
            if !missing.isEmpty { out.append("\(here): missing \(missing)") }
            if !undeclared.isEmpty { out.append("\(here): undeclared \(undeclared)") }
            for (key, child) in declared.sorted(by: { $0.key < $1.key }) where actual[key] != nil {
                out += mismatches(actual[key], against: child, at: path.isEmpty ? key : "\(path).\(key)")
            }
            return out
        case .text:
            guard let s = value as? String else { return ["\(here): not a string"] }
            return s.unicodeScalars.contains(where: { visible.contains($0) })
                ? [] : ["\(here): no visible characters"]
        case .hex(let length):
            guard let s = value as? String else { return ["\(here): not a string"] }
            // ASCII scalars, not `Character.isHexDigit` — that is Unicode, so
            // the fullwidth compatibility forms qualify and 40 copies of U+FF41
            // passed as a git revision.
            let scalars = Array(s.unicodeScalars)
            guard scalars.count == length,
                scalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) })
            else { return ["\(here): not \(length) ASCII lowercase hex digits"] }
            return []
        case .count(let min):
            guard let n = plain(value) else { return ["\(here): not a number"] }
            // The token has to have been written as an integer. Checking only
            // `doubleValue == Double(intValue)` accepts 0.99999999999999999,
            // which the parser rounds to 1.0 before any rule sees it.
            guard !CFNumberIsFloatType(n) else { return ["\(here): \(n) was written as a real, not a count"] }
            return n.intValue >= min ? [] : ["\(here): \(n) is below the declared minimum \(min)"]
        case .real(let min):
            guard let n = plain(value) else { return ["\(here): not a number"] }
            guard n.doubleValue.isFinite else { return ["\(here): not finite"] }
            return n.doubleValue >= min ? [] : ["\(here): \(n) is below the declared minimum \(min)"]
        case .flag:
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
                return ["\(here): not a boolean — 1 and 0 bridge to Bool and would pass silently"]
            }
            return []
        case .array(let element, let min, let distinct):
            guard let a = value as? [Any] else { return ["\(here): not an array"] }
            var out: [String] = []
            if a.count < min { out.append("\(here): has \(a.count) element(s), needs \(min)") }
            if distinct {
                // Compare what renders. A trailing space or a zero-width
                // character made five copies of one sentence "distinct".
                let rendered = a.map { Self.rendered(String(describing: $0)) }
                if Set(rendered).count != rendered.count {
                    out.append("\(here): has elements that render identically, so its length overstates its content")
                }
            }
            return out + a.enumerated().flatMap { mismatches($1, against: element, at: "\(here)[\($0)]") }
        }
    }

    // MARK: - Text helpers

    /// Does `text` contain `needle` as a complete numeric token — nothing
    /// numeric continuing it on **either** side?
    ///
    /// Four constructions defeated weaker forms of this, in order: plain
    /// `contains`, so prose that had drifted to `773` inside `7730` still
    /// matched; an after-only digit check, which left the mirror image open the
    /// moment any anchor began with its figure; a digit-only check on both
    /// sides, which read `773,000` and `773.5` as the recorded `773` because a
    /// comma and a period are not digits; and then — in the very helper written
    /// to end that — a separator check on the trailing side only, so `1,773`
    /// satisfied a seek for `773`. Each fix had closed the examples it was given
    /// and left their mirror image standing.
    static func statesWholeNumber(_ rawText: String, _ rawNeedle: String) -> Bool {
        // Normalise both sides before looking at anything. Two escape routes
        // closed here are structural rather than another missing scalar:
        //
        // - **An invisible between the sign and the digit.** `(-<U+200E>773)`
        //   passed every version of this helper, because the check reads exactly
        //   *one* character and that character was a left-to-right mark. No list
        //   of signs closes that. Stripping what renders as nothing does, and
        //   this file already knew which scalars those are — `knownBlank` holds
        //   U+200B, and `rendered()` has gone through it since round 16. This
        //   helper was the one place that read raw text.
        // - **Compatibility spellings.** NFKC folds U+207B and U+208B to U+2212
        //   and U+FF0D to `-`, so three of round 25's escapes need no rule at
        //   all after this line.
        //
        // `rendered()` itself is the wrong tool — it drops spaces, so
        // `agree at 773` becomes `agreeat773` and word boundaries vanish. This
        // removes only what is invisible.
        let text = normalisedForAnchoring(rawText)
        let needle = normalisedForAnchoring(rawNeedle)
        /// A **minus**. `Pd` and U+2212 cover it after normalisation; the two
        /// stragglers are named because they have no compatibility mapping.
        ///
        /// **This list is not closed, and that is now stated rather than
        /// claimed away.** Round 23 enumerated four dashes and round 24 found
        /// three more; round 24 asked Unicode for `Pd` and round 25 found three
        /// spellings in *other* categories. `Sm` cannot be taken wholesale —
        /// `=773` and `<773` state 773 — so what is left is a list, and lists of
        /// this kind have been falsified in three consecutive rounds. Read the
        /// scope note above `statesWholeNumber` for what that means: this is a
        /// detector for a figure that has gone **stale**, not for one somebody
        /// is hiding.
        ///
        /// `+` is deliberately not a sign: `+773` **is** 773, and rejecting it
        /// was the mirror of the bug this helper exists to fix. `133+640` — a
        /// `+` that is arithmetic — is handled by `runsOn`, because a digit
        /// sits before it.
        ///
        /// One residual is named rather than left to be rediscovered: U+30FC
        /// KATAKANA-HIRAGANA PROLONGED SOUND MARK renders as a dash and Unicode
        /// calls it a **letter** (`Lm`), so `ー773` passes both this and
        /// `runsOn`. Admitting it would mean treating a letter as a sign. It is
        /// the shape of thing this helper cannot decide, and the scope note says
        /// so.
        func isSign(_ c: Character) -> Bool {
            guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return false }
            if s.properties.generalCategory == .dashPunctuation { return true }
            return s == "\u{2212}"  // MINUS SIGN
                || s == "\u{2052}"  // COMMERCIAL MINUS SIGN — `Sm`, no NFKC mapping
                || s == "\u{2796}"  // HEAVY MINUS SIGN — `So`, no NFKC mapping
        }
        /// A group or decimal separator, which continues a number only when a
        /// digit sits on its far side.
        ///
        /// `Zs` is the class; the rest are the `Po` spellings found so far, and
        /// that list is open for the same reason as the signs. U+066B was the
        /// sharpest miss: U+066**C**, the Arabic *thousands* separator, was
        /// listed and its immediate sibling the *decimal* separator was not.
        ///
        /// **A known cost, chosen deliberately.** `Zs` includes the ordinary
        /// space, and `1 773` (one grouped number) is typographically identical
        /// to `3 640` (two numbers) — so prose like *"across the 3 640-call
        /// chunks"* now fails this anchor although both figures are honest. The
        /// alternative is letting `1 773` satisfy a seek for `773`. Neither
        /// error is refinable away; a loud false alarm with a diagnostic beats a
        /// silent false pass, so the space stays in.
        func isSeparator(_ c: Character) -> Bool {
            if c == "," || c == "." || c == "'" || c == "\u{00B7}"  // MIDDLE DOT
                || c == "\u{066B}" || c == "\u{066C}"  // ARABIC DECIMAL / THOUSANDS
                || c == "\u{2019}" || c == "\u{2044}"  // apostrophe (Swiss), FRACTION SLASH
            { return true }
            guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return false }
            return s.properties.generalCategory == .spaceSeparator
        }
        /// Is the character before `i` one a word or a number runs into? `-` is
        /// three characters at once — a sign, a hyphen and a subtraction
        /// operator — and only the first makes a different number.
        func runsOn(_ i: String.Index) -> Bool {
            guard i > text.startIndex else { return false }
            let p = text[text.index(before: i)]
            return p.isLetter || p.isNumber || p == "_"
        }
        for range in text.ranges(of: needle) {
            if range.lowerBound > text.startIndex {
                let i = text.index(before: range.lowerBound)
                let before = text[i]
                if before.isNumber { continue }
                // Reading every `-` as a sign rejected `guard-773`, `re-773`,
                // the range `770-780` and the unspaced arithmetic `773-640`,
                // `133+640` — which is precisely what someone restating
                // `_limits[1]` writes. A sign is a sign only where a word or a
                // digit does not run into it; `-773`, ` -773` and `(−773)` are
                // still a different number and still rejected.
                if isSign(before), !runsOn(i) { continue }
                if isSeparator(before), i > text.startIndex,
                    text[text.index(before: i)].isNumber { continue }
            }
            if range.upperBound < text.endIndex {
                let j = range.upperBound
                let after = text[j]
                if after.isNumber { continue }
                if isSeparator(after) {
                    let k = text.index(after: j)
                    if k < text.endIndex, text[k].isNumber { continue }
                }
            }
            return true
        }
        return false
    }

    private static let backtickSpan = #/`([^`]+)`/#

    private static func backtickedTokens(in text: String) -> Set<String> {
        var found = Set<String>()
        for match in text.matches(of: backtickSpan) {
            for token in String(match.1)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            { found.insert(String(token)) }
        }
        return found
    }

    private static func fieldNames(in text: String) -> Set<String> {
        backtickedTokens(in: text).filter {
            $0.contains("_") && !$0.hasPrefix("__") && !$0.contains(where: \.isUppercase)
        }
    }

    private static func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    // MARK: - 1. The file has the declared shape and magnitudes

    @Test func `every evidence file matches its declared shape`() throws {
        let files = try Self.evidenceFiles()
        let onDisk = Set(files.map { $0.path })
        for declared in Self.shapes.keys {
            #expect(onDisk.contains(declared), "`shapes` declares \(declared), which is not on disk")
        }
        for e in files {
            guard let shape = Self.shape(for: e) else { continue }
            let problems = Self.mismatches(e.json, against: shape.root, at: "")
            #expect(
                problems.isEmpty,
                "\(e.path) does not match its declaration:\n  \(problems.joined(separator: "\n  "))")
        }
    }

    /// A duplicated key makes the file mean one thing here and another
    /// everywhere else, and `JSONSerialization` hides the fact before any other
    /// rule can see it.
    @Test func `no object declares the same key twice`() throws {
        for e in try Self.evidenceFiles() {
            let dupes = Self.duplicateKeys(in: e.text)
            #expect(
                dupes.isEmpty,
                """
                \(e.path) declares \(dupes) twice in one object. Foundation keeps the first; \
                jq, python3 and node all keep the last, so this file means different things \
                to this suite and to every other reader of it.
                """)
        }
    }

    // MARK: - 2. No dangling field name

    @Test func `every backticked field name resolves to a key`() throws {
        for e in try Self.evidenceFiles() {
            var dangling = Set<String>()
            for text in e.strings {
                dangling.formUnion(Self.fieldNames(in: text).subtracting(e.allKeys))
            }
            #expect(dangling.isEmpty, "\(e.path) names field(s) that do not exist: \(dangling.sorted())")
        }
    }

    /// A probe entry may cite a declared `path_coverage` name, a declared `how`
    /// key, a source symbol or an ordinary word — but not a key belonging to
    /// another block. Two thirds of the scope come from the declaration — the
    /// census measurements and the declared `how` keys — and the third part is
    /// the literal `["path_coverage", "_limits"]` below, the two names the
    /// block calls itself by.
    @Test func `probe entries cite only declared path_coverage names`() throws {
        for e in try Self.evidenceFiles() {
            guard let shape = Self.shape(for: e) else { continue }
            guard case .object(let root) = shape.root,
                case .object(let pc)? = root["path_coverage"],
                case .object(let howDeclared)? = pc["how"],
                let probes = ((e.json["path_coverage"] as? [String: Any])?["how"]
                    as? [String: Any])?["probes"] as? [String: String]
            else { continue }
            let inScope = Set(shape.measurements).union(howDeclared.keys)
                .union(["path_coverage", "_limits"])

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                let foreign = Self.backtickedTokens(in: method)
                    .intersection(e.allKeys).subtracting(inScope).sorted()
                #expect(
                    foreign.isEmpty,
                    "\(e.path): how.probes[\(field)] sources its value from \(foreign), which belong to another block")
            }
        }
    }

    // MARK: - 3. Underscored key names in prose are backticked

    @Test func `underscored key names in prose are written in backticks`() throws {
        for e in try Self.evidenceFiles() {
            let names = e.allKeys.filter { $0.contains("_") && !$0.hasPrefix("_") }
            var bare: Set<String> = []
            for text in e.strings {
                let covered = text.matches(of: Self.backtickSpan).map(\.range)
                for name in names {
                    for range in text.ranges(of: name) {
                        if range.upperBound < text.endIndex,
                            Self.isIdentifierCharacter(text[range.upperBound]) { continue }
                        if range.lowerBound > text.startIndex,
                            Self.isIdentifierCharacter(text[text.index(before: range.lowerBound)])
                        { continue }
                        if covered.contains(where: {
                            $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound
                        }) { continue }
                        bare.insert(name)
                    }
                }
            }
            #expect(bare.isEmpty, "\(e.path) writes key name(s) without backticks: \(bare.sorted())")
        }
    }

    // MARK: - 4. Every method says more than its own name

    @Test func `probe entries say more than their own name`() throws {
        for e in try Self.evidenceFiles() {
            guard let probes = ((e.json["path_coverage"] as? [String: Any])?["how"]
                as? [String: Any])?["probes"] as? [String: String] else { continue }
            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                #expect(
                    !Self.backtickedTokens(in: method).subtracting([field]).isEmpty,
                    "\(e.path): how.probes[\(field)] names nothing but itself: \"\(method)\"")
            }
            #expect(
                Set(probes.values.map(Self.rendered)).count == probes.count,
                "\(e.path): how.probes has methods that render identically, so some field's method describes another's")
        }
    }

    // MARK: - 5. The external anchor still parses

    /// `Package.resolved` is the one file outside the evidence that anything
    /// here reads. Exactly one relation consults it — the arm under test must
    /// carry the revision it pins; the baseline arm is checked against a literal
    /// here. When the file is edited past what the parse follows, that relation
    /// fails saying the *evidence* does not hold — a diagnostic that sends a
    /// maintainer to re-run a benchmark, which is both wrong and expensive. So
    /// say which file stopped parsing, first.
    ///
    /// Reaching this guard by editing `Package.resolved` is harder than it
    /// looks, and two measured facts are worth knowing before trying:
    /// **deleting the whole file** does not test anything — SwiftPM re-creates
    /// it before the tests run, so the green suite means the mutation was
    /// undone; and **corrupting** it makes SwiftPM refuse to plan the build,
    /// which reports zero failures **and zero tests**, a shape only the exit
    /// code tells apart from a pass. Deleting the *pin* from an otherwise valid
    /// file does reach the guard: measured `rc=1`, 8 tests run, this test and
    /// the arm-under-test observation both failing. (An earlier version of this
    /// paragraph said that case was green. It was describing the deleted-file
    /// measurement and calling it the deleted-pin one.)
    ///
    /// There used to be a second source. `scripts/fetch-corpora.sh` was parsed
    /// by regex for the corpus name and two digests, and round 23 measured what
    /// that was worth: 16 of 66 shell constructions left the suite **green while
    /// the script and the evidence disagreed**. Those three values are now
    /// literals a reviewer read, declared in `observations`. Deleting the parse
    /// deleted the failure mode; the honest response to "a regex cannot follow
    /// shell" was not a better regex.
    ///
    /// This one stays because `Package.resolved` is different in the way that
    /// matters: it is written by a **tool** from an external fact, in a stable
    /// format, and it is the only thing in the repository that independently
    /// knows which revision the arm under test was built from.
    @Test func `the external anchor still parses`() {
        #expect(
            Self.pinnedFluidAudio != nil,
            "Package.resolved no longer parses — the arm-under-test revision relation below cannot run, and the failure it reports is about that file, not about the evidence")
    }

    // MARK: - 6. The laws hold, and so do the declared observations

    @Test func `recorded values satisfy the laws and the declared observations`() throws {
        for e in try Self.evidenceFiles() {
            guard let shape = Self.shape(for: e) else { continue }
            for law in shape.laws {
                #expect(law.holds(e.json), "\(e.path): the law \"\(law.label)\" does not hold")
            }
            for o in shape.observations {
                #expect(
                    o.holds(e.json),
                    "\(e.path): the declared observation \"\(o.label)\" no longer holds — if the run changed, change the declaration too")
            }
        }
    }
}
