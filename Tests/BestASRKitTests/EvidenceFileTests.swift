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
/// So the declaration now constrains magnitude as well as form, and
/// `relations` derives what is derivable rather than asserting it:
/// `metric.value == edits / reference_words`, `merges == chunks - 1`,
/// `case_folded_canonical_id ∈ case_folded_matched_token_ids`. Those are laws
/// of the recording, not of this run; a re-measurement satisfies them or the
/// recording is wrong. `observations` is the separate, deliberate class for
/// relations that are true of *this* run and are not laws — the transcripts
/// being identical across arms, run-to-run equality, the `nm` counts differing.
/// Changing one of those means changing the declaration, on purpose.
///
/// **The blind spots this leaves.** Every item below was a mutation that
/// passed. The list has been wrong in each of rounds 9 to 18 — most recently by
/// stating the vacuity case backwards — so it is written from what got through,
/// and where a claim would need testing to make, it is not made.
///
/// - **A declaration detects one-sided change.** A deletion, rename or typo
///   applied to both the artifact and the declaration agrees with itself. That
///   is the dual of a derived schema, which cannot detect absence at all.
/// - **`.text` is a floor, not a legibility test.** It rejects the empty
///   string, the Marks, and the eight blank-rendering scalars found so far. No
///   Foundation predicate answers "does this render", so a scalar nobody has
///   tried will pass — and a single `x` passes by design.
/// - **The prose anchors protect against silent numeric drift, not against
///   false prose.** They match phrases and parse figures; they do not read
///   affirmation, negation or subject. `"They do not agree at 773"` passes.
///   Removing a phrase makes three of the seven probe clauses vacuous — the
///   ones guarded `!quotes(…) || …`, namely `never nil`, `each 0` and
///   `recorded true`; removing any of the other four, or either quadruple, or
///   `_reproducing`'s figure, makes its law **fail**.
/// - **The quadruple parser is strict about syntax and blind to context.** It
///   needs exactly two parseable matches in textual order; a third anywhere in
///   the string breaks it, and moving both into a negated passage still passes.
/// - **A probe entry may cite any backticked token**, so filler, a denial or
///   mutual citation pass — except where a prose law pins the entry. The
///   twenty methods must now be distinct, and each must name something other
///   than its own field.
/// - **No rule checks a method is true of the code**, or that a citation is apt.
/// - **The dangling-name and bare-name rules see only underscored,
///   all-lowercase, non-`__` names**, so `chunks` and `merges` are invisible to
///   them in backticks or out. Single words cannot be required to carry
///   backticks: the file legitimately writes `nil`, `left`, `grep`.
/// - **Figures quoted in prose outside `how.probes` and `_limits[1]` are
///   unbound**, and a legitimate re-measurement that changes an observation or
///   a pinned figure requires editing this declaration — deliberately, which is
///   what `observations` is for, but it is a cost.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

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
                // `merges`' own probe entry, and the reason a uniform scaling of
                // the census does not satisfy this set.
                Relation(label: "merges == chunks - 1") {
                    guard let c = int($0, "path_coverage.chunks"),
                        let m = int($0, "path_coverage.merges") else { return false }
                    return m == c - 1
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
                        for range in text.ranges(of: phrase) {
                            if range.upperBound == text.endIndex { return true }
                            if !text[range.upperBound].isNumber { return true }
                        }
                        return false
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
                        for range in text.ranges(of: String(v)) {
                            let beforeOK = range.lowerBound == text.startIndex
                                || !text[text.index(before: range.lowerBound)].isNumber
                            let afterOK = range.upperBound == text.endIndex
                                || !text[range.upperBound].isNumber
                            if beforeOK && afterOK { return true }
                        }
                        return false
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
                // The conclusion follows from its two comparisons.
                Relation(label: "changed_merge_output == !(tokens_equal && timestamps_equal)") {
                    guard let t = value($0, "path_coverage.counterfactual_tokens_equal") as? Bool,
                        let s = value($0, "path_coverage.counterfactual_timestamps_equal") as? Bool,
                        let c = value($0, "path_coverage.case_folded_changed_merge_output") as? Bool
                    else { return false }
                    return c == !(t && s)
                },
            ],
            observations: [
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
            ]),
    ]

    /// `arms` keys contain dots, which the dotted-path accessor cannot address,
    /// so the arm relations are written directly.
    static let armObservations: [Relation] = [
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
        Relation(label: "the nm counts differ between arms — the A/B result itself") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = (arms["0.15.4"] as? [String: Any])?["nm_caseVariantCanonicalIds"] as? NSNumber,
                let b = (arms["0.15.5"] as? [String: Any])?["nm_caseVariantCanonicalIds"] as? NSNumber
            else { return false }
            return a.intValue == 0 && b.intValue > 0
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

    private static func shape(for e: Evidence) throws -> Shape {
        try #require(
            shapes[e.path],
            "\(e.path) has no entry in `shapes`. Every evidence file must declare its shape here.")
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
    /// BRAILLE PATTERN BLANK (`So`, so `symbols`) — along with two more Hangul
    /// fillers. General category is not a renderability predicate, and no
    /// predicate in Foundation is. **This is a floor, not a test for
    /// legibility**: it rejects the blank-rendering scalars that have actually
    /// been found, and a scalar nobody has thought of will pass.
    private static let knownBlank = CharacterSet(charactersIn:
        "\u{115F}\u{1160}\u{3164}\u{FFA0}\u{2800}\u{180E}\u{200B}\u{FEFF}")
    private static let visible = CharacterSet.alphanumerics
        .union(.punctuationCharacters).union(.symbols)
        .subtracting(.nonBaseCharacters)
        .subtracting(knownBlank)

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
                let rendered = a.map { element -> String in
                    String(String(describing: element).unicodeScalars.filter { visible.contains($0) })
                }
                if Set(rendered).count != rendered.count {
                    out.append("\(here): has elements that render identically, so its length overstates its content")
                }
            }
            return out + a.enumerated().flatMap { mismatches($1, against: element, at: "\(here)[\($0)]") }
        }
    }

    // MARK: - Text helpers

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
            let problems = Self.mismatches(e.json, against: try Self.shape(for: e).root, at: "")
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
    /// another block. Both halves of the scope come from the declaration.
    @Test func `probe entries cite only declared path_coverage names`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
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
                Set(probes.values).count == probes.count,
                "\(e.path): how.probes has repeated methods, so some field's method describes another's")
        }
    }

    // MARK: - 5. The laws hold, and so do the declared observations

    @Test func `recorded values satisfy the laws and the declared observations`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            for law in shape.laws {
                #expect(law.holds(e.json), "\(e.path): the law \"\(law.label)\" does not hold")
            }
            for o in shape.observations {
                #expect(
                    o.holds(e.json),
                    "\(e.path): the declared observation \"\(o.label)\" no longer holds — if the run changed, change the declaration too")
            }
            for o in Self.armObservations {
                #expect(
                    o.holds(e.json),
                    "\(e.path): the declared observation \"\(o.label)\" no longer holds — if the run changed, change the declaration too")
            }
        }
    }
}
