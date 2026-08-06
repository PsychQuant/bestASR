import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// An evidence file records measurements together with the method that produced
/// each one. These tests enforce five properties of that pairing:
///
/// 1. The value fields are exactly the set declared in `expectedValueFields`
///    below — declared *here*, not read from the file.
/// 2. Every backticked lowercase snake_case name resolves to a key that exists.
/// 3. Every underscored key name appearing in prose is written in backticks,
///    so rule 2 can see it.
/// 4. `path_coverage.how.probes` covers the value fields exactly, no entry is
///    merely its own field name, and no measurement hides under a `_` key.
/// 5. The recorded counts satisfy five arithmetic identities, and every
///    identity is actually evaluated rather than skipped.
///
/// **Why the field set is declared here.** Round 10 established that a checker
/// deriving its schema from the artifact cannot detect absence: delete a value
/// and its method entry together, or empty both to `{}`, and every derived rule
/// still passes because ∅ corresponds to ∅. An external declaration is the only
/// thing that notices something missing. Its maintenance cost is the mechanism,
/// not a defect in it.
///
/// **What these tests cannot do.** Rule 4 requires a method entry to cite a
/// symbol, field or section other than itself, which rejects filler and
/// restatement. It cannot check that the citation is *apt*, nor tell an
/// assertion from a denial: "not measured; assumed to equal the 0.15.4 arm,
/// see `case_folded_calls`" cites something and passes. No lexical rule
/// distinguishes that from a true method; only reading does. Rule 3 covers underscored
/// names only — a single-word field name like `merges` is also ordinary English
/// and requiring backticks around every use would distort the prose. And
/// nothing here checks that a method entry is *true* of the code it describes.
/// Read the entries; do not assume a green suite vouched for them.
///
/// These assert structure, never a particular measurement, so re-measuring the
/// corpus never breaks them. Rule 5 does read measured values — it checks they
/// are consistent with each other, not that they equal anything expected.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    /// The value fields each evidence file must record, by file name. A new
    /// evidence file has to be declared here — that is deliberate, and it is
    /// what makes a missing field detectable.
    static let expectedValueFields: [String: Set<String>] = [
        "issue-122-fluidaudio-ab.json": [
            "chunks", "merges",
            "case_folded_calls", "case_folded_early_return_ids_equal",
            "case_folded_reached_guard", "case_folded_guard_else",
            "case_folded_guard_else_map_nil", "case_folded_guard_else_id_absent",
            "case_folded_both_ids_in_map", "case_folded_canonicals_differed",
            "case_folded_matches", "case_folded_matched_token_ids",
            "case_folded_canonical_id", "case_folded_changed_merge_output",
            "collapse_called", "collapse_tokens_in", "collapse_tokens_out",
            "word_boundary_fallbacks_entered",
            "counterfactual_tokens_equal", "counterfactual_timestamps_equal",
        ]
    ]

    // MARK: - Loading

    private struct Evidence {
        let name: String
        let json: [String: Any]
        /// Each string value separately. Never joined: a regex for backticked
        /// spans run over a concatenation can pair a backtick in one value with
        /// one in another, and `Dictionary` iteration order is randomised per
        /// process, so the result would differ between runs of the same file.
        let strings: [String]
        let allKeys: Set<String>
    }

    private static func evidenceFiles() throws -> [Evidence] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: evidenceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
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

    /// Lowercase snake_case tokens inside backticks, split on non-identifier
    /// characters so `` `a - b` `` yields both. Tokens containing uppercase are
    /// skipped deliberately: they are source symbols (`tokenIdsMatch`,
    /// `SRTParser`), not fields of this file. That also means a stale reference
    /// to a mixed-case *field* — `nm_caseVariantCanonicalIds` is one — is not
    /// caught here.
    private static func backtickedIdentifiers(in text: String) -> Set<String> {
        var found = Set<String>()
        for match in text.matches(of: backtickSpan) {
            for token in String(match.1)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            where token.contains("_") && !token.contains(where: \.isUppercase) {
                found.insert(String(token))
            }
        }
        return found
    }

    private static func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    // MARK: - 1. The value fields are the declared ones

    @Test func `each evidence file records exactly the value fields declared here`() throws {
        for e in try Self.evidenceFiles() {
            let declared = try #require(
                Self.expectedValueFields[e.name],
                """
                \(e.name) has no entry in expectedValueFields. A new evidence file must \
                declare its value fields here — otherwise nothing can notice one going missing.
                """)
            let pc = try #require(
                e.json["path_coverage"] as? [String: Any],
                "\(e.name) declares value fields but has no path_coverage block")
            let actual = Self.valueKeys(pc)

            #expect(
                actual == declared,
                """
                \(e.name): value fields differ from the declaration.
                missing: \(declared.subtracting(actual).sorted())
                unexpected: \(actual.subtracting(declared).sorted())
                If a field was added or removed on purpose, update expectedValueFields \
                and the count quoted in `_reproducing`.
                """)
        }
    }

    // MARK: - 2. No dangling field name

    @Test func `every backticked field name resolves to a key`() throws {
        for e in try Self.evidenceFiles() {
            var dangling = Set<String>()
            for text in e.strings {
                dangling.formUnion(Self.backtickedIdentifiers(in: text).subtracting(e.allKeys))
            }
            #expect(
                dangling.isEmpty,
                """
                \(e.name) names field(s) that do not exist: \(dangling.sorted()).
                A rename has to reach every sentence citing the old name.
                """)
        }
    }

    /// A method entry may only cite names from `path_coverage` — or source
    /// symbols, which carry uppercase. Citing `reference_words` (the WER
    /// denominator) or `transcript_sha256_txt` as the source of a control-flow
    /// count would otherwise satisfy rule 2, because those are keys somewhere.
    @Test func `probe entries cite only path_coverage fields`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any],
                let how = pc["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }
            let inScope = Self.valueKeys(pc).union(how.keys).union(["path_coverage"])

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                let outside = Self.backtickedIdentifiers(in: method).subtracting(inScope).sorted()
                #expect(
                    outside.isEmpty,
                    "\(e.name): how.probes[\(field)] sources its value from \(outside), which are not path_coverage fields")
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
            #expect(
                bare.isEmpty,
                "\(e.name) writes key name(s) without backticks: \(bare.sorted()). Rule 2 cannot see them.")
        }
    }

    // MARK: - 4. Every value states its method

    @Test func `probes cover the value fields and no measurement hides`() throws {
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

            // A method has to name something other than the field it describes:
            // the code symbol it reads, another field it derives from, or the
            // section that explains it. Filler text and a restatement of the
            // field name — in backticks or not — both fail this.
            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                var cited = Set<String>()
                for match in method.matches(of: Self.backtickSpan) {
                    for token in String(match.1)
                        .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
                    { cited.insert(String(token)) }
                }
                #expect(
                    !cited.subtracting([field]).isEmpty,
                    """
                    \(e.name): how.probes[\(field)] names nothing but itself: "\(method)"
                    A method entry has to cite the symbol, field or section it comes from.
                    """)
            }

            // A `_` key is metadata. A measurement moved under one would leave
            // the correspondence above, so numbers may not appear there at any
            // depth — including inside arrays and nested objects. Booleans are
            // allowed: they bridge to NSNumber but are ordinary metadata flags.
            func containsNumber(_ node: Any) -> Bool {
                switch node {
                case let n as NSNumber: return CFGetTypeID(n) != CFBooleanGetTypeID()
                case let a as [Any]: return a.contains(where: containsNumber)
                case let d as [String: Any]: return d.values.contains(where: containsNumber)
                default: return false
                }
            }
            for (key, value) in pc where key.hasPrefix("_") {
                #expect(
                    !containsNumber(value),
                    "\(e.name): \(key) holds a number under a metadata key, escaping the method requirement")
            }
        }
    }

    // MARK: - 5. The counts add up, and every identity is checked

    @Test func `recorded counts satisfy their identities, and none is skipped`() throws {
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
        ]

        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }

            func count(_ key: String) throws -> Int {
                let value = try #require(pc[key], "\(e.name): \(key) is absent")
                let number = try #require(
                    value as? NSNumber,
                    "\(e.name): \(key) is \(type(of: value)), not a number — its identities would be skipped")
                #expect(
                    CFGetTypeID(number) != CFBooleanGetTypeID(),
                    "\(e.name): \(key) is a boolean standing in for a count")
                #expect(
                    number.doubleValue == Double(number.intValue),
                    "\(e.name): \(key) is \(number), not a whole number")
                return number.intValue
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

            // The file states this identity in words; it is as checkable as the
            // four above, and it carries the entry's conclusion.
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
