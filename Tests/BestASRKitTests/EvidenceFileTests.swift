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
/// **The blind spots this leaves**, written from the mutations that got past it
/// rather than from intent:
///
/// - **A declaration detects one-sided change.** A deletion, rename or typo
///   applied to both the artifact and the declaration agrees with itself and
///   passes. That is the dual of a derived schema, which cannot detect absence
///   at all. Neither covers the other; this is the declared kind.
/// - **They cannot tell a method from filler.** A probe entry must cite
///   something other than itself, and any backticked token satisfies that:
///   ``"the `usual` way."`` passes, so does a denial, so do two entries citing
///   each other.
/// - **They cannot check that a method is true of the code**, or that a
///   citation is apt.
/// - **The dangling-name and bare-name rules see only underscored,
///   all-lowercase, non-`__` names.** `chunks` and `merges` are single words
///   and invisible to them. Single words cannot be required to carry backticks:
///   the file legitimately writes `nil`, `left`, `grep`.
/// - **Prose figures are not bound to the fields they quote.** Re-measure a
///   count, update every field consistently, and sentences still quoting the
///   old number stay green.
/// - **The case-fold census is internally consistent and externally
///   unanchored, and that cannot be fixed from inside this file.** The four
///   sums are a homogeneous, underdetermined system — nine counts, four
///   equations — so they admit a family of solutions, and the minimums only
///   exclude the zero one. Measured: scaling the nine census counts by ten
///   passes; so does moving along a free direction (854 / 71 / 783 / 650 / 0 /
///   650 / 133 / 2 / 131); so does setting both collapse counts to 1. Scaling
///   `chunks` and `merges` too is caught, but only by `merges == chunks - 1`.
///   Nothing recorded here determines how many times `tokenIdsMatch` is called,
///   so no relation can pin that census — the information is not in the file.
///   The sums are also permutation-invariant within a side.
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
        for p in paths { guard let v = int(json, "path_coverage." + p) else { return nil }; total += v }
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
            "probes": .object(measurements.mapValues { _ in Node.text }),
        ])
        keys["_limits"] = .array(of: .text, min: 5, distinct: true)
        return .object(keys)
    }

    /// A count's minimum is part of the recording's meaning: a run that
    /// produced no chunks produced no evidence, while a guard cause that never
    /// fired is a real zero.
    static let fluidAudioMeasurements: [String: Node] = [
        "chunks": .count(min: 1), "merges": .count(min: 1),
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
                    "corpus_duration_seconds": .real(min: 0), "language": .text,
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
                // The collapse counts are taken at that function's entry and
                // exit, so they mean nothing if it was never called.
                Relation(label: "collapse counts exist only if collapse_called") {
                    (value($0, "path_coverage.collapse_called") as? Bool) == true
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
                Relation(label: "collapse removed no token in this run") {
                    int($0, "path_coverage.collapse_tokens_in")
                        == int($0, "path_coverage.collapse_tokens_out")
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
            return (a["transcript_sha256_srt_run1"] as? String)
                == (b["transcript_sha256_srt_run1"] as? String)
        },
        Relation(label: "the txt transcripts are identical across arms") { json in
            guard let arms = json["arms"] as? [String: Any],
                let a = arms["0.15.4"] as? [String: Any], let b = arms["0.15.5"] as? [String: Any]
            else { return false }
            return (a["transcript_sha256_txt"] as? String) == (b["transcript_sha256_txt"] as? String)
        },
        Relation(label: "run 1 and run 2 agree within each arm") { json in
            guard let arms = json["arms"] as? [String: Any] else { return false }
            return ["0.15.4", "0.15.5"].allSatisfy { name in
                guard let arm = arms[name] as? [String: Any] else { return false }
                return (arm["transcript_sha256_srt_run1"] as? String)
                    == (arm["transcript_sha256_srt_run2"] as? String)
            }
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
        var stack: [Set<String>] = []
        let chars = Array(json)
        var i = 0
        var pendingKey: String?

        func readString() -> String {
            var out = ""
            i += 1  // opening quote
            while i < chars.count {
                if chars[i] == "\\" { i += 2; out += "?"; continue }
                if chars[i] == "\"" { i += 1; return out }
                out.append(chars[i]); i += 1
            }
            return out
        }

        while i < chars.count {
            switch chars[i] {
            case "{": stack.append([]); pendingKey = nil; i += 1
            case "}": if !stack.isEmpty { stack.removeLast() }; pendingKey = nil; i += 1
            case "[": i += 1
            case "]": i += 1
            case "\"":
                let s = readString()
                // A string is a key if the next non-space character is a colon
                // and we are directly inside an object.
                var j = i
                while j < chars.count, chars[j] == " " || chars[j] == "\n" || chars[j] == "\t" { j += 1 }
                if j < chars.count, chars[j] == ":", !stack.isEmpty {
                    if stack[stack.count - 1].contains(s) { duplicates.append(s) }
                    stack[stack.count - 1].insert(s)
                }
                pendingKey = nil
            default: i += 1
            }
        }
        _ = pendingKey
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

    /// Characters that occupy no visual space. Foundation trims U+FEFF and
    /// U+200B but not the format category, so a file of U+2060 word joiners
    /// passed every non-empty check while rendering as blank.
    private static let invisible = CharacterSet(charactersIn: "\u{00AD}\u{200E}\u{200F}\u{2060}\u{2061}\u{2062}\u{2063}\u{2064}\u{3164}\u{2800}\u{180E}")
        .union(.whitespacesAndNewlines)

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
            return s.unicodeScalars.contains(where: { !invisible.contains($0) })
                ? [] : ["\(here): no visible characters"]
        case .hex(let length):
            guard let s = value as? String else { return ["\(here): not a string"] }
            guard s.count == length, s.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                return ["\(here): not \(length) lowercase hex digits"]
            }
            return []
        case .count(let min):
            guard let n = plain(value) else { return ["\(here): not a number"] }
            guard n.doubleValue == Double(n.intValue) else { return ["\(here): \(n) is not whole"] }
            return n.intValue >= min ? [] : ["\(here): \(n) is below the declared minimum \(min)"]
        case .real(let min):
            guard let n = plain(value) else { return ["\(here): not a number"] }
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
                let rendered = a.map { "\($0)" }
                if Set(rendered).count != rendered.count {
                    out.append("\(here): has repeated elements, so its length overstates its content")
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
