import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// **The whole shape of every file is declared here, recursively, and not read
/// from the artifact.** Rounds 10 to 13 each found the same defect one level
/// further out. Round 10: derive the field set and deleting a field passes.
/// Round 11: declare the names and the key survives holding `null`. Round 12:
/// declare `path_coverage` and 87 % of the file — including the error rate it
/// exists to report — is still deletable. Round 13: declare which keys every
/// block holds and `metric.value: null` still passes, because a key set says
/// nothing about what the keys hold; and `method_limits`, the block that round
/// had just rewritten, could be `[]`.
///
/// So the declaration is a node tree: every object's key set is exact, every
/// scalar has a kind, every array has an element kind and a minimum length.
///
/// **The blind spot this leaves.** A declaration detects one-sided change. A
/// deletion, rename or typo applied to *both* the artifact and the declaration
/// agrees with itself and passes. That is the dual of what round 10 found for
/// derived schemas, which cannot detect absence at all. Neither mechanism
/// covers the other; this suite is the declared kind.
///
/// **What these tests cannot do**, written from the mutations that got past
/// them rather than from intent:
///
/// - **They cannot tell a method from filler.** A probe entry must cite
///   something other than itself, and any backticked token satisfies that:
///   ``"the `usual` way."`` passes, so does a denial ("not measured; assumed,
///   cf `case_folded_calls`"), so do two entries citing each other.
/// - **They cannot check that a method is true of the code**, that a citation
///   is apt, or that a string required to be non-empty says anything.
/// - **The dangling-name rule sees only underscored, all-lowercase, non-`__`
///   names.** `chunks` and `merges` — two of the twenty measurements — are
///   single words and invisible to it, as is a mixed-case name like
///   `nm_caseVariantCanonicalIds`. Single words cannot be required to carry
///   backticks: the file legitimately writes `nil`, `left`, `grep`.
/// - **The metadata rule discriminates on JSON type.** It rejects a number
///   under a `_` key and cannot see the same number retyped as text — which is
///   the file's own idiom, since `_limits` and `_nm_note` record figures in
///   prose. It also rejects legitimate numeric metadata, for the same reason.
/// - **Prose figures are not bound to the fields they quote.** Re-measure a
///   count, update every field consistently, and sentences still quoting the
///   old number stay green.
/// - **Identities are sums, so they are permutation-invariant**, and a field in
///   no identity is constrained only by its kind.
///
/// Identities compare recorded values with each other and pin none to a
/// literal. `observations` is the deliberate exception: relations that hold in
/// the recorded run and are not laws, so a re-measurement that changes one has
/// to change the declaration too. `collapse_tokens_in == collapse_tokens_out`
/// is one — a corpus with a removable duplicate would legitimately break it.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    // MARK: - The declaration

    indirect enum Node {
        /// Exact key set: missing and undeclared keys both fail.
        case object([String: Node])
        /// A non-empty string.
        case text
        /// A whole, non-negative number that is not a boolean.
        case count
        /// Any JSON number that is not a boolean.
        case number
        case flag
        case array(of: Node, min: Int)
    }

    struct Identity { let label: String; let lhs: [String]; let rhs: [String] }

    struct Shape {
        let root: Node
        let measurements: [String]
        let identities: [Identity]
        /// Relations that hold in the recorded run but are not invariants.
        let observations: [Identity]
    }

    private static func armNode() -> Node {
        .object([
            "fluidaudio_revision": .text, "executable_sha256": .text,
            "nm_caseVariantCanonicalIds": .count,
            "transcript_sha256_srt_run1": .text, "transcript_sha256_srt_run2": .text,
            "transcript_sha256_txt": .text,
        ])
    }

    /// `path_coverage` is built from the measurement map, so the schema, the
    /// probe map and the measurement list cannot drift apart.
    private static func pathCoverageNode(_ measurements: [String: Node]) -> Node {
        var keys = measurements
        keys["how"] = .object([
            "patch": .text, "build": .text, "probe_implementation": .text,
            "isolating_the_counterfactual": .text,
            "method_limits": .array(of: .text, min: 5),
            "probes": .object(measurements.mapValues { _ in Node.text }),
        ])
        keys["_limits"] = .array(of: .text, min: 5)
        return .object(keys)
    }

    static let fluidAudioMeasurements: [String: Node] = [
        "chunks": .count, "merges": .count,
        "case_folded_calls": .count,
        "case_folded_early_return_ids_equal": .count,
        "case_folded_reached_guard": .count,
        "case_folded_guard_else": .count,
        "case_folded_guard_else_map_nil": .count,
        "case_folded_guard_else_id_absent": .count,
        "case_folded_both_ids_in_map": .count,
        "case_folded_canonicals_differed": .count,
        "case_folded_matches": .count,
        "case_folded_canonical_id": .count,
        "collapse_tokens_in": .count, "collapse_tokens_out": .count,
        "word_boundary_fallbacks_entered": .count,
        "case_folded_matched_token_ids": .array(of: .count, min: 1),
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
                    "corpus_duration_seconds": .number, "language": .text,
                    "audio_sha256": .text, "reference_sha256": .text,
                    "transcribe_command": .text, "nm_command": .text,
                    "notes": .array(of: .text, min: 1),
                ]),
                "arms": .object([
                    "0.15.4": armNode(), "0.15.5": armNode(),
                    "cross_pin_cmp": .text,
                    "_executable_hash_note": .text, "_nm_note": .text,
                ]),
                "metric": .object([
                    "kind": .text, "edits": .count, "reference_words": .count,
                    "value": .number, "edit_list": .array(of: .text, min: 1), "_note": .text,
                ]),
                "path_coverage": pathCoverageNode(fluidAudioMeasurements),
            ]),
            measurements: Array(fluidAudioMeasurements.keys),
            identities: [
                Identity(label: "calls split at the early return",
                         lhs: ["case_folded_calls"],
                         rhs: ["case_folded_early_return_ids_equal", "case_folded_reached_guard"]),
                Identity(label: "the guard's two outcomes",
                         lhs: ["case_folded_reached_guard"],
                         rhs: ["case_folded_guard_else", "case_folded_both_ids_in_map"]),
                Identity(label: "the guard's else, by cause",
                         lhs: ["case_folded_guard_else"],
                         rhs: ["case_folded_guard_else_map_nil", "case_folded_guard_else_id_absent"]),
                Identity(label: "both ids present, by outcome",
                         lhs: ["case_folded_both_ids_in_map"],
                         rhs: ["case_folded_matches", "case_folded_canonicals_differed"]),
            ],
            observations: [
                Identity(label: "collapse removed no token in this run",
                         lhs: ["collapse_tokens_in"], rhs: ["collapse_tokens_out"]),
            ]),
    ]

    // MARK: - Loading

    private struct Evidence {
        let path: String
        let json: [String: Any]
        let strings: [String]
        let allKeys: Set<String>
    }

    /// Every regular file under the directory that parses as a JSON object,
    /// whatever it is named. Selecting by extension missed a file called
    /// exactly `.json`, whose `pathExtension` is empty.
    private static func evidenceFiles() throws -> [Evidence] {
        let root = evidenceDirectory.standardizedFileURL
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var found: [Evidence] = []
        var unusable: [String] = []

        for case let url as URL in enumerator ?? .init() {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: root.path + "/", with: "")
            guard let data = try? Data(contentsOf: url),
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { unusable.append(relative); continue }

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
            found.append(Evidence(path: relative, json: json, strings: strings, allKeys: keys))
        }

        #expect(
            unusable.isEmpty,
            "\(evidenceDirectory.path) holds file(s) that are not JSON objects: \(unusable.sorted()). This directory holds evidence and nothing else.")
        #expect(!found.isEmpty, "no evidence files — every test here would pass vacuously")
        return found.sorted { $0.path < $1.path }
    }

    private static func shape(for e: Evidence) throws -> Shape {
        try #require(
            shapes[e.path],
            "\(e.path) has no entry in `shapes`. Every evidence file must declare its shape here.")
    }

    // MARK: - Matching a value against a declared node

    /// The mismatches between a value and its declaration. Empty means the
    /// value has exactly the declared shape, all the way down.
    static func mismatches(_ value: Any?, against node: Node, at path: String) -> [String] {
        func plainNumber(_ v: Any?) -> NSNumber? {
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
                out += mismatches(
                    actual[key], against: child, at: path.isEmpty ? key : "\(path).\(key)")
            }
            return out
        case .text:
            guard let s = value as? String else { return ["\(here): not a string"] }
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ["\(here): empty string"] : []
        case .count:
            guard let n = plainNumber(value) else { return ["\(here): not a number"] }
            return n.doubleValue == Double(n.intValue) && n.intValue >= 0
                ? [] : ["\(here): \(n) is not a whole non-negative count"]
        case .number:
            return plainNumber(value) == nil ? ["\(here): not a number"] : []
        case .flag:
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
                return ["\(here): not a boolean — 1 and 0 bridge to Bool and would pass silently"]
            }
            return []
        case .array(let element, let min):
            guard let a = value as? [Any] else { return ["\(here): not an array"] }
            guard a.count >= min else { return ["\(here): has \(a.count) element(s), needs \(min)"] }
            return a.enumerated().flatMap { mismatches($1, against: element, at: "\(here)[\($0)]") }
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

    // MARK: - 1. The file has the declared shape, all the way down

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

    /// A probe entry may cite a declared `path_coverage` name, a `how` key, a
    /// source symbol or an ordinary word — but not a key belonging to another
    /// block. The scope comes from the declaration, not from the artifact.
    @Test func `probe entries cite only declared path_coverage names`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            guard let how = (e.json["path_coverage"] as? [String: Any])?["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }
            let inScope = Set(shape.measurements).union(how.keys)
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

    // MARK: - 4. Every method says something, and no number hides in metadata

    @Test func `probe entries say more than their own name, and no number hides`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any],
                let how = pc["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                #expect(
                    !Self.backtickedTokens(in: method).subtracting([field]).isEmpty,
                    "\(e.path): how.probes[\(field)] names nothing but itself: \"\(method)\"")
            }

            func numberUnderMetadata(_ node: Any, metadata: Bool) -> Bool {
                switch node {
                case let n as NSNumber: return metadata && CFGetTypeID(n) != CFBooleanGetTypeID()
                case let a as [Any]: return a.contains { numberUnderMetadata($0, metadata: metadata) }
                case let d as [String: Any]:
                    return d.contains { numberUnderMetadata($1, metadata: metadata || $0.hasPrefix("_")) }
                default: return false
                }
            }
            #expect(
                !numberUnderMetadata(pc, metadata: false),
                "\(e.path): a number sits under a metadata key in path_coverage, escaping the method requirement")
        }
    }

    // MARK: - 5. Identities, and the observations that are not identities

    @Test func `recorded counts satisfy their identities and declared observations`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }

            func count(_ key: String) throws -> Int {
                let n = try #require(pc[key] as? NSNumber, "\(e.path): \(key) is not a number")
                #expect(CFGetTypeID(n) != CFBooleanGetTypeID(), "\(e.path): \(key) is a boolean")
                return n.intValue
            }
            func check(_ list: [Identity], _ noun: String) throws {
                for i in list {
                    let l = try i.lhs.map(count).reduce(0, +)
                    let r = try i.rhs.map(count).reduce(0, +)
                    #expect(
                        l == r,
                        """
                        \(e.path): \(noun) "\(i.label)" does not hold.
                        \(i.lhs.joined(separator: " + ")) = \(l)
                        \(i.rhs.joined(separator: " + ")) = \(r)
                        """)
                }
            }
            try check(shape.identities, "identity")
            try check(shape.observations, "declared observation")

            if let tokens = pc["counterfactual_tokens_equal"] as? Bool,
                let stamps = pc["counterfactual_timestamps_equal"] as? Bool,
                let changed = pc["case_folded_changed_merge_output"] as? Bool
            {
                #expect(
                    changed == !(tokens && stamps),
                    "\(e.path): case_folded_changed_merge_output is \(changed) but the counterfactual comparisons say \(!(tokens && stamps))")
            }
        }
    }
}
