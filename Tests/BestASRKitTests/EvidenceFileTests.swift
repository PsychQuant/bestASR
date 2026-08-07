import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// An evidence file records measurements together with the method that produced
/// each one. These tests enforce, for every file in that directory:
///
/// 1. The value fields are exactly the set declared in `expectedValueFields`
///    below, **each holding a value of its declared kind** — declared here, not
///    read from the artifact.
/// 2. Every backticked lowercase snake_case name resolves to a key that exists.
/// 3. A probe entry may cite a name from `path_coverage` or a source symbol,
///    but not a key from elsewhere in the file.
/// 4. Every underscored key name appearing in prose is written in backticks.
/// 5. `how.probes` covers the value fields exactly, no entry names only itself,
///    and no number hides under a `_`-prefixed key at any depth.
/// 6. Six arithmetic identities hold, with every operand type-checked.
///
/// **Why the field set and its kinds are declared here.** Round 10 established
/// that a checker deriving its schema from the artifact cannot detect absence:
/// delete a value and its method together and every derived rule passes,
/// because ∅ corresponds to ∅. Round 11 established that declaring the *names*
/// alone repeats that one level down — the key survives holding `null`, and the
/// correspondence is still perfect. So the kind is declared too.
///
/// **What these tests cannot do**, stated so nobody reads a green suite as more
/// than it is:
///
/// - **They cannot tell a method from filler.** Rule 5 rejects an entry that
///   names only its own field, but any other backticked token satisfies it —
///   ``"the `usual` way."`` passes. Nor can any lexical rule tell an assertion
///   from a denial: "not measured; assumed, cf `case_folded_calls`" passes.
/// - **They cannot check that a method is true of the code**, or that a
///   citation is apt.
/// - **Rules 2 and 4 see only underscored, all-lowercase names.** A stale
///   reference to `nm_caseVariantCanonicalIds` (mixed case) or to `chunks` (one
///   word) is invisible, in backticks or out. Single words cannot be required
///   to carry backticks — the file legitimately writes `nil`, `left`, `grep` —
///   and mixed-case tokens are excluded so that source symbols do not have to
///   be keys. Names beginning `__` are excluded as Mach-O sections.
/// - **Rule 3 polices only citations that are keys somewhere.** A cited word
///   that is no key at all is unchecked.
/// - **Rule 6 constrains sums, which are permutation-invariant.** Swapping two
///   counts within one side of an identity still balances; nothing binds a
///   count to its own name, and nine of the twenty fields appear in no identity.
///
/// Rule 6 reads measured values, to check they agree with each other. Nothing
/// here pins a value to an expected number, so re-measuring never breaks these.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    /// What a value field holds. Declared so that emptying a field — `null`,
    /// `[]`, `{}` — is a failure rather than a silent hole behind a live key.
    enum Kind { case count, flag, intList }

    /// Every evidence file's value fields and their kinds. A new file must be
    /// declared here; that is what makes a missing field detectable.
    static let expectedValueFields: [String: [String: Kind]] = [
        "issue-122-fluidaudio-ab.json": [
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
        ]
    ]

    // MARK: - Loading

    private struct Evidence {
        let name: String
        let json: [String: Any]
        /// Each string separately — never joined. A backtick regex over a
        /// concatenation can pair a backtick in one value with one in another,
        /// and `Dictionary` order is randomised per process, so the result
        /// would differ between runs of the same file.
        let strings: [String]
        let allKeys: Set<String>
    }

    private static func evidenceFiles() throws -> [Evidence] {
        // Recursive and case-insensitive: a file in a subdirectory or named
        // `.JSON` is still an evidence file, and was previously undeclarable
        // and therefore unchecked.
        let enumerator = FileManager.default.enumerator(
            at: evidenceDirectory, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!urls.isEmpty, "no evidence files — every test here would pass vacuously")

        return try urls.map { url in
            let data = try Data(contentsOf: url)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
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
            return Evidence(name: url.lastPathComponent, json: json, strings: strings, allKeys: keys)
        }
    }

    private static func valueKeys(_ pathCoverage: [String: Any]) -> Set<String> {
        Set(pathCoverage.keys.filter { $0 != "how" && !$0.hasPrefix("_") })
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

    /// Field-shaped names only: underscored, all-lowercase, and not
    /// double-underscored. Mixed case means a source symbol; a single word
    /// cannot be told from ordinary prose; and a leading `__` is the reserved
    /// convention for Mach-O sections and compiler internals (`__text`,
    /// `__LINKEDIT`), which the file cites and which are not fields.
    private static func fieldNames(in text: String) -> Set<String> {
        backtickedTokens(in: text).filter {
            $0.contains("_") && !$0.hasPrefix("__") && !$0.contains(where: \.isUppercase)
        }
    }

    private static func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    // MARK: - 1. The declared fields, holding declared kinds

    @Test func `each evidence file records the declared value fields, each holding a value`() throws {
        let files = try Self.evidenceFiles()
        let onDisk = Set(files.map(\.name))
        for declared in Self.expectedValueFields.keys {
            #expect(
                onDisk.contains(declared),
                "expectedValueFields declares \(declared), which is not in \(Self.evidenceDirectory.path)")
        }

        for e in files {
            let declared = try #require(
                Self.expectedValueFields[e.name],
                """
                \(e.name) has no entry in expectedValueFields. A new evidence file must declare \
                its value fields and their kinds here — otherwise nothing notices one going missing.
                """)
            let pc = try #require(
                e.json["path_coverage"] as? [String: Any],
                "\(e.name) declares value fields but has no path_coverage block")
            let actual = Self.valueKeys(pc)

            #expect(
                actual == Set(declared.keys),
                """
                \(e.name): value fields differ from the declaration.
                missing: \(Set(declared.keys).subtracting(actual).sorted())
                unexpected: \(actual.subtracting(Set(declared.keys)).sorted())
                """)

            for (field, kind) in declared.sorted(by: { $0.key < $1.key }) {
                guard let value = pc[field] else { continue }  // reported above
                switch kind {
                case .count:
                    let n = try #require(
                        value as? NSNumber, "\(e.name): \(field) is \(value), not a count")
                    #expect(
                        CFGetTypeID(n) != CFBooleanGetTypeID(),
                        "\(e.name): \(field) is a boolean standing in for a count")
                    #expect(
                        n.doubleValue == Double(n.intValue) && n.intValue >= 0,
                        "\(e.name): \(field) is \(n), not a whole non-negative count")
                case .flag:
                    let n = value as? NSNumber
                    #expect(
                        n != nil && CFGetTypeID(n!) == CFBooleanGetTypeID(),
                        "\(e.name): \(field) is \(value), not a boolean — 1 and 0 bridge to Bool and would pass silently")
                case .intList:
                    let list = try #require(
                        value as? [NSNumber], "\(e.name): \(field) is \(value), not a list of numbers")
                    #expect(!list.isEmpty, "\(e.name): \(field) is an empty list")
                }
            }
        }
    }

    // MARK: - 2. No dangling field name

    @Test func `every backticked field name resolves to a key`() throws {
        for e in try Self.evidenceFiles() {
            var dangling = Set<String>()
            for text in e.strings {
                dangling.formUnion(Self.fieldNames(in: text).subtracting(e.allKeys))
            }
            #expect(
                dangling.isEmpty,
                "\(e.name) names field(s) that do not exist: \(dangling.sorted())")
        }
    }

    // MARK: - 3. A probe entry cites its own block, not another

    /// Any cited name that is a key *somewhere* must be a key of
    /// `path_coverage`. That blocks sourcing a control-flow count from `edits`
    /// or `reference_words` — the WER numerator and denominator — while leaving
    /// source symbols and ordinary words alone, since neither is a key.
    @Test func `probe entries cite only path_coverage names`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any],
                let how = pc["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }
            let inScope = Set(pc.keys).union(how.keys)

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                let foreign = Self.backtickedTokens(in: method)
                    .intersection(e.allKeys)
                    .subtracting(inScope)
                    .sorted()
                #expect(
                    foreign.isEmpty,
                    "\(e.name): how.probes[\(field)] sources its value from \(foreign), which belong to another block")
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
            #expect(
                bare.isEmpty,
                "\(e.name) writes key name(s) without backticks: \(bare.sorted()). Rule 2 cannot see them.")
        }
    }

    // MARK: - 5. Every value states its method, and nothing hides

    @Test func `probes cover the value fields and no number hides`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }
            let how = try #require(pc["how"] as? [String: Any], "\(e.name): path_coverage has no how")
            let probes = try #require(how["probes"] as? [String: String], "\(e.name): how has no probes")
            let values = Self.valueKeys(pc)

            #expect(
                values.subtracting(probes.keys).sorted().isEmpty,
                "\(e.name): recorded with no method: \(values.subtracting(probes.keys).sorted())")
            #expect(
                Set(probes.keys).subtracting(values).sorted().isEmpty,
                "\(e.name): how.probes describes absent field(s): \(Set(probes.keys).subtracting(values).sorted())")

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                #expect(
                    !Self.backtickedTokens(in: method).subtracting([field]).isEmpty,
                    "\(e.name): how.probes[\(field)] names nothing but itself: \"\(method)\"")
            }

            // A `_` key is metadata. A measurement moved under one — at any
            // depth, under any key, inside arrays or nested objects — would
            // leave the correspondence above. Booleans are ordinary flags.
            func numbersUnderMetadata(_ node: Any, underMetadataKey: Bool) -> Bool {
                switch node {
                case let n as NSNumber:
                    return underMetadataKey && CFGetTypeID(n) != CFBooleanGetTypeID()
                case let a as [Any]:
                    return a.contains { numbersUnderMetadata($0, underMetadataKey: underMetadataKey) }
                case let d as [String: Any]:
                    return d.contains {
                        numbersUnderMetadata($1, underMetadataKey: underMetadataKey || $0.hasPrefix("_"))
                    }
                default: return false
                }
            }
            #expect(
                !numbersUnderMetadata(pc, underMetadataKey: false),
                "\(e.name): a number sits under a metadata key in path_coverage, escaping the method requirement")
        }
    }

    // MARK: - 6. The counts add up

    @Test func `recorded counts satisfy their identities`() throws {
        struct Sum { let label: String; let lhs: [String]; let rhs: [String] }
        let sums = [
            Sum(label: "calls split at the early return",
                lhs: ["case_folded_calls"],
                rhs: ["case_folded_early_return_ids_equal", "case_folded_reached_guard"]),
            Sum(label: "the guard's two outcomes",
                lhs: ["case_folded_reached_guard"],
                rhs: ["case_folded_guard_else", "case_folded_both_ids_in_map"]),
            Sum(label: "the guard's else, by cause",
                lhs: ["case_folded_guard_else"],
                rhs: ["case_folded_guard_else_map_nil", "case_folded_guard_else_id_absent"]),
            Sum(label: "both ids present, by outcome",
                lhs: ["case_folded_both_ids_in_map"],
                rhs: ["case_folded_matches", "case_folded_canonicals_differed"]),
            // Stated in `_limits`: equal counts establish that no token was removed.
            Sum(label: "collapse removed no token",
                lhs: ["collapse_tokens_in"], rhs: ["collapse_tokens_out"]),
        ]

        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }

            func count(_ key: String) throws -> Int {
                let value = try #require(pc[key], "\(e.name): \(key) is absent")
                let n = try #require(
                    value as? NSNumber,
                    "\(e.name): \(key) is \(type(of: value)), not a number — its identities would be skipped")
                #expect(CFGetTypeID(n) != CFBooleanGetTypeID(), "\(e.name): \(key) is a boolean")
                return n.intValue
            }

            for sum in sums {
                let lhs = try sum.lhs.map(count).reduce(0, +)
                let rhs = try sum.rhs.map(count).reduce(0, +)
                #expect(
                    lhs == rhs,
                    """
                    \(e.name): \(sum.label) does not balance.
                    \(sum.lhs.joined(separator: " + ")) = \(lhs)
                    \(sum.rhs.joined(separator: " + ")) = \(rhs)
                    """)
            }

            // The sixth: stated in words, and it carries the entry's conclusion.
            // `as? Bool` bridges 0 and 1, so the kinds are checked in rule 1.
            let tokensEqual = try #require(pc["counterfactual_tokens_equal"] as? Bool)
            let stampsEqual = try #require(pc["counterfactual_timestamps_equal"] as? Bool)
            let changed = try #require(pc["case_folded_changed_merge_output"] as? Bool)
            #expect(
                changed == !(tokensEqual && stampsEqual),
                """
                \(e.name): case_folded_changed_merge_output is \(changed) but the counterfactual \
                comparisons say \(!(tokensEqual && stampsEqual)).
                """)
        }
    }
}
