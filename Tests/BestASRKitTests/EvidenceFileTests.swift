import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// **The shape of every file is declared here, in `shapes`, and not read from
/// the artifact.** Rounds 10 to 12 each found the same defect one level further
/// out: a checker that asks the artifact what it should contain cannot notice
/// something missing. Round 10 found it in the schema (derive the field set and
/// deleting a field passes); round 11 found it in the values (declare the names
/// and the key survives holding `null`); round 12 found it in every block that
/// was not `path_coverage` — 87 % of the file could be deleted, including the
/// error rate it exists to report, with every rule green — and in the checker's
/// own vocabulary, since adding a key to `how` used to legitimise any citation
/// of it.
///
/// So the declaration covers the whole file: which blocks exist, which keys
/// each holds, which arrays must be non-empty, which values are measurements
/// and of what kind, and which arithmetic identities apply. Its maintenance
/// cost is the mechanism, not a defect in it — a new evidence file, or a new
/// field in an old one, must be declared before it will pass.
///
/// **What these tests cannot do**, stated from the mutations that got past them
/// rather than from intent:
///
/// - **They cannot tell a method from filler.** A probe entry must cite
///   something other than itself, but any backticked token satisfies that —
///   ``"the `usual` way."`` passes, as does a denial ("not measured; assumed,
///   cf `case_folded_calls`"), as do two entries citing each other.
/// - **They cannot check that a method is true of the code**, or that a
///   citation is apt.
/// - **The dangling-name rule sees only underscored, all-lowercase,
///   non-`__` names.** `chunks` and `merges` — two of the twenty measurements —
///   are single words and are invisible to it, in backticks or out; so is a
///   mixed-case name like `nm_caseVariantCanonicalIds`, and so is anything
///   beginning `__`. Single words cannot be required to carry backticks: the
///   file legitimately writes `nil`, `left`, `grep`.
/// - **The metadata rule discriminates on JSON type.** It rejects a number
///   under a `_` key, and cannot see the same number written as text — which is
///   the file's own idiom, since `_limits` and `_nm_note` record figures in
///   prose. It catches a measurement moved wholesale; it does not catch one
///   retyped. It also rejects legitimate numeric metadata — a schema version
///   under `path_coverage` would fail — because type is the only signal it has.
/// - **Prose figures are not bound to the fields they quote.** Re-measure a
///   count, update every field consistently, and the sentences still quoting
///   the old number stay green.
/// - **Identities are sums, so they are permutation-invariant.** Swapping two
///   counts on one side still balances, and a field in no identity is
///   constrained only by its kind.
///
/// The identities read measured values to check they agree with each other.
/// Nothing here pins a value to an expected number.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    // MARK: - The declaration

    enum Kind { case count, flag, intList }

    /// One side of an identity equals the other. Both sides are recorded
    /// counts; nothing is compared to a literal.
    struct Identity { let label: String; let lhs: [String]; let rhs: [String] }

    struct Shape {
        /// Top-level key → the keys it must hold. An empty list means the key
        /// must exist and its contents are not further declared.
        let blocks: [String: [String]]
        /// `path_coverage.how` → the keys it must hold. Nothing else may sit
        /// there: `how` is excluded from the value/method correspondence, so an
        /// undeclared key under it is a measurement with nowhere to be checked.
        let howKeys: [String]
        /// Arrays that must not be empty. Declaring a key is not enough —
        /// round 11's lesson, applied to arrays as well as scalars.
        let nonEmptyArrays: [(block: String, key: String)]
        /// `path_coverage`'s measurements and what each holds.
        let valueFields: [String: Kind]
        let identities: [Identity]
    }

    /// Keyed by path relative to `benchmarks/evidence`, so two files with the
    /// same basename in different directories are two declarations.
    static let shapes: [String: Shape] = [
        "issue-122-fluidaudio-ab.json": Shape(
            blocks: [
                "_what_this_is": [],
                "_reproducing": [],
                "store_note": [],
                "session": [
                    "measured_at", "machine", "toolchain", "toolchain_caveat", "corpus",
                    "corpus_duration_seconds", "language", "audio_sha256", "reference_sha256",
                    "transcribe_command", "nm_command", "notes",
                ],
                "arms": ["0.15.4", "0.15.5", "cross_pin_cmp", "_executable_hash_note", "_nm_note"],
                "metric": ["kind", "edits", "reference_words", "value", "edit_list", "_note"],
                "path_coverage": [],  // its keys are valueFields + how + _limits, below
            ],
            howKeys: [
                "patch", "build", "probe_implementation", "probes",
                "isolating_the_counterfactual", "method_limits",
            ],
            nonEmptyArrays: [
                (block: "session", key: "notes"),
                (block: "metric", key: "edit_list"),
                (block: "path_coverage", key: "_limits"),
            ],
            valueFields: [
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
                "case_folded_matched_token_ids": .intList,
                "collapse_called": .flag,
                "case_folded_changed_merge_output": .flag,
                "counterfactual_tokens_equal": .flag,
                "counterfactual_timestamps_equal": .flag,
            ],
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
            ]),
    ]

    // MARK: - Loading

    private struct Evidence {
        let path: String  // relative to evidenceDirectory
        let json: [String: Any]
        /// Each string separately — never joined. A backtick regex over a
        /// concatenation can pair a backtick in one value with one in another,
        /// and `Dictionary` order is randomised per process.
        let strings: [String]
        let allKeys: Set<String>
    }

    /// Every regular file under the directory that parses as a JSON object,
    /// regardless of name. Selecting by extension missed a file named exactly
    /// `.json` (whose `pathExtension` is empty), `.jsonc`, and no extension at
    /// all — each of which is still an artifact sitting in the evidence
    /// directory.
    private static func evidenceFiles() throws -> [Evidence] {
        let root = evidenceDirectory.standardizedFileURL
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var found: [Evidence] = []
        var unparseable: [String] = []

        for case let url as URL in enumerator ?? .init() {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: root.path + "/", with: "")
            guard let data = try? Data(contentsOf: url) else {
                unparseable.append(relative); continue
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { unparseable.append(relative); continue }

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
            unparseable.isEmpty,
            "\(evidenceDirectory.path) holds file(s) that are not JSON objects: \(unparseable.sorted()). This directory holds evidence and nothing else.")
        #expect(!found.isEmpty, "no evidence files — every test here would pass vacuously")
        return found.sorted { $0.path < $1.path }
    }

    private static func shape(for e: Evidence) throws -> Shape {
        try #require(
            shapes[e.path],
            """
            \(e.path) has no entry in `shapes`. Every evidence file must declare its \
            structure here — that is what makes a missing block, key or measurement detectable.
            """)
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

    // MARK: - 1. The file has the declared shape

    @Test func `every evidence file has the blocks, keys and arrays it declares`() throws {
        let files = try Self.evidenceFiles()
        let onDisk = Set(files.map { $0.path })
        for declared in Self.shapes.keys {
            #expect(onDisk.contains(declared), "`shapes` declares \(declared), which is not on disk")
        }

        for e in files {
            let shape = try Self.shape(for: e)

            let actualTop: Set<String> = Set(e.json.keys)
            let declaredTop: Set<String> = Set(shape.blocks.keys)
            let missingTop: [String] = declaredTop.subtracting(actualTop).sorted()
            let extraTop: [String] = actualTop.subtracting(declaredTop).sorted()
            #expect(
                actualTop == declaredTop,
                """
                \(e.path): top-level keys differ from the declaration.
                missing: \(missingTop)
                unexpected: \(extraTop)
                """)

            for (block, requiredKeys) in shape.blocks.sorted(by: { $0.key < $1.key })
            where !requiredKeys.isEmpty {
                let actual: Set<String> = Set((e.json[block] as? [String: Any])?.keys.map { $0 } ?? [])
                let missing: [String] = Set(requiredKeys).subtracting(actual).sorted()
                #expect(missing.isEmpty, "\(e.path): \(block) is missing \(missing)")
            }

            let how = (e.json["path_coverage"] as? [String: Any])?["how"] as? [String: Any] ?? [:]
            let actualHow: Set<String> = Set(how.keys)
            let declaredHow: Set<String> = Set(shape.howKeys)
            let missingHow: [String] = declaredHow.subtracting(actualHow).sorted()
            let extraHow: [String] = actualHow.subtracting(declaredHow).sorted()
            #expect(
                actualHow == declaredHow,
                """
                \(e.path): how's keys differ from the declaration.
                missing: \(missingHow)
                unexpected: \(extraHow) \
                — `how` is outside the value/method correspondence, so an undeclared key \
                here is a measurement with nowhere to be checked.
                """)

            for (block, key) in shape.nonEmptyArrays {
                let array = (e.json[block] as? [String: Any])?[key] as? [Any]
                #expect(
                    !(array ?? []).isEmpty,
                    "\(e.path): \(block).\(key) is empty. Declaring a key is not enough; it has to hold something.")
            }
        }
    }

    // MARK: - 2. The measurements are present and of the declared kind

    @Test func `every declared measurement holds a value of its kind`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            let pc = try #require(e.json["path_coverage"] as? [String: Any])
            let actual = Set(pc.keys.filter { $0 != "how" && !$0.hasPrefix("_") })

            #expect(
                actual == Set(shape.valueFields.keys),
                """
                \(e.path): measurements differ from the declaration.
                missing: \(Set(shape.valueFields.keys).subtracting(actual).sorted())
                unexpected: \(actual.subtracting(Set(shape.valueFields.keys)).sorted())
                """)

            for (field, kind) in shape.valueFields.sorted(by: { $0.key < $1.key }) {
                guard let value = pc[field] else { continue }
                switch kind {
                case .count:
                    let n = try #require(value as? NSNumber, "\(e.path): \(field) is \(value), not a count")
                    #expect(CFGetTypeID(n) != CFBooleanGetTypeID(), "\(e.path): \(field) is a boolean, not a count")
                    #expect(
                        n.doubleValue == Double(n.intValue) && n.intValue >= 0,
                        "\(e.path): \(field) is \(n), not a whole non-negative count")
                case .flag:
                    let n = value as? NSNumber
                    #expect(
                        n != nil && CFGetTypeID(n!) == CFBooleanGetTypeID(),
                        "\(e.path): \(field) is \(value), not a boolean — 1 and 0 bridge to Bool and would pass silently")
                case .intList:
                    let list = try #require(value as? [Any], "\(e.path): \(field) is \(value), not a list")
                    #expect(!list.isEmpty, "\(e.path): \(field) is an empty list")
                    for element in list {
                        let n = try #require(element as? NSNumber, "\(e.path): \(field) holds \(element), not a number")
                        #expect(CFGetTypeID(n) != CFBooleanGetTypeID(), "\(e.path): \(field) holds a boolean")
                        #expect(
                            n.doubleValue == Double(n.intValue) && n.intValue >= 0,
                            "\(e.path): \(field) holds \(n), not a whole non-negative id")
                    }
                }
            }
        }
    }

    // MARK: - 3. No dangling field name

    @Test func `every backticked field name resolves to a key`() throws {
        for e in try Self.evidenceFiles() {
            var dangling = Set<String>()
            for text in e.strings {
                dangling.formUnion(Self.fieldNames(in: text).subtracting(e.allKeys))
            }
            #expect(dangling.isEmpty, "\(e.path) names field(s) that do not exist: \(dangling.sorted())")
        }
    }

    /// A probe entry may cite a **declared** `path_coverage` or `how` name, or a
    /// source symbol, or an ordinary word — but not a key belonging to another
    /// block. The scope comes from the declaration, not from the artifact:
    /// adding a key to `how` used to legitimise any citation of it.
    @Test func `probe entries cite only declared path_coverage names`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            guard let pc = e.json["path_coverage"] as? [String: Any],
                let how = pc["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }
            let inScope = Set(shape.valueFields.keys).union(shape.howKeys)
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

    // MARK: - 4. Underscored key names in prose are backticked

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

    // MARK: - 5. Every measurement states its method

    @Test func `probes cover the measurements and no number hides in metadata`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }
            let how = try #require(pc["how"] as? [String: Any])
            let probes = try #require(how["probes"] as? [String: String])
            let declared = Set(shape.valueFields.keys)

            #expect(
                declared.subtracting(probes.keys).sorted().isEmpty,
                "\(e.path): declared with no method: \(declared.subtracting(probes.keys).sorted())")
            #expect(
                Set(probes.keys).subtracting(declared).sorted().isEmpty,
                "\(e.path): how.probes describes undeclared field(s): \(Set(probes.keys).subtracting(declared).sorted())")

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                #expect(
                    !Self.backtickedTokens(in: method).subtracting([field]).isEmpty,
                    "\(e.path): how.probes[\(field)] names nothing but itself: \"\(method)\"")
            }

            // A number moved wholesale under a metadata key would leave the
            // correspondence above. This does not see a number retyped as text;
            // see the suite comment.
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

    // MARK: - 6. The declared identities hold

    @Test func `recorded counts satisfy their declared identities`() throws {
        for e in try Self.evidenceFiles() {
            let shape = try Self.shape(for: e)
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }

            func count(_ key: String) throws -> Int {
                let value = try #require(pc[key], "\(e.path): \(key) is absent")
                let n = try #require(
                    value as? NSNumber,
                    "\(e.path): \(key) is \(type(of: value)), not a number — its identities would be skipped")
                #expect(CFGetTypeID(n) != CFBooleanGetTypeID(), "\(e.path): \(key) is a boolean")
                return n.intValue
            }

            for identity in shape.identities {
                let lhs = try identity.lhs.map(count).reduce(0, +)
                let rhs = try identity.rhs.map(count).reduce(0, +)
                #expect(
                    lhs == rhs,
                    """
                    \(e.path): \(identity.label) does not balance.
                    \(identity.lhs.joined(separator: " + ")) = \(lhs)
                    \(identity.rhs.joined(separator: " + ")) = \(rhs)
                    """)
            }

            // The counterfactual conclusion follows from its two comparisons.
            // Kept out of `identities` because it is boolean, not a sum.
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
