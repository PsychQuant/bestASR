import Foundation
import Testing

/// Internal-consistency contract for evidence files under `benchmarks/evidence/`.
///
/// An evidence file records measurements together with the method that produced
/// them. These tests enforce four properties of that pairing. They assert
/// structure only — never a measured value, so re-measuring never breaks them.
///
/// 1. Every field name written in backticks resolves to a key that exists.
/// 2. Every value field's name, wherever it appears in prose, is written in
///    backticks — otherwise rule 1 cannot see it.
/// 3. `path_coverage.how.probes` and the value fields are in exact
///    correspondence, and each probe entry states a method rather than
///    restating the field name.
/// 4. The arithmetic relationships between the recorded counts hold.
///
/// If one of these fires, the file and its own description have drifted apart;
/// fix whichever is wrong. If the file has moved or been archived, update
/// `evidenceDirectory` or delete this suite — it guards that directory and
/// nothing else.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let evidenceDirectory = repoRoot.appendingPathComponent("benchmarks/evidence")

    /// Words that mark a probe entry as stating a method rather than naming a field.
    static let methodWords = [
        "probe", "probed", "derived", "emitted", "sum", "count", "loop",
        "entry", "exit", "follows", "comparison", "obtainable", "reduction",
    ]

    // MARK: - Loading

    private struct Evidence {
        let name: String
        let json: [String: Any]
        /// Every string anywhere in the file, joined — the prose rules 1 and 2 apply to.
        let prose: String
        /// Every key at every depth.
        let allKeys: Set<String>
    }

    private static func evidenceFiles() throws -> [Evidence] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: evidenceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!urls.isEmpty, "no evidence files in \(evidenceDirectory.path) — these tests would pass vacuously")

        return try urls.map { url in
            let data = try Data(contentsOf: url)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var strings: [String] = []
            var keys = Set<String>()
            func walk(_ node: Any) {
                switch node {
                case let d as [String: Any]:
                    for (k, v) in d {
                        keys.insert(k)
                        walk(v)
                    }
                case let a as [Any]: a.forEach(walk)
                case let s as String: strings.append(s)
                default: break
                }
            }
            walk(json)
            return Evidence(
                name: url.lastPathComponent, json: json,
                prose: strings.joined(separator: "\n"), allKeys: keys)
        }
    }

    /// The `path_coverage` value keys — those holding measurements, so excluding
    /// `how` and anything a `_` marks as metadata.
    private static func valueKeys(_ pathCoverage: [String: Any]) -> Set<String> {
        Set(pathCoverage.keys.filter { $0 != "how" && !$0.hasPrefix("_") })
    }

    // MARK: - Text helpers

    private static let backtickSpan = #/`([^`]+)`/#

    /// snake_case tokens inside backticks, split on anything that is not an
    /// identifier character so that `` `a - b` `` yields both names.
    private static func backtickedIdentifiers(in prose: String) -> Set<String> {
        var found = Set<String>()
        for match in prose.matches(of: backtickSpan) {
            for token in String(match.1).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            where token.contains("_") && !token.contains(where: \.isUppercase) {
                found.insert(String(token))
            }
        }
        return found
    }

    private static func backtickedRanges(in prose: String) -> [Range<String.Index>] {
        prose.matches(of: backtickSpan).map(\.range)
    }

    // MARK: - 1. No dangling field name

    /// Every backticked snake_case name must be a key that exists somewhere in
    /// the file. Derived from the file's own keys, so a new field needs no
    /// change here — round 8 shipped a rename that left a sentence naming the
    /// old key, and a hand-maintained prefix list would not have seen it.
    @Test func `every backticked field name resolves to a key`() throws {
        for e in try Self.evidenceFiles() {
            let dangling = Self.backtickedIdentifiers(in: e.prose)
                .subtracting(e.allKeys).sorted()
            #expect(
                dangling.isEmpty,
                """
                \(e.name) names field(s) that do not exist: \(dangling).
                A rename has to reach every sentence citing the old name, or the \
                cited figure silently loses what the sentence said about it.
                """)
        }
    }

    // MARK: - 2. Field names in prose are backticked

    /// Rule 1 can only see names in backticks, so a bare name is a hole in it.
    ///
    /// Applied only to names containing an underscore. Those are unambiguously
    /// identifiers; a single-word field name like `merges` is also an ordinary
    /// English plural, and requiring backticks around every use of it would
    /// distort the prose rather than protect it. So single-word field names are
    /// not covered by this rule — rename one and rule 1 will not catch the
    /// stale references.
    @Test func `field names in prose are written in backticks`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }
            let covered = Self.backtickedRanges(in: e.prose)
            var bare: [String] = []

            for key in Self.valueKeys(pc).sorted() where key.contains("_") {
                for range in e.prose.ranges(of: key) {
                    // Skip a name that is part of a longer identifier.
                    if let after = e.prose.indices.contains(range.upperBound) ? e.prose[range.upperBound] : nil,
                        after.isLetter || after.isNumber || after == "_"
                    { continue }
                    if covered.contains(where: { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }) {
                        continue
                    }
                    bare.append(key)
                    break
                }
            }
            #expect(
                bare.isEmpty,
                "\(e.name) writes field name(s) without backticks: \(bare). Rule 1 cannot see them.")
        }
    }

    // MARK: - 3. Every value states its method, and every method has a value

    @Test func `probes and value fields correspond exactly`() throws {
        var checked = 0
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }
            checked += 1
            let how = try #require(pc["how"] as? [String: Any])
            let probes = try #require(how["probes"] as? [String: String])
            let values = Self.valueKeys(pc)
            let described = Set(probes.keys)

            #expect(
                values.subtracting(described).sorted().isEmpty,
                "\(e.name): recorded with no method in how.probes: \(values.subtracting(described).sorted())")
            #expect(
                described.subtracting(values).sorted().isEmpty,
                "\(e.name): how.probes describes absent field(s): \(described.subtracting(values).sorted())")

            // A `_` key is metadata. Moving a measurement under one would drop it
            // out of the correspondence above, so measurements may not hide there.
            for (key, value) in pc where key.hasPrefix("_") {
                #expect(
                    !(value is NSNumber),
                    "\(e.name): \(key) holds a measurement (\(value)) under a metadata key, escaping the method requirement")
            }
        }
        #expect(checked > 0, "no evidence file had a path_coverage block — this test verified nothing")
    }

    /// A probe entry has to say where the number came from. Length alone does not
    /// establish that: the literal name `case_folded_early_return_ids_equal` is 34
    /// characters. Require a backticked identifier or a word that names a method.
    @Test func `each probes entry states a method`() throws {
        for e in try Self.evidenceFiles() {
            guard let how = (e.json["path_coverage"] as? [String: Any])?["how"] as? [String: Any],
                let probes = how["probes"] as? [String: String]
            else { continue }

            for (field, method) in probes.sorted(by: { $0.key < $1.key }) {
                let lowered = method.lowercased()
                let hasIdentifier = !Self.backtickedIdentifiers(in: method).isEmpty
                    || method.contains("`")
                let hasMethodWord = Self.methodWords.contains { lowered.contains($0) }
                #expect(
                    hasIdentifier || hasMethodWord,
                    """
                    \(e.name): how.probes[\(field)] states no method: "\(method)".
                    Name the site in backticks, or say how it was obtained \
                    (\(Self.methodWords.prefix(6).joined(separator: ", "))…).
                    """)
            }
        }
    }

    // MARK: - 4. The counts add up

    /// Internal contracts between recorded counts, not pinned measurements:
    /// re-measuring the corpus changes every number and these still hold.
    @Test func `recorded counts satisfy their arithmetic relationships`() throws {
        for e in try Self.evidenceFiles() {
            guard let pc = e.json["path_coverage"] as? [String: Any] else { continue }
            func n(_ key: String) -> Int? { (pc[key] as? NSNumber)?.intValue }

            let relations: [(String, [String], String, [String])] = [
                ("calls split at the early return",
                 ["case_folded_calls"],
                 "=", ["case_folded_early_return_ids_equal", "case_folded_reached_guard"]),
                ("the guard's two outcomes",
                 ["case_folded_reached_guard"],
                 "=", ["case_folded_guard_else", "case_folded_both_ids_in_map"]),
                ("the guard's else, by cause",
                 ["case_folded_guard_else"],
                 "=", ["case_folded_guard_else_map_nil", "case_folded_guard_else_id_absent"]),
                ("both ids present, by outcome",
                 ["case_folded_both_ids_in_map"],
                 "=", ["case_folded_matches", "case_folded_canonicals_differed"]),
            ]

            for (label, lhsKeys, _, rhsKeys) in relations {
                let lhs = lhsKeys.compactMap(n)
                let rhs = rhsKeys.compactMap(n)
                guard lhs.count == lhsKeys.count, rhs.count == rhsKeys.count else { continue }
                #expect(
                    lhs.reduce(0, +) == rhs.reduce(0, +),
                    """
                    \(e.name): \(label) does not balance — \
                    \(lhsKeys.joined(separator: " + ")) = \(lhs.reduce(0, +)) but \
                    \(rhsKeys.joined(separator: " + ")) = \(rhs.reduce(0, +)).
                    """)
            }
        }
    }
}
